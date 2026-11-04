// A mailbox for files, from the page to an interpreter that is parked in a read.
//
// The console's worker cannot be sent a message once CPython is running (see
// python_repl_worker.js), so a file typed on the page reaches it the way a line
// does: through shared memory. The page fills the mailbox and wakes the reader
// on the stdin channel, and the worker empties it in its `idle`, which runs
// whenever CPython asks for input. At a prompt that is at once; while a program
// is busy it is the next `input()`.
//
// One batch at a time. The worker posts `filesTaken` when it has emptied the
// mailbox, and the page holds anything newer until then.

import { wake } from './stdin_channel.js';

const IDX_FULL = 0;
const IDX_LENGTH = 1;

const HEADER_SLOTS = 2;
const HEADER_BYTES = HEADER_SLOTS * 4;

const OP_PUT = 1;
const OP_REMOVE = 2;

/** Room for one file of `PythonRepl.maxPutBytes` (1 MiB) and its path. MUST
 *  stay above that, or a put the page accepted could never be sent. */
const DEFAULT_CAPACITY = 2 * 1024 * 1024;

/** Allocates a mailbox. Returns the raw buffer, which crosses to the worker in
 *  its `start` message. */
export function createFileChannel(capacity = DEFAULT_CAPACITY) {
  return new SharedArrayBuffer(HEADER_BYTES + capacity);
}

/** The page half. Puts as many of `ops` as fit, in order, and wakes the reader
 *  on `stdinChannel`. Returns how many it took, which is none while the worker
 *  has not taken the last batch.
 *
 *  An op is `{ path, bytes }` to write a file, or `{ path, bytes: null }` to
 *  remove one. `path` is relative to the interpreter's root. */
export function sendFiles(channel, stdinChannel, ops) {
  const header = new Int32Array(channel, 0, HEADER_SLOTS);
  if (Atomics.load(header, IDX_FULL) !== 0) return 0;

  const data = new Uint8Array(channel, HEADER_BYTES);
  const view = new DataView(channel, HEADER_BYTES);
  const encoder = new TextEncoder();

  // The count goes first and is written last, once it is known.
  let at = 4;
  let taken = 0;
  for (const op of ops) {
    const path = encoder.encode(op.path);
    const bytes = op.bytes ?? null;
    const size = 1 + 4 + path.length + 4 + (bytes?.length ?? 0);
    if (at + size > data.length) break;

    view.setUint8(at, bytes ? OP_PUT : OP_REMOVE);
    view.setUint32(at + 1, path.length, true);
    data.set(path, at + 5);
    at += 5 + path.length;
    view.setUint32(at, bytes?.length ?? 0, true);
    if (bytes) data.set(bytes, at + 4);
    at += 4 + (bytes?.length ?? 0);
    taken += 1;
  }
  if (taken === 0) return 0;

  view.setUint32(0, taken, true);
  Atomics.store(header, IDX_LENGTH, at);
  Atomics.store(header, IDX_FULL, 1);
  wake(stdinChannel);
  return taken;
}

/** The worker half. Empties the mailbox, or returns null when it is empty. */
export function takeFiles(channel) {
  const header = new Int32Array(channel, 0, HEADER_SLOTS);
  if (Atomics.load(header, IDX_FULL) === 0) return null;

  // Copied out first: TextDecoder refuses a view on shared memory, and the
  // page may refill the mailbox the moment it is marked empty.
  const length = Atomics.load(header, IDX_LENGTH);
  const copy = new Uint8Array(length);
  copy.set(new Uint8Array(channel, HEADER_BYTES, length));
  Atomics.store(header, IDX_FULL, 0);

  const view = new DataView(copy.buffer);
  const decoder = new TextDecoder();
  const ops = [];
  let at = 4;
  for (let i = view.getUint32(0, true); i > 0; i--) {
    const kind = view.getUint8(at);
    const pathLength = view.getUint32(at + 1, true);
    const path = decoder.decode(copy.subarray(at + 5, at + 5 + pathLength));
    at += 5 + pathLength;
    const size = view.getUint32(at, true);
    const bytes = kind === OP_PUT ? copy.slice(at + 4, at + 4 + size) : null;
    at += 4 + size;
    ops.push({ path, bytes });
  }
  return ops;
}
