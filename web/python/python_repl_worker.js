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
//
// Given a `program`, it runs that as /main.py instead of starting a prompt, and
// exits when the program does. Everything above still holds: `input()` parks in
// the same read, so the program reads from the terminal as it would in one.
//
// The student's files live in the root beside it, the folder the console and
// the program page share. They arrive with `start`, later ones through the
// mailbox in file_channel.js, and what the program does to them goes back to
// the page as `files` messages: whenever CPython asks for input, when it closes
// a file it wrote (at most every REPORT_INTERVAL_MS), and when it exits. A run
// that is stopped loses what it wrote since the last of those.

import { Wasi, WasiExit } from './wasi.js';
import { BlockingStdin } from './stdin_channel.js';
import { takeFiles } from './file_channel.js';
import { STDLIB_DIRECTORIES, STDLIB_ZIP } from './stdlib_layout.js';

/** How long output may sit in the worker before it is posted. One frame. */
const FLUSH_INTERVAL_MS = 16;

/** How often closing a file reports the folder, at most. A program that writes
 *  a file in a loop would otherwise post the folder once per pass. */
const REPORT_INTERVAL_MS = 250;

/** The most files the folder reports. Bounded because a program can make any
 *  number, and each one is a copy posted to the page. */
const MAX_REPORTED_FILES = 200;

/** What in the root is the app's and not the student's: the standard library,
 *  /tmp, /dev and the program itself. `kReservedFolderNames` in
 *  lib/services/folder_store.dart MUST name the same. */
const NOT_THE_FOLDER = new Set([STDLIB_ZIP.split('/')[1], 'tmp', 'dev', 'main.py']);

let compiled = null;
let stdlib = null;

/** Takes the module the page compiled (`python_build_web.dart`), the same one
 *  the lesson runner gets, so a console started after a lesson compiles nothing. */
function init({ module, stdlib: zip }) {
  compiled = module;
  stdlib = new Uint8Array(zip);
}

/** Never returns while the session lives. */
async function start({ channel, fileChannel, files, program }) {
  const runsProgram = typeof program === 'string';
  // One decoder per stream, kept across writes: a multi-byte character can be
  // split over two fd_writes, and a fresh decoder would turn the halves into
  // two replacement characters.
  const decoders = {
    stdout: new TextDecoder('utf-8', { fatal: false }),
    stderr: new TextDecoder('utf-8', { fatal: false }),
  };

  let pending = [];
  let lastFlush = 0;

  function flush() {
    lastFlush = performance.now();
    if (pending.length === 0) return;
    self.postMessage({ type: 'output', chunks: pending });
    pending = [];
  }

  // What the page last heard about each file in the folder, by path, so only
  // what changed since is posted.
  let reported = new Map();
  let reportedChanges = -1;
  let lastReport = 0;
  // Paths whose last word from the page did not land, and which are posted as
  // they really are so the page does not go on showing what it asked for.
  const refused = new Set();

  const stamp = (node) => ({ ino: node.ino, version: node.version });

  function reportFiles() {
    lastReport = performance.now();
    if (wasi.changes === reportedChanges && refused.size === 0) return;
    reportedChanges = wasi.changes;

    const now = wasi.files(NOT_THE_FOLDER, MAX_REPORTED_FILES);
    const changed = [];
    for (const [path, node] of now) {
      const seen = reported.get(path);
      if (seen && seen.ino === node.ino && seen.version === node.version && !refused.has(path)) continue;
      changed.push({ path, bytes: node.data.slice() });
    }
    const removed = [...reported.keys(), ...refused].filter((path) => !now.has(path));
    reported = new Map([...now].map(([path, node]) => [path, stamp(node)]));
    refused.clear();

    if (changed.length === 0 && removed.length === 0) return;
    const transfer = changed.map((file) => file.bytes.buffer);
    self.postMessage({ type: 'files', changed, removed: [...new Set(removed)] }, transfer);
  }

  /** What the page put in the mailbox, applied, and recorded as already known
   *  to it so it does not come back as a change. */
  function takePageFiles() {
    const ops = takeFiles(fileChannel);
    if (ops === null) return;

    for (const { path, bytes } of ops) {
      const at = `/${path}`;
      // Removing a file that is already gone has done what was asked.
      const done = bytes ? wasi.writeFile(at, bytes) : wasi.removeFile(at) || !wasi.resolve(at).node;
      if (!done) {
        refused.add(path);
        continue;
      }
      const node = wasi.resolve(at).node;
      if (node) reported.set(path, stamp(node));
      else reported.delete(path);
    }
    self.postMessage({ type: 'filesTaken' });
  }

  const stdin = new BlockingStdin(channel, {
    // Flushing here is what keeps the prompt from arriving late: CPython
    // writes `>>> ` and then asks for a line, and this worker is about to
    // park for as long as the student takes to type it. Whatever is still
    // pending has to leave before that.
    idle: () => {
      takePageFiles();
      reportFiles();
      flush();
    },
  });

  const wasi = new Wasi({
    // `-i` forces the interactive loop even though stdin is not a terminal,
    // which is the whole trick: without it CPython would read stdin to the end
    // and run it as a script, printing nothing back.
    //
    // `-u` because a prompt that sits in a buffer is a prompt nobody sees.
    //
    // A program is given a real filename rather than passed with -c, for the
    // reason python_worker.js gives: a traceback then quotes the line.
    args: runsProgram ? ['python', '-u', '/main.py'] : ['python', '-i', '-u'],
    env: {
      PYTHONHOME: '/',
      // No .pyc files beside the modules a session imports: they would
      // outlive nothing and show up in the next os.listdir at the prompt.
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
    files: new Map([
      [STDLIB_ZIP, stdlib],
      ...(runsProgram ? [['/main.py', new TextEncoder().encode(program)]] : []),
    ]),
    // Writable from the prompt, except the zip every import reads from. This
    // filesystem lives as long as the session, not as long as one run.
    readOnlyPaths: [STDLIB_ZIP],
    directories: STDLIB_DIRECTORIES,
    stdinReader: stdin,
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
    onFileClosed: () => {
      if (performance.now() - lastReport >= REPORT_INTERVAL_MS) reportFiles();
    },
  });

  // Written after the tree is built rather than handed to it, so the folder is
  // charged to the quota: what a run leaves behind is then never more than the
  // quota, however many runs it has been through.
  for (const { path, bytes } of files ?? []) {
    if (!wasi.writeFile(`/${path}`, bytes)) refused.add(path);
  }
  reported = new Map([...wasi.files(NOT_THE_FOLDER, MAX_REPORTED_FILES)].map(([path, node]) => [path, stamp(node)]));
  reportedChanges = wasi.changes;

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

  reportFiles();
  flush();
  self.postMessage({ type: 'exited', code });
}

self.onmessage = async (event) => {
  const message = event.data;
  try {
    if (message.type === 'init') {
      init(message);
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
