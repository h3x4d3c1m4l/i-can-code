// Runs CPython off the main thread.
//
// Being in a worker is not about smoothness, it is the stop button: a student
// will write `while True:` and the only reliable way to end that is for the
// main thread to terminate this worker outright. Nothing here needs to
// cooperate, because nothing here can be trusted to.
//
// Each run instantiates a fresh module. CPython calls proc_exit when its main()
// finishes, which unwinds the instance, so instances are single-use by nature.
// The compile is the expensive half, and the page does it once for every worker.

import { Wasi, WasiExit } from './wasi.js';
import { STDLIB_DIRECTORIES, STDLIB_ZIP } from './stdlib_layout.js';

/** Per-stream output cap. A run's output is held here until it ends and then
 *  posted to the page in one message, so a runaway `while True: print(x)` would
 *  otherwise grow both until the tab gives out. `PythonAttemptRunner.outputCap`
 *  MUST match it. */
const MAX_OUTPUT_BYTES = 256 * 1024;

/** The environment every interpreter is started with — a student's program and
 *  the version probe alike. */
const PYTHON_ENV = {
  PYTHONHOME: '/',
  // Without this CPython caches a .pyc beside every module a program
  // imports, so a lesson about listing files would find a __pycache__ nobody
  // wrote sitting in the middle of its output.
  PYTHONDONTWRITEBYTECODE: '1',
  // Output is captured at the end rather than streamed, so buffering would
  // only risk losing the tail of a program that dies mid-write.
  PYTHONUNBUFFERED: '1',
};

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

/** Takes the module the page compiled (`python_build_web.dart`), so a worker
 *  started after a Stop costs an instantiate rather than a compile. */
function init({ module, stdlib: zip }) {
  compiled = module;
  stdlib = new Uint8Array(zip);
}

/** Instantiates a fresh interpreter and runs it to completion.
 *
 *  How it ends is the caller's problem, and there are two endings: a program
 *  that runs exits through proc_exit, which throws WasiExit out of _start, while
 *  an interpreter that answers before it gets that far — `-V` — returns from
 *  _start normally. Either way the instance is spent. */
async function start(wasi) {
  const instance = await WebAssembly.instantiate(compiled, wasi.imports());
  wasi.memory = instance.exports.memory;
  instance.exports._start();
}

/** What the interpreter says it is — "Python 3.15.0" — asked of the build that
 *  is actually loaded rather than written down anywhere in the app.
 *
 *  `-V` because the answer then carries the name as well as the number, and
 *  neither has to be assembled here. It writes to stdout and it is cheap: one
 *  extra instantiate, measured at ~4ms against a compile of a 7 MB module.
 *
 *  Its failure is not startup's failure: a runtime that cannot name itself still
 *  runs code, so this answers null and whoever shows it falls back. */
async function probeVersion() {
  const out = new Collector();
  const wasi = new Wasi({
    args: ['python', '-V'],
    env: PYTHON_ENV,
    files: new Map([[STDLIB_ZIP, stdlib]]),
    readOnlyPaths: [STDLIB_ZIP],
    directories: STDLIB_DIRECTORIES,
    stdin: new Uint8Array(0),
    onOutput: (kind, bytes) => { if (kind === 'stdout') out.add(bytes); },
  });

  try {
    await start(wasi);
  } catch (error) {
    if (!(error instanceof WasiExit) || error.code !== 0) return null;
  }
  return out.text().trim() || null;
}

async function run({ code, stdin }) {
  const started = performance.now();
  const stdout = new Collector();
  const stderr = new Collector();

  // The program is given a real filename rather than passed with -c, so a
  // traceback names main.py and quotes the offending line instead of saying
  // "<string>". That difference matters a lot when a class is reading the error.
  const files = new Map([
    [STDLIB_ZIP, stdlib],
    ['/main.py', new TextEncoder().encode(code)],
  ]);

  const wasi = new Wasi({
    args: ['python', '/main.py'],
    env: PYTHON_ENV,
    files,
    // The zip is the only thing here a program must not be able to break:
    // zipimport re-opens it on every import, so emptying it ends the run with
    // an EOFError that names nothing the student did.
    readOnlyPaths: [STDLIB_ZIP],
    directories: STDLIB_DIRECTORIES,
    stdin: new TextEncoder().encode(stdin ?? ''),
    onOutput: (kind, bytes) => (kind === 'stdout' ? stdout : stderr).add(bytes),
  });

  let exitCode = 0;
  try {
    await start(wasi);
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
      init(message);
      self.postMessage({ type: 'ready', version: await probeVersion() });
    } else if (message.type === 'run') {
      const result = await run(message);
      self.postMessage({ type: 'result', id: message.id, ...result });
    }
  } catch (error) {
    self.postMessage({ type: 'failed', id: message.id, message: String(error) });
  }
};
