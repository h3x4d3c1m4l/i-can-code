// The page's one v86 machine: built without firmware, restored from a snapshot,
// its CPU stopped whenever nothing needs it to run. vm_run.js drives it; the
// build tools use it directly through createVmHost().
//
// It brings no v86 of its own: a snapshot restores only into the build that
// saved it, so the bundle carries that build and the caller imports it.

import { isLocalPath, never, sleep, toArrayBuffer, withTimeout } from './vm_util.js';
import { Watchdog } from './vm_watchdog.js';

const MiB = 1024 * 1024;

/** v86 reports nothing when its own init throws; it just never fires
 *  emulator-loaded. Past this the host gives up rather than wait forever. */
const LOAD_TIMEOUT_MS = 30_000;

/** README 9.8: one retry, a second later, for a network error or a 5xx. A 404
 *  means a deploy took the file away, and it will not come back. */
const FETCH_RETRY_DELAYS_MS = [1000];

/** One attempt at a rootfs file. A connection that stalls would otherwise hold
 *  the guest's read, and so the student's program, for good. */
const FETCH_ATTEMPT_TIMEOUT_MS = 30_000;

/** Decompressed rootfs files the guest has closed but the host keeps. A run's
 *  working set beyond what the snapshot holds open is a few MiB. */
const ROOTFS_KEEP_BYTES = 16 * MiB;

/** The live machine. A Flutter hot restart re-runs the Dart side but keeps this
 *  module, and with it an emulator nothing can reach any more. */
let current = null;

/**
 * Builds the page's machine and resolves once v86 has loaded. It holds no
 * guest yet: call restoreSnapshot(), then resume().
 *
 * There is one machine per page, so this destroys the previous one first. Two
 * emulators would hold two ~150 MiB wasm memories.
 *
 * @param {object} options
 * @param {Function} options.V86 The V86 class of the build that saved the snapshot.
 * @param {BufferSource | WebAssembly.Module} options.wasm That build's v86.wasm.
 * @param {number} options.memoryMiB MUST be at least the size the snapshot was
 *     saved with; a smaller one fails the restore with an out-of-bounds access.
 * @param {number} options.vgaMiB MUST equal the size the snapshot was saved with.
 * @param {boolean} [options.uart1] MUST match the saving machine. Defaults to true.
 * @param {string} options.rootfsUrl The content-addressed rootfs directory the
 *     snapshot's filesystem refers to.
 * @param {HTMLElement} [options.screen] v86's screen container; none when headless.
 * @param {(event: object) => void} [options.onEvent]
 * @param {(url: string, signal: AbortSignal) => Promise<Uint8Array>} [options.fetchFile]
 *     Replaces how rootfs files are fetched. It MUST reject on failure and MAY
 *     set `status` on the error; a 4xx other than 408 or 429 is not retried.
 * @param {{get: (url: string) => Promise<Uint8Array | null>, put: (url: string, bytes: Uint8Array) => Promise<void>,
 *     delete: (url: string) => Promise<void>}} [options.fileCache] Where rootfs files are kept
 *     between visits (vm_cache.js's RootfsCache). A file is read from it before the network,
 *     and one fetched is put into it once its content matches its name.
 * @param {boolean} [options.trackVisibility] Follow document.visibilityState.
 *     Defaults to true wherever there is a document; headless callers use setVisible().
 * @param {() => number} [options.now] The watchdog's clock, in ms. Tests pass a mocked one.
 * @returns {Promise<VmHost>}
 */
export async function createVmHost(options) {
  const previous = current;
  current = null;
  if (previous) await previous.destroy();

  const host = new VmHost(options);
  current = host;
  try {
    await host.loaded;
  } catch (error) {
    await host.destroy();
    throw error;
  }
  if (host.destroyed) throw new Error('The VM host was destroyed while it loaded.');
  return host;
}

class VmHost {

  /** Resolves once v86 has loaded and the host has hooked into it. */
  loaded;

  /** Counts while the CPU runs and the page is visible, and is suspended while
   *  a rootfs file is on its way. The run layer arms it. */
  watchdog;

