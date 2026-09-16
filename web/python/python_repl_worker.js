// Runs one long-lived CPython at an interactive prompt.
//
// The sibling worker (python_worker.js) runs a program and returns what it
// printed. This one starts CPython with `-i` and then never returns: `_start()`
// blocks this thread for as long as the session lasts, parked inside `fd_read`
// between lines. That is not a workaround — it is what the real REPL does, and
// what makes `x = 1` on one line still be there on the next.
//
// Consequences of the thread being blocked, all deliberate:
//
//  * Input cannot arrive by postMessage, because this worker will not reach its
//    event loop again. It arrives through the SharedArrayBuffer in
//    stdin_channel.js, written by the page.
//  * Output still leaves by postMessage. Posting from a blocked stack is fine;
//    the message is queued to the page, whose event loop is running.
//  * Stopping is termination from outside, exactly as it is for the runner.
//    Nothing here can be asked to stop, so nothing here is asked.
//
// The interpreter is single-use: CPython calls proc_exit when the session ends,
// which unwinds the instance. A new session is a new worker.

import { Wasi, WasiExit } from './wasi.js';
import { BlockingStdin } from './stdin_channel.js';

/** How long output may sit in the worker before it is posted. One frame. */
const FLUSH_INTERVAL_MS = 16;

let compiled = null;
let stdlib = null;

async function init({ wasmUrl, stdlibUrl }) {
  // Not compileStreaming, for the same reason as python_worker.js: Flutter's
  // dev server does not send `application/wasm`, so streaming would work in a
  // release build and fail the moment anyone ran the app from the IDE.
  const [wasmBytes, zip] = await Promise.all([
    fetchStrict(wasmUrl),
    fetchStrict(stdlibUrl),
  ]);
  compiled = await WebAssembly.compile(wasmBytes);
  stdlib = new Uint8Array(zip);
}

async function fetchStrict(url) {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`${response.status} fetching ${url}`);
  return response.arrayBuffer();
}

/** Never returns while the session lives. */
async function start({ channel }) {
  // One decoder per stream, kept across writes: a multi-byte character can be
  // split over two fd_writes, and a fresh decoder would turn the halves into
  // two replacement characters.
  const decoders = {
    stdout: new TextDecoder('utf-8', { fatal: false }),
    stderr: new TextDecoder('utf-8', { fatal: false }),
  };

  const stdin = new BlockingStdin(channel);

  let pending = [];
  let lastFlush = 0;

  function flush() {
    lastFlush = performance.now();
    if (pending.length === 0) return;
    self.postMessage({ type: 'output', chunks: pending });
    pending = [];
  }

  const wasi = new Wasi({
    // `-i` forces the interactive loop even though stdin is not a terminal,
    // which is the whole trick: without it CPython would read stdin to the end
    // and run it as a script, printing nothing back.
    //
    // `-u` because a prompt that sits in a buffer is a prompt nobody sees.
    args: ['python', '-i', '-u'],
    env: {
      PYTHONHOME: '/',
      PYTHONPATH: '/python314.zip',
      PYTHONDONTWRITEBYTECODE: '1',
      PYTHONUNBUFFERED: '1',
      // 3.13 shipped a new REPL that drives the terminal itself through
      // termios, which wasm32-wasi does not have. It would discover that and
      // fall back anyway; asking for the classic one outright keeps the
      // behaviour the same across CPython versions instead of depending on how
      // that probe happens to fail.
      PYTHON_BASIC_REPL: '1',
      // What is on the other end really is an xterm-compatible emulator, so
      // saying so is not a courtesy — it is what turns CPython 3.13+'s
      // colourised tracebacks on. Line editing, history and echo are still the
      // page's job, because the basic REPL does none of them.
      TERM: 'xterm-256color',
    },
    // No /main.py: there is no program, only the prompt.
    files: new Map([['/python314.zip', stdlib]]),
    stdinReader: {
      // Flushing here is what keeps the prompt from arriving late: CPython
      // writes `>>> ` and then asks for a line, and this worker is about to
      // park for as long as the student takes to type it. Whatever is still
      // pending has to leave before that.
      read: (max) => {
        flush();
        return stdin.read(max);
      },
    },
    // Without this isatty() is false — our shim hands out the FD_SEEK right,
    // and wasi-libc reads a seekable character device as a redirected file —
    // and CPython drops the colour again. Verified: it is this, not TERM, that
    // decides. Set here and nowhere else: python_worker.js renders its output
    // as plain text, where the same escape codes are just noise.
    stdioIsTerminal: true,
    onOutput: (kind, bytes) => {
      const text = decoders[kind].decode(bytes, { stream: true });
      if (text.length > 0) pending.push({ kind, text });
      // A `while True: print(x)` writes unbuffered, which is one fd_write and
      // so one postMessage per line. Coalescing keeps that from drowning the
      // page's event loop in messages it can only render sixty times a second
      // anyway.
      if (performance.now() - lastFlush >= FLUSH_INTERVAL_MS) flush();
    },
  });

  const instance = await WebAssembly.instantiate(compiled, wasi.imports());
  wasi.memory = instance.exports.memory;

  self.postMessage({ type: 'started' });

  let code = 0;
  try {
    instance.exports._start();
  } catch (error) {
    if (error instanceof WasiExit) {
      code = error.code;
    } else if (error instanceof WebAssembly.RuntimeError && /stack|recursion/i.test(error.message)) {
      // The shadow stack is fixed at link time. Unlike a single run, this ends
      // the session: the interpreter's own stack is what overflowed.
      code = 1;
      pending.push({ kind: 'stderr', text: '\r\nRecursionError: too much nesting for this sandbox\r\n' });
    } else {
      code = 1;
      pending.push({ kind: 'stderr', text: `\r\n${error}\r\n` });
    }
  }

  flush();
  self.postMessage({ type: 'exited', code });
}

self.onmessage = async (event) => {
  const message = event.data;
  try {
    if (message.type === 'init') {
      await init(message);
      self.postMessage({ type: 'ready' });
    } else if (message.type === 'start') {
      // Blocks this worker for the rest of the session. Nothing may be posted
      // to it after this.
      await start(message);
    }
  } catch (error) {
    self.postMessage({ type: 'failed', message: String(error) });
  }
};
