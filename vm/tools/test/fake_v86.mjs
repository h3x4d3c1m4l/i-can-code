// Just enough of v86 to test the host's own logic without an image: the TSC
// arithmetic of src/rust/cpu/cpu.rs, a CPU that starts and stops, and a 9p
// storage that asks load_from_server for any file it does not hold.

import { createHash } from 'node:crypto';

const U64 = (1n << 64n) - 1n;

/** A rootfs file named the way copy-to-sha256.py names one: by the first ten
 *  hex digits of its content's sha256. */
export const HASHED = (() => {
  const content = new TextEncoder().encode('print("named by what is in it")');
  const name = `${createHash('sha256').update(content).digest('hex').slice(0, 10)}.bin`;
  return { path: '/usr/lib/hashed.py', content, name };
})();

/** Stands in for performance.now(), which v86 calls microtick(). */
export class FakeClock {

  ms = 1000;

  advance(ms) {
    this.ms += ms;
  }

}

class FakeCpu {

  current_tsc = new Uint32Array(2);
  wasm_memory = { buffer: { byteLength: 150 * 1024 * 1024 } };
  #offset = 0n;
  #clock;

  constructor(clock) {
    this.#clock = clock;
    this.set_tsc(0, 0);
  }

  /** read_tsc, less the extrapolation between coarse performance.now() ticks. */
  tsc() {
    return (BigInt(Math.round(this.#clock.ms * 1e6)) - this.#offset) & U64;
  }

  /** set_tsc as v86 has it: the offset is computed from a TSC the old offset
   *  has already been taken off. */
  set_tsc(low, high) {
    const value = BigInt(low >>> 0) | (BigInt(high >>> 0) << 32n);
    this.#offset = (this.tsc() - value) & U64;
  }

  store_current_tsc() {
    const value = this.tsc();
    this.current_tsc[0] = Number(value & 0xFFFFFFFFn);
    this.current_tsc[1] = Number(value >> 32n);
  }

}

class FakeStorage {

  storage = { filedata: new Map() };

  constructor(baseurl) {
    this.baseurl = baseurl.endsWith('/') ? baseurl : `${baseurl}/`;
  }

  /** ServerFileStorageWrapper.read from src/browser/filestorage.js. */
  async read(name, offset, count, size) {
    const data = this.storage.filedata.get(name);
    if (data) return data.subarray(offset, offset + count);
    const whole = await this.load_from_server(name, size);
    return whole.subarray(offset, offset + count);
  }

  async cache(name, data) {
    this.storage.filedata.set(name, data);
  }

  load_from_server() {
    throw new Error('The host was meant to replace load_from_server.');
  }

  /** What CloseInode calls on every close; upstream it forgets the file. */
  uncache(name) {
    this.storage.filedata.delete(name);
  }

  zstd_decompress() {
    throw new Error('The fake rootfs holds no compressed files.');
  }

}

const DIR = 0x41ED;
const FILE = 0x81A4;

function inode(mode, entries = {}, sha256sum = '') {
  return { mode, sha256sum, direntries: new Map(Object.entries(entries)) };
}

/** A rootfs of four files in /usr/lib, each stored under its name plus `.bin`
 *  but hashed.py, stored under its content's name (HASHED). */
class FakeFs {

  static FILES = ['this.py', 'big1', 'big2', 'hashed.py'];

  inodedata = {};
  inodes = [
    inode(DIR, { usr: 1 }),
    inode(DIR, { '.': 1, '..': 0, lib: 2 }),
    inode(DIR, { '.': 2, '..': 1, ...Object.fromEntries(FakeFs.FILES.map((name, i) => [name, 3 + i])) }),
    ...FakeFs.FILES.map(name => inode(FILE, {}, name === 'hashed.py' ? HASHED.name : `${name.replace(/\..*/, '')}.bin`)),
  ];

  constructor(baseurl) {
    this.storage = new FakeStorage(baseurl);
  }

  /** What 9p's Tread ends up calling for a file still on the server. */
  read(path) {
    const { sha256sum } = this.#inode(path);
    return this.storage.read(sha256sum, 0, 64, 64);
  }

  /** What CloseInode does for a file still on the server. */
  close(path) {
    this.storage.uncache(this.#inode(path).sha256sum);
  }

  #inode(path) {
    return this.inodes[3 + FakeFs.FILES.indexOf(path.replace('/usr/lib/', ''))];
  }

}

/** A snapshot is 8 bytes here: the TSC it was saved at. */
export function fakeSnapshot(tscNs) {
  const bytes = new ArrayBuffer(8);
  new DataView(bytes).setBigUint64(0, tscNs, true);
  return bytes;
}

/**
 * @param {FakeClock} clock
 * @param {(emulator: object) => object} [makeAgent] The guest on ttyS1: an object with
 *     receive(bytes) and reset(), which answers through emulator.agentSend(bytes).
 * @param {{loadAfterMs?: number}} [loading] Read by each emulator as it is built. With
 *     `loadAfterMs`, `v86` appears that much later, as the real starter sets it only once
 *     wasm_fn resolves, and emulator-loaded follows.
 */
export function fakeV86(clock, makeAgent = null, loading = {}) {
  return class FakeV86 {

    cpu_is_running = false;
    /** Files the host wrote with create_file, by guest path. A restore drops them. */
    files = new Map();
    #listeners = new Map();
    #pending = [];

    constructor(options) {
      this.options = options;
      this.fs9p = new FakeFs(options.filesystem.baseurl);
      this.agent = makeAgent?.(this) ?? null;
      const loaded = () => {
        this.v86 = { cpu: new FakeCpu(clock) };
        this.#emit('emulator-loaded');
      };
      if (loading.loadAfterMs > 0) setTimeout(loaded, loading.loadAfterMs);
      else queueMicrotask(loaded);
    }

    add_listener(name, listener) {
      if (!this.#listeners.has(name)) this.#listeners.set(name, []);
      this.#listeners.get(name).push(listener);
    }

    async run() {
      if (this.cpu_is_running) return;
      this.cpu_is_running = true;
      this.#emit('emulator-started');
      this.#deliver();
    }

    async stop() {
      if (!this.cpu_is_running) return;
      this.cpu_is_running = false;
      this.#emit('emulator-stopped');
    }

    /** cpu.set_state's part in this: the saved TSC goes through set_tsc. */
    async restore_state(state) {
      const saved = new DataView(state).getBigUint64(0, true);
      this.v86.cpu.set_tsc(Number(saved & 0xFFFFFFFFn), Number(saved >> 32n));
      this.files.clear();
      this.#pending.length = 0;
      this.agent?.reset();
    }

    async create_file(file, data) {
      this.files.set(file, data);
    }

    /** The UART queues what the host sends; a guest reads it only while its CPU runs. */
    serial_send_bytes(index, bytes) {
      if (index !== 1) return;
      this.#pending.push(Uint8Array.from(bytes));
      queueMicrotask(() => this.#deliver());
    }

    /** What the agent writes to ttyS1. */
    agentSend(bytes) {
      for (const byte of bytes) this.#emit('serial1-output-byte', byte);
    }

    /** Throws without a wasm instance, as the real one does. */
    async destroy() {
      if (!this.v86) throw new TypeError('Cannot read properties of undefined (reading \'destroy\')');
      await this.stop();
      this.destroyed = true;
    }

    #deliver() {
      if (!this.cpu_is_running || !this.agent) return;
      for (const bytes of this.#pending.splice(0)) this.agent.receive(bytes);
    }

    #emit(name, value) {
      for (const listener of this.#listeners.get(name) ?? []) listener(value);
    }

  };
}