  #emulator;
  #cpu = null;
  #onEvent;
  #fetchFile;
  #fileCache;
  #wantRunning = false;
  #visible = true;
  #cpuRunning = false;
  #frozenTsc = null;
  #snapshot = null;
  #epoch = 0;
  #inflight = new Map();
  #fetching = 0;
  #kept = new Map();
  #keptBytes = 0;
  #queue = Promise.resolve();
  #emulatorLoaded;
  #destroyed = false;
  #stopTrackingVisibility = null;
  #stats = { rootfsFetches: 0, rootfsFetchBytes: 0, rootfsCacheHits: 0, staleFetchesDropped: 0, yield: null };

  constructor({
    V86,
    wasm,
    memoryMiB,
    vgaMiB,
    uart1 = true,
    rootfsUrl,
    screen = null,
    onEvent = () => {},
    fetchFile = defaultFetchFile,
    fileCache = null,
    trackVisibility = typeof document !== 'undefined',
    now,
  }) {
    if (typeof V86 !== 'function') throw new TypeError('V86 must be the V86 class');
    if (!wasm) throw new TypeError('wasm is required');
    if (!(memoryMiB > 0) || !(vgaMiB > 0)) throw new TypeError('memoryMiB and vgaMiB are required');
    if (!rootfsUrl) throw new TypeError('rootfsUrl is required');

    this.#onEvent = onEvent;
    this.#fetchFile = fetchFile;
    this.#fileCache = fileCache;
    this.watchdog = new Watchdog({ now });
    this.watchdog.pause('cpu');

    let failLoad;
    const loadFailed = new Promise((_, reject) => { failLoad = reject; });

    // No bios, vga_bios, bzimage, initrd, basefs or initial_state: the machine
    // only ever runs from a restored snapshot, which carries the kernel in RAM
    // and the filesystem tree in its 9p state. emulator-loaded then fires in
    // ~14 ms, and restoreSnapshot() stays the one place a state is restored.
    this.#emulator = new V86({
      wasm_fn: async imports => {
        try {
          const result = await WebAssembly.instantiate(wasm, imports);
          return (result.instance ?? result).exports;
        } catch (error) {
          // v86 chains no catch onto wasm_fn, so a rejection here would only
          // surface as an unhandled one.
          failLoad(error);
          return never();
        }
      },
      memory_size: memoryMiB * MiB,
      vga_memory_size: vgaMiB * MiB,
      uart1,
      filesystem: { baseurl: rootfsUrl },
      autostart: false,
      disable_speaker: true,
      ...(screen
        ? { screen: { container: screen } }
        : { disable_keyboard: true, disable_mouse: true }),
    });

    this.#emulatorLoaded = new Promise(resolve => this.#emulator.add_listener('emulator-loaded', resolve));
    this.loaded = withTimeout(Promise.race([this.#emulatorLoaded, loadFailed]), LOAD_TIMEOUT_MS, 'v86 did not load')
      .then(() => this.#attach(trackVisibility));
  }

  /** The raw V86, for the serial line and the build tools. It MUST NOT be run,
   *  stopped or restored directly: the host's clock bookkeeping would go stale. */
  get emulator() {
    return this.#emulator;
  }

  /** Whether the guest's CPU is executing right now. */
  get running() {
    return this.#cpuRunning;
  }

  get visible() {
    return this.#visible;
  }

  get destroyed() {
    return this.#destroyed;
  }

  /** Rootfs traffic since construction, files served from `fileCache` among it,
   *  and how v86 yields (`channel` or `v86`). A run that fetches nothing is the goal. */
  get stats() {
    return { ...this.#stats };
  }

  /**
   * Parks the machine on `snapshot`: the CPU is stopped afterwards, and
   * resume() continues from the snapshot. Any rootfs fetch still in flight is
   * dropped when it lands, since its request belongs to the machine replaced here.
   *
   * @param {ArrayBuffer | Uint8Array} [snapshot] A v86 state, raw or zstd. A raw
   *     one restores in a third of the time and grows no wasm memory.
   *     Defaults to the last one restored, which the host keeps for this.
   * @returns {Promise<{ms: number, syncMs: number}>} `syncMs` is the part v86
   *     does inside one synchronous call, during which the thread does nothing else.
   */
  restoreSnapshot(snapshot = this.#snapshot) {
    return this.#serially(async () => {
      if (!snapshot) throw new Error('No snapshot to restore.');
      const state = toArrayBuffer(snapshot);
      this.#wantRunning = false;
      await this.#stopCpu();

      // A restore that throws half way leaves no machine worth resuming.
      this.#frozenTsc = null;
      const started = performance.now();
      zeroTscOffset(this.#cpu);
      this.#epoch++;
      this.#fetching = 0;
      this.watchdog.setFetching(false);
      const restored = this.#emulator.restore_state(state);
      const syncMs = performance.now() - started;
      await restored;
      const ms = performance.now() - started;

      this.#frozenTsc = readTsc(this.#cpu);
      this.#snapshot = state;
      return { ms, syncMs };
    });
  }

  /** Lets the guest run: now if the page is visible, otherwise once it is. */
  resume() {
    return this.#serially(() => {
      if (!this.#frozenTsc) throw new Error('restoreSnapshot() must come first.');
      this.#wantRunning = true;
      return this.#applyCpu();
    });
  }

  /** Stops the guest's CPU. Its clock stands still until resume(). */
  pause() {
    return this.#serially(() => {
      this.#wantRunning = false;
      return this.#applyCpu();
    });
  }

  /**
   * A hidden page stops the CPU, so a Tk animation in a background tab does
   * not keep a core busy, and the watchdog stops counting at once rather than
   * after the stop has been queued.
   */
  setVisible(visible) {
    if (visible) this.watchdog.resume('hidden');
    else this.watchdog.pause('hidden');
    return this.#serially(() => {
      this.#visible = visible;
      return this.#applyCpu();
    });
  }

  /** What the machine holds on to, in bytes. Wasm memory only ever grows, so
   *  `wasmBytes` is also its high-water mark. */
  memoryUsage() {
    const fs = this.#emulator.fs9p;
    const cache = fs?.storage?.storage?.filedata;
    let rootfsCacheBytes = 0;
    for (const data of cache?.values() ?? []) rootfsCacheBytes += data.byteLength;
    let guestFileBytes = 0;
    for (const data of Object.values(fs?.inodedata ?? {})) guestFileBytes += data.byteLength;
    return {
      wasmBytes: this.#cpu?.wasm_memory.buffer.byteLength ?? 0,
      snapshotBytes: this.#snapshot?.byteLength ?? 0,
      rootfsCacheBytes,
      rootfsCacheFiles: cache?.size ?? 0,
      guestFileBytes,
    };
  }

  async destroy() {
    if (this.#destroyed) return;
    this.#destroyed = true;
    if (current === this) current = null;
    this.watchdog.stop();
    this.#stopTrackingVisibility?.();
    await this.#queue;
    // v86 creates its wasm instance, the ~150 MiB this frees, only once wasm_fn
    // resolves, so a host destroyed while it loads waits for that.
    await this.loaded.catch(() => {});
    // Without a wasm instance v86 has nothing to free, and its destroy() would
    // throw on the emulator it never created. One that loads after the timeout
    // is freed when it does.
    if (this.#emulator.v86) await this.#emulator.destroy();
    else this.#emulatorLoaded.then(() => this.#emulator.destroy()).catch(console.error);
  }

  #attach(trackVisibility) {
    // Hooking in would add a visibility listener that nothing removes.
    if (this.#destroyed) throw new Error('The VM host was destroyed while it loaded.');
    const cpu = this.#emulator.v86.cpu;
    // current_tsc is a Proxy over wasm memory rather than a Uint32Array, so it
    // is checked by shape.
    if (typeof cpu.set_tsc !== 'function' || typeof cpu.store_current_tsc !== 'function' ||
        cpu.current_tsc?.length !== 2) {
      throw new Error('This v86 build does not expose the TSC internals the restore depends on.');
    }
    const storage = this.#emulator.fs9p?.storage;
    if (typeof storage?.load_from_server !== 'function' || !(storage.storage?.filedata instanceof Map)) {
      throw new Error('This v86 build does not load rootfs files the way the host hooks into.');
    }
    this.#cpu = cpu;
    storage.load_from_server = (name, size) => this.#readRootfsFile(storage, name, size);
    storage.uncache = name => this.#keep(storage.storage.filedata, name);
    this.#stats.yield = yieldThroughChannel(this.#emulator.v86) ? 'channel' : 'v86';

    if (trackVisibility) {
      const onChange = () => {
        this.setVisible(document.visibilityState === 'visible').catch(console.error);
      };
      document.addEventListener('visibilitychange', onChange);
      this.#stopTrackingVisibility = () => document.removeEventListener('visibilitychange', onChange);
      if (document.visibilityState !== 'visible') {
        this.#visible = false;
        this.watchdog.pause('hidden');
      }
    }
  }

  async #applyCpu() {
    const shouldRun = this.#wantRunning && this.#visible;
    if (shouldRun && !this.#cpuRunning) this.#startCpu();
    else if (!shouldRun && this.#cpuRunning) await this.#stopCpu();
  }

  #startCpu() {
    writeTsc(this.#cpu, this.#frozenTsc);
    this.#cpuRunning = true;
    this.#emulator.run();
    this.watchdog.resume('cpu');
  }

  async #stopCpu() {
    if (!this.#cpuRunning) return;
    this.watchdog.pause('cpu');
    await this.#emulator.stop();
    this.#frozenTsc = readTsc(this.#cpu);
    this.#cpuRunning = false;
  }

  #serially(operation) {
    const result = this.#queue.then(() => {
      if (this.#destroyed) throw new Error('The VM host has been destroyed.');
      return operation();
    });
    this.#queue = result.catch(() => {});
    return result;
  }

  // Rootfs files
  //
  // Upstream, a file that cannot be fetched holds the guest's read. In a
  // browser load_file (src/lib.js) logs a 404 and never calls back, and retries
  // a network error or a 5xx without end, backing off to 34 s. Under Node its
  // readFile rejects inside a promise nobody handles, which ends the process.
  // Meanwhile an agent that is not itself waiting on the rootfs goes on
  // answering pings, so no watchdog notices.
  //
  // So the host fetches them itself. The request that failed is still never
  // answered, deliberately: v86 has no error path back to the guest for a read
  // (9p.js awaits fs.Read with no catch), and a reply that arrived after the
  // next restore would write into a guest that never asked for it. Instead the
  // host reports fetch-failed. The run layer ends the run on it and parks,
  // which also discards the stuck request.

  async #readRootfsFile(storage, name, size) {
    const epoch = this.#epoch;
    let load = this.#inflight.get(name);
    if (!load) {
      load = this.#loadRootfsFile(storage, name, size);
      this.#inflight.set(name, load);
      const forget = () => this.#inflight.delete(name);
      load.then(forget, forget);
    }

    this.#fetching++;
    this.watchdog.setFetching(true);
    const settled = () => {
      if (epoch !== this.#epoch) return;
      this.#fetching--;
      if (this.#fetching === 0) this.watchdog.setFetching(false);
    };

    try {
      const data = await load;
      settled();
      if (epoch === this.#epoch && !this.#destroyed) {
        await storage.cache(name, data);
        return data;
      }
    } catch (failure) {
      settled();
      if (epoch === this.#epoch && !this.#destroyed) {
        if (!failure.reported) {
          failure.reported = true;
          this.#emit({ type: 'fetch-failed', ...failure.details });
        }
        return never();
      }
    }
    this.#stats.staleFetchesDropped++;
    return never();
  }

  async #loadRootfsFile(storage, name, size) {
    const url = storage.baseurl + name;
    const started = performance.now();
    const kept = await this.#fileCache?.get(url).catch(() => null);
    if (kept) {
      try {
        const data = name.endsWith('.zst') ? new Uint8Array(storage.zstd_decompress(size, kept)) : kept;
        this.#stats.rootfsCacheHits++;
        this.#emit({ type: 'rootfs-cached', path: this.#pathOf(name), bytes: kept.byteLength, ms: performance.now() - started });
        return data;
      } catch {
        await this.#fileCache.delete(url).catch(() => {});
      }
    }

    let bytes;
    for (let attempt = 0; ; attempt++) {
      try {
        bytes = await this.#fetchOnce(url);
        break;
      } catch (error) {
        const wait = FETCH_RETRY_DELAYS_MS[attempt];
        if (isPermanentFetchError(error) || wait === undefined || this.#destroyed) {
          throw this.#fetchFailure(name, url, error, attempt + 1);
        }
        await sleep(wait);
      }
    }

    let data;
    try {
      data = name.endsWith('.zst') ? new Uint8Array(storage.zstd_decompress(size, bytes)) : bytes;
    } catch (error) {
      throw this.#fetchFailure(name, url, error, 1);
    }

    this.#stats.rootfsFetches++;
    this.#stats.rootfsFetchBytes += bytes.byteLength;
    this.#emit({
      type: 'rootfs-fetched',
      path: this.#pathOf(name),
      bytes: bytes.byteLength,
      ms: performance.now() - started,
    });
    if (this.#fileCache) this.#keepFetched(url, name, bytes, data);
    return data;
  }

  /**
   * Puts a fetched file into `fileCache` once its content is what its name says:
   * a rootfs file is named by the first ten hex digits of its content's sha256
   * (docs/vm-build.md, "The bundle"), and a bad copy kept would be served to
   * every later run. Runs behind the guest's read, which does not wait for it.
   */
  #keepFetched(url, name, bytes, data) {
    const named = /^([0-9a-f]{10})\./.exec(name)?.[1];
    const subtle = globalThis.crypto?.subtle;
    if (!named || !subtle) return;
    subtle.digest('SHA-256', data).then(digest => {
      const hex = Array.from(new Uint8Array(digest, 0, 5), b => b.toString(16).padStart(2, '0')).join('');
      if (hex === named && !this.#destroyed) return this.#fileCache.put(url, bytes);
      return undefined;
    }).catch(() => {});
  }

  async #fetchOnce(url) {
    const controller = new AbortController();
    const timer = setTimeout(
      () => controller.abort(new Error(`No answer within ${FETCH_ATTEMPT_TIMEOUT_MS} ms.`)),
      FETCH_ATTEMPT_TIMEOUT_MS,
    );
    try {
      return await this.#fetchFile(url, controller.signal);
    } finally {
      clearTimeout(timer);
    }
  }

  #fetchFailure(name, url, error, attempts) {
    const failure = new Error(`Could not fetch ${url}: ${error?.message ?? error}`);
    failure.details = {
      path: this.#pathOf(name),
      url,
      status: error?.status ?? null,
      message: String(error?.message ?? error),
      attempts,
    };
    return failure;
  }

  /**
   * Stands in for v86's uncache, which drops a file from memory whenever the
   * guest closes it (CloseInode), so that every command after a restore fetched
   * and decompressed /bin/busybox again. The files are immutable and named by
   * content, so holding on to the most recently closed ones is always correct.
   */
  #keep(filedata, name) {
    const data = filedata.get(name);
    if (!data) return;
    if (this.#kept.has(name)) this.#kept.delete(name);
    else this.#keptBytes += data.byteLength;
    this.#kept.set(name, data.byteLength);
    for (const [oldest, bytes] of this.#kept) {
      if (this.#keptBytes <= ROOTFS_KEEP_BYTES) break;
      this.#kept.delete(oldest);
      this.#keptBytes -= bytes;
      filedata.delete(oldest);
    }
  }

  /** The guest path of a rootfs file, for reports. v86 names files by content
   *  and keeps no parent link on a file inode, so this walks the tree. */
  #pathOf(name) {
    const fs = this.#emulator.fs9p;
    const pending = [[0, '']];
    while (pending.length > 0) {
      const [dir, path] = pending.pop();
      for (const [entry, index] of fs.inodes[dir].direntries) {
        if (entry === '.' || entry === '..') continue;
        const inode = fs.inodes[index];
        const child = `${path}/${entry}`;
        if (inode.sha256sum === name) return child;
        if ((inode.mode & 0xF000) === 0x4000) pending.push([index, child]);
      }
    }
    return null;
  }

  #emit(event) {
    try {
      this.#onEvent(event);
    } catch (error) {
      // A listener's mistake must not unwind into v86's 9p or serial code.
      console.error(error);
    }
  }

}

