// Runs CPython off the main thread.
//
// Being in a worker is not about smoothness, it is the stop button: a pupil will
// write `while True:` and the only reliable way to end that is for the main
// thread to terminate this worker outright. Nothing here needs to cooperate,
// because nothing here can be trusted to.
//
// Each run instantiates a fresh module. CPython calls proc_exit when its main()
// finishes, which unwinds the instance, so instances are single-use by nature —
// but the compile is cached, which is the expensive half.

import { Wasi, WasiExit } from './wasi.js';

/** Per-stream output cap. Output is mirrored to other screens and saved with the
 *  board, so a runaway `while True: print(x)` must not be allowed to grow the
 *  board file without bound. */
const MAX_OUTPUT_BYTES = 256 * 1024;

let compiled = null;
let stdlib = null;

class Collector {
  constructor() {
    this.chunks = [];
    this.bytes = 0;
    this.truncated = false;
  }

  add(chunk) {
    if (this.bytes >= MAX_OUTPUT_BYTES) {
      this.truncated = true;
      return;
    }
    const room = MAX_OUTPUT_BYTES - this.bytes;
    if (chunk.length > room) {
      this.chunks.push(chunk.subarray(0, room));
      this.bytes = MAX_OUTPUT_BYTES;
      this.truncated = true;
      return;
    }
    this.chunks.push(chunk);
    this.bytes += chunk.length;
  }

  text() {
    const merged = new Uint8Array(this.bytes);
    let offset = 0;
    for (const chunk of this.chunks) {
      merged.set(chunk, offset);
      offset += chunk.length;
    }
    return new TextDecoder().decode(merged);
  }
}

async function init({ wasmUrl, stdlibUrl }) {
  // Deliberately not compileStreaming. That refuses anything not served as
  // `application/wasm`, and Flutter's dev server sends a generic type for
  // assets — so streaming works in a production build and fails with
  // "Incorrect response MIME type" the moment anyone runs the app from the IDE.
  // Compiling from the buffer costs one extra copy of a 7 MB file, once, and
  // works on any server.
  const [wasmBytes, zip] = await Promise.all([
    fetchStrict(wasmUrl),
    fetchStrict(stdlibUrl),
  ]);
  assertWasm(wasmBytes, wasmUrl);
  compiled = await WebAssembly.compile(wasmBytes);
  stdlib = new Uint8Array(zip);
}

async function fetchStrict(url) {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`${response.status} fetching ${url}`);
  }
  return response.arrayBuffer();
}

/** Turns the least helpful error in this pipeline into the most helpful one.
 *
 *  A single-page server answers a missing asset with index.html and a 200, so a
 *  wrong URL arrives as HTML and surfaces from the compiler as "expected magic
 *  word 00 61 73 6d, found 3c 21 44 4f" — which is `<!DO`, and says nothing
 *  about the actual mistake. Checking the four magic bytes here names it. */
function assertWasm(buffer, url) {
  const header = new Uint8Array(buffer, 0, Math.min(4, buffer.byteLength));
  const isWasm = header[0] === 0x00 && header[1] === 0x61 && header[2] === 0x73 && header[3] === 0x6d;
  if (isWasm) return;

  const looksLikeHtml = header[0] === 0x3c; // '<'
  throw new Error(
    looksLikeHtml
      ? `${url} returned HTML, not WebAssembly — the asset URL is wrong and the `
        + 'server answered with index.html.'
      : `${url} is not a WebAssembly module.`);
}

async function run({ code, stdin }) {
  const started = performance.now();
  const stdout = new Collector();
  const stderr = new Collector();

  // The program is given a real filename rather than passed with -c, so a
  // traceback names main.py and quotes the offending line instead of saying
  // "<string>". That difference matters a lot when a class is reading the error.
  const files = new Map([
    ['/python314.zip', stdlib],
    ['/main.py', new TextEncoder().encode(code)],
  ]);

  const wasi = new Wasi({
    args: ['python', '/main.py'],
    env: {
      PYTHONHOME: '/',
      PYTHONPATH: '/python314.zip',
      // Without this CPython tries to write .pyc files next to the source and
      // the read-only filesystem refuses, noisily.
      PYTHONDONTWRITEBYTECODE: '1',
      // Output is captured at the end rather than streamed, so buffering would
      // only risk losing the tail of a program that dies mid-write.
      PYTHONUNBUFFERED: '1',
    },
    files,
    stdin: new TextEncoder().encode(stdin ?? ''),
    onOutput: (kind, bytes) => (kind === 'stdout' ? stdout : stderr).add(bytes),
  });

  let exitCode = 0;
  try {
    const instance = await WebAssembly.instantiate(compiled, wasi.imports());
    wasi.memory = instance.exports.memory;
    instance.exports._start();
  } catch (error) {
    if (error instanceof WasiExit) {
      exitCode = error.code;
    } else if (error instanceof WebAssembly.RuntimeError && /stack|recursion/i.test(error.message)) {
      // The shadow stack is fixed at link time, so this cannot be widened from
      // here — it means the program recursed too deep.
      exitCode = 1;
      stderr.add(new TextEncoder().encode(
        'RecursionError: too much nesting for this sandbox\n'));
    } else {
      exitCode = 1;
      stderr.add(new TextEncoder().encode(`${error}\n`));
    }
  }

  return {
    stdout: stdout.text(),
    stderr: stderr.text(),
    exitCode,
    truncated: stdout.truncated || stderr.truncated,
    durationMs: Math.round(performance.now() - started),
  };
}

self.onmessage = async (event) => {
  const message = event.data;
  try {
    if (message.type === 'init') {
      await init(message);
      self.postMessage({ type: 'ready' });
    } else if (message.type === 'run') {
      const result = await run(message);
      self.postMessage({ type: 'result', id: message.id, ...result });
    }
  } catch (error) {
    self.postMessage({ type: 'failed', id: message.id, message: String(error) });
  }
};
