// A blocking standard input, built from a SharedArrayBuffer ring.
//
// The problem it solves: CPython's `fd_read` is synchronous. A REPL has to sit
// inside that call until the student types a line, and a worker cannot await
// anything without returning to its event loop first. `Atomics.wait` is the one
// primitive that parks a thread without unwinding it — so the worker running
// CPython parks there, and the page writes into the same memory and wakes it.
//
// The page MUST be the writer and the worker MUST be the reader. `Atomics.wait`
// throws on the main thread, and a parked worker cannot service `postMessage`,
// so the shared buffer is the only channel that still works once CPython is
// waiting. This is the same arrangement swiftwasm/uwasi and cryptool-org's
// wasm-webterm use.
//
// Requires cross-origin isolation for `SharedArrayBuffer` to exist at all. See
// web/coi-serviceworker.js.

/** Header slots, as Int32 indices. `Atomics.wait` needs an Int32Array. */
const IDX_WRITE = 0;
const IDX_READ = 1;
const IDX_CLOSED = 2;
const IDX_WAITING = 3;

const HEADER_SLOTS = 4;
const HEADER_BYTES = HEADER_SLOTS * 4;

/** Room for anything a person can type or paste in one go, and nothing like the
 *  size that would make it worth growing. */
const DEFAULT_CAPACITY = 64 * 1024;

/** Allocates a channel. Returns the raw buffer, which is what crosses to the
 *  worker in a postMessage. */
export function createChannel(capacity = DEFAULT_CAPACITY) {
  return new SharedArrayBuffer(HEADER_BYTES + capacity);
}

/** Whether this browser can host one at all — false without cross-origin
 *  isolation, which is what makes SharedArrayBuffer absent rather than broken. */
export function isSupported() {
  return typeof SharedArrayBuffer === 'function' && globalThis.crossOriginIsolated === true;
}

function headerOf(channel) {
  return new Int32Array(channel, 0, HEADER_SLOTS);
}

function dataOf(channel) {
  return new Uint8Array(channel, HEADER_BYTES);
}

/** Appends UTF-8 bytes and wakes the reader.
 *
 *  Returns how many bytes were taken. Short of `text` means the ring was full —
 *  the program is not reading, and dropping the tail is better than blocking the
 *  page, which is the one thread that must never block.
 */
export function write(channel, text) {
  const header = headerOf(channel);
  const data = dataOf(channel);
  const capacity = data.length;

  const bytes = new TextEncoder().encode(text);
  const w = Atomics.load(header, IDX_WRITE);
  const r = Atomics.load(header, IDX_READ);

  // One slot stays empty so that `write === read` can only ever mean empty.
  const free = capacity - ((w - r + capacity) % capacity) - 1;
  const count = Math.min(bytes.length, free);
  if (count === 0) return 0;

  const firstRun = Math.min(count, capacity - w);
  data.set(bytes.subarray(0, firstRun), w);
  if (count > firstRun) data.set(bytes.subarray(firstRun, count), 0);

  Atomics.store(header, IDX_WRITE, (w + count) % capacity);
  Atomics.notify(header, IDX_WRITE);
  return count;
}

/** Ends the stream. A parked reader wakes and sees EOF, which is what Ctrl-D
 *  means to the REPL: exit. */
export function close(channel) {
  const header = headerOf(channel);
  Atomics.store(header, IDX_CLOSED, 1);
  Atomics.notify(header, IDX_WRITE);
}

/** True while the program is parked on an empty ring — it has asked for input
 *  and is doing nothing else.
 *
 *  Advisory: it can go stale the instant it is read. Used only to tell a Ctrl-C
 *  that can clear a half-typed line from one that has to stop a running program,
 *  and being wrong there costs an unnecessary restart, not correctness.
 */
export function isWaiting(channel) {
  return Atomics.load(headerOf(channel), IDX_WAITING) === 1;
}

/** The worker half. Hands bytes to the WASI shim's fd 0, blocking until there
 *  are some. */
export class BlockingStdin {

  constructor(channel) {
    this.header = headerOf(channel);
    this.data = dataOf(channel);
    this.capacity = this.data.length;
  }

  /** Blocks until at least one byte is available. An empty result means EOF and
   *  MUST be treated as such by the caller — returning it in a loop would spin. */
  read(max) {
    const r = Atomics.load(this.header, IDX_READ);
    let w = Atomics.load(this.header, IDX_WRITE);

    while (w === r) {
      if (Atomics.load(this.header, IDX_CLOSED) === 1) return new Uint8Array(0);

      Atomics.store(this.header, IDX_WAITING, 1);
      // Expects `w`, so a write landing between the store above and this call
      // returns "not-equal" straight away rather than being lost.
      Atomics.wait(this.header, IDX_WRITE, w);
      Atomics.store(this.header, IDX_WAITING, 0);

      w = Atomics.load(this.header, IDX_WRITE);
    }

    const available = (w - r + this.capacity) % this.capacity;
    const count = Math.min(available, max);
    const out = new Uint8Array(count);

    const firstRun = Math.min(count, this.capacity - r);
    out.set(this.data.subarray(r, r + firstRun), 0);
    if (count > firstRun) out.set(this.data.subarray(0, count - firstRun), firstRun);

    Atomics.store(this.header, IDX_READ, (r + count) % this.capacity);
    return out;
  }

}