/**
 * Replaces how v86 hands the main thread back between its slices of about a
 * millisecond. In a browser v86 posts the end of every slice to a blob worker
 * and waits for the echo, and that round trip queues behind whatever else the
 * page does: with 6 ms of page work a frame the guest kept 3 % of its speed at
 * 4× CPU throttling. A MessageChannel to the page itself brought the first
 * window 10 to 25 % sooner under that load, and changed nothing measurable on
 * an idle page (docs/vm-build.md, "frame-load").
 *
 * Like v86's worker it keeps one timer at most for a guest that is idle until
 * its next timer, and sets it from a message task rather than from the timer
 * before it, which keeps a chain of idle waits clear of the 4 ms clamp browsers
 * put on deeply nested timeouts.
 *
 * @param {object} inner The emulator's `v86`: src/main.js.
 * @returns {boolean} Whether it replaced v86's worker, the one yield it replaces.
 */
export function yieldThroughChannel(inner) {
  if (!inner?.worker || typeof MessageChannel !== 'function') return false;
  inner.unregister_yield();
  const channel = new MessageChannel();
  let timer = null;
  channel.port1.onmessage = ({ data: { t, tick } }) => {
    clearTimeout(timer);
    timer = null;
    if (t < 1) {
      inner.yield_callback(tick);
      return;
    }
    timer = setTimeout(() => {
      timer = null;
      inner.yield_callback(tick);
    }, t);
  };
  inner.yield = (t, tick) => channel.port2.postMessage({ t, tick });
  inner.register_yield = () => {};
  inner.unregister_yield = () => {
    clearTimeout(timer);
    channel.port1.close();
    channel.port2.close();
  };
  return true;
}

// Guest time stamp counter
//
// v86 keeps the guest TSC as microtick() * TSC_RATE - tsc_offset (read_tsc in
// src/rust/cpu/cpu.rs), microtick being performance.now(). Its set_tsc(new)
// sets tsc_offset = read_tsc() - new, but read_tsc() has already subtracted the
// current offset, so afterwards the TSC reads new + the old offset rather than
// new. restore_state goes through set_tsc with the saved TSC S. A restore that
// lands right leaves the offset at about (elapsed - S), so the next one lands
// the TSC near `elapsed`: far below S, behind the kernel's last cycle count, and
// the guest clock stands still until the TSC climbs back past S. That one leaves
// a small positive offset, so the restore after it is right again, which is why
// it failed on every second restore. The upstream fix is to add
// (current_value - new_value) to tsc_offset instead of replacing it.
//
// set_tsc is exact while the offset is zero, and setting the TSC to its own
// value makes the offset the time between two reads: nanoseconds, or within one
// performance.now() tick where the page is not cross-origin isolated and v86
// extrapolates between ticks.
//
// read_tsc also keeps counting while the CPU is stopped, so a guest resumed
// after a park would see the whole park pass at once: an after() or a sleep()
// that was running when the tab was hidden ends the moment it comes back. The
// host freezes the TSC instead, the way QEMU freezes kvmclock across stop and
// cont: a stop records it and a start writes it back, so the guest never sees
// the parked time. Its wall clock falls behind by that much, which is why the
// run layer sends HELLO after every resume.

function zeroTscOffset(cpu) {
  cpu.store_current_tsc();
  cpu.set_tsc(cpu.current_tsc[0], cpu.current_tsc[1]);
}

function readTsc(cpu) {
  cpu.store_current_tsc();
  return [cpu.current_tsc[0], cpu.current_tsc[1]];
}

function writeTsc(cpu, [low, high]) {
  zeroTscOffset(cpu);
  cpu.set_tsc(low, high);
}

async function defaultFetchFile(url, signal) {
  if (isLocalPath(url)) {
    const { readFile } = await import('node:fs/promises');
    return new Uint8Array(await readFile(url, { signal }));
  }
  const response = await fetch(url, { signal });
  if (!response.ok) {
    throw Object.assign(new Error(`HTTP ${response.status}`), { status: response.status });
  }
  return new Uint8Array(await response.arrayBuffer());
}

function isPermanentFetchError(error) {
  const status = error?.status;
  if (typeof status === 'number') return status >= 400 && status < 500 && status !== 408 && status !== 429;
  return ['ENOENT', 'ENOTDIR', 'EISDIR', 'EACCES'].includes(error?.code);
}
