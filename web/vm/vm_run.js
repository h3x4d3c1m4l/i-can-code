// What the app uses: openVm() loads an image bundle, keeps the machine parked
// between runs, runs programs on it and stops them. vm/protocol/README.md
// section 9 is its state machine, and docs/vm-build.md, "Host API", is the
// contract the Dart side binds to.

import { inflateState, loadBundle } from './vm_bundle.js';
import { createVmHost } from './vm_machine.js';
import {
  CreditedSender,
  decodeMessage,
  encodeMessage,
  FILE_NAME,
  FrameDecoder,
  inFilePath,
  MAX_FILES,
  MAX_FILES_BYTES,
  MAX_PAYLOAD_TO_HOST,
  OUTPUT_CAP,
} from './vm_protocol.js';
import { sleep } from './vm_util.js';

/** README 9.7. Active time, not wall-clock time: see Watchdog. */
const HELLO_DEADLINE_MS = 1000;
const STARTED_DEADLINE_MS = 2000;
const PING_EVERY_MS = 2000;
const PONG_DEADLINE_MS = 1000;

/** README 9.5: wall-clock time the host waits for a stopped run's EXIT before
 *  it parks anyway. A park needs nothing from the guest. */
const STOP_GRACE_MS = 500;

/** How long a run whose rootfs read failed goes on before it ends: what the
 *  program printed before the read waits up to 16 ms in the agent's output
 *  batch, and the student should see it. */
const FETCH_FAILURE_GRACE_MS = 50;

/** The kernel console's tail, kept for failure reports. */
const CONSOLE_KEEP_BYTES = 16 * 1024;

/** README 6.8's hint kinds. The host ignores any other. */
const HINT_KINDS = new Set(['tk_no_mainloop']);

/** The live Vm. A Flutter hot restart re-runs the Dart side but keeps this
 *  module, and with it a machine nothing can reach any more. */
let currentVm = null;

/** Vms a newer openVm() destroyed. Their page did not ask for that, so they
 *  tell it with a `failed` event. */
const replacedVms = new WeakSet();

/**
 * Opens the page's VM. Nothing is downloaded until load() or run().
 *
 * There is one per page, so this destroys the previous one, which reports
 * `failed` with the reason `replaced` to its own `onEvent`.
 *
 * @param {object} options
 * @param {string} options.baseUrl The directory that holds the image's
 *     manifest.json: in the browser a URL, absolute or relative to the
 *     document's base URL as fetch() resolves it; under Node a directory path.
 * @param {(event: object) => void} [options.onEvent] See the Vm class for the events.
 * @param {object} [options.screen] A VmScreen from vm_screen.js; none when headless.
 * @param {boolean} [options.trackVisibility] Follow document.visibilityState.
 *     Defaults to true wherever there is a document; headless callers use setVisible().
 * @param {(url: string, signal: AbortSignal) => Promise<Uint8Array>} [options.fetchFile]
 *     Replaces how rootfs files are fetched, as createVmHost's option does.
 * @param {(url: string, onBytes: (n: number) => void, signal: AbortSignal) => Promise<Uint8Array>} [options.readAsset]
 *     Replaces how the wasm and the state are read. Defaults to the Cache API in
 *     the browser and the file system under Node. `signal` aborts once the other
 *     file has failed.
 * @param {object} [options.download] vm_download.js's knobs, for tests and the
 *     bench: `pieceBytes`, `parallel`, `ranges`, `retryDelaysMs`, `stallMs`, `lingerMs`.
 * @param {{manifest: object, V86: Function, wasm: BufferSource, state: ArrayBuffer, rootfsUrl: string,
 *     release?: () => void, evictState?: () => Promise<void>}} [options.bundle]
 *     A bundle already in memory, which skips the download. For tools and tests.
 * @param {() => number} [options.now] The watchdog's clock, in ms.
 * @returns {Vm}
 */
export function openVm(options) {
  if (currentVm) {
    replacedVms.add(currentVm);
    currentVm.destroy().catch(console.error);
  }
  currentVm = new Vm(options);
  return currentVm;
}

/**
 * The page's VM: README section 9.
 *
 * Events, passed to `onEvent` as plain objects:
 *
 * - `{type: 'progress', phase, loaded, total, cached, rate, remainingMs, stalled,
 *   keeps, slowConnection}` while the machine loads. `phase` is `download` while
 *   the bundle is read, then `unpack` while the state decompresses and `start`
 *   while the machine starts. The other fields are vm_download.js's
 *   BundleDownload's. Never after the `failed` that ends that load.
 * - `{type: 'ready', python, tk, imageId}` once the machine is parked and
 *   waiting. `python` is what the guest's interpreter calls itself.
 * - `{type: 'failed', reason, message}`: the VM cannot run programs any more.
 *   `reason` is `network`, `incompatible`, `fetch`, `unresponsive`, `broken`,
 *   or `replaced` when a newer openVm() destroyed this one.
 * - `{type: 'started', run, warm, pid}`.
 * - `{type: 'output', run, stream, text}`, `stream` being `stdout` or `stderr`.
 * - `{type: 'window', run, windows}`: the run's top-level windows (README 6.7).
 * - `{type: 'hint', run, kind}`: `tk_no_mainloop` (README 6.8), once per run at most.
 * - `{type: 'ended', run, reason, code, signal, truncated, ms, message}`, exactly
 *   once for every run, however it ended (README 9.3).
 * - `{type: 'parked'}` whenever the machine has been restored and stopped.
 * - `{type: 'log', level, message, run}`: the agent's LOG, for developers.
 * - `{type: 'stop-answered', run, ms}`: how long after STOP the stopped run's
 *   EXIT came, or null when the host parked without it. For diagnostics.
 * - `{type: 'rootfs-fetched', path, bytes, ms}`, `{type: 'rootfs-cached', path,
 *   bytes, ms}` and `{type: 'fetch-failed', ...}` for diagnostics.
 */
class Vm {

  #options;
  #onEvent;
  #state = 'unloaded';
  #loading = null;
  /** The load in flight, which is the only one whose progress is reported. */
  #attempt = null;
  /** Leaves the download when the Vm is destroyed while it loads. */
  #loadAbort = null;
  /** The download's last report, which the later phases repeat. */
  #lastProgress = null;
  #bundle = null;
  #inflated = false;
  #machine = null;
  #failure = null;
  #interpreter = null;

  #nextId = 1;
  #decoder = new FrameDecoder({ maxPayload: MAX_PAYLOAD_TO_HOST });
  #sender = null;
  #incoming = [];
  #flushQueued = false;
  #console = [];

  #run = null;
  #queued = null;
  /** HELLOs awaiting READY, by id, with what each is for. */
  #hellos = new Map();
  #pingId = null;
  #strikes = 0;
  #stopTimer = null;
  #parking = null;
  #parkedWaiters = [];
  #stopTrackingVisibility = null;
  #visible = true;
  #stats = { frames: 0, dropped: {}, invalid: {}, stale: 0, parks: 0, hintsDropped: 0, inflate: null };

  constructor(options) {
    if (!options?.baseUrl && !options?.bundle) throw new TypeError('baseUrl is required');
    this.#options = options;
    this.#onEvent = options.onEvent ?? (() => {});
    const trackVisibility = options.trackVisibility ?? typeof document !== 'undefined';
    if (trackVisibility) {
      const onChange = () => this.setVisible(document.visibilityState === 'visible');
      document.addEventListener('visibilitychange', onChange);
      this.#stopTrackingVisibility = () => document.removeEventListener('visibilitychange', onChange);
      this.#visible = document.visibilityState === 'visible';
    }
  }

  /** unloaded, loading, parked, starting, running, stopping, parking, failed or destroyed. */
  get state() {
    return this.#state;
  }

  /** `{python, tk}` as the guest reported them, once ready. */
  get interpreter() {
    return this.#interpreter;
  }

  get manifest() {
    return this.#bundle?.manifest ?? null;
  }

  /** The raw V86, for the build tools: its framebuffer and its input bus. */
  get emulator() {
    return this.#machine?.emulator ?? null;
  }

  get stats() {
    return { ...this.#stats, ...(this.#machine?.stats ?? {}), memory: this.#machine?.memoryUsage() ?? null };
  }

  /** The kernel console's last 16 KiB, as text. */
  consoleText() {
    return new TextDecoder().decode(Uint8Array.from(this.#console));
  }

  /**
   * Downloads the bundle, builds the machine and parks it. It never throws: it
   * resolves with the `ready` or the `failed` event. Calls share one load, and a
   * failed one is dropped so that the next call tries again.
   */
  load() {
    if (this.#state === 'destroyed') return Promise.resolve(this.#destroyedEvent());
    if (!this.#loading) {
      this.#loading = this.#load().catch(error => this.#fail('broken', `Loading failed: ${error.message}`));
      this.#loading.then(event => {
        if (event.type === 'failed') this.#loading = null;
      });
    }
    return this.#loading;
  }

  /**
   * Runs a program. A run in progress ends as `stopped` first; it supersedes, it
   * never waits. Loads the VM first when it has not been.
   *
   * @param {object} program
   * @param {Record<string, Uint8Array | string>} program.files Flat names matching
   *     vm_protocol.js's FILE_NAME, at most 64 and 8 MiB together.
   * @param {string} program.entry The file run as `__main__`. MUST be one of `files`.
   * @param {string[]} [program.argv]
   * @returns {{id: number, ended: Promise<object>}} `ended` resolves with the
   *     run's `ended` event. It never rejects.
   * @throws {TypeError} When the program breaks the rules above.
   */
  run({ files, entry, argv = [] }) {
    const checked = checkProgram(files, entry, argv);
    const run = {
      id: this.#nextId++,
      ...checked,
      phase: 'queued',
      ended: false,
      hints: new Set(),
      decoders: { stdout: new TextDecoder(), stderr: new TextDecoder() },
    };
    run.promise = new Promise(resolve => { run.resolve = resolve; });

    // A load that failed may work next time; a machine that failed after it was ready does not.
    if (this.#state === 'destroyed' || (this.#state === 'failed' && this.#loading)) {
      this.#end(run, { reason: 'broken', message: this.#failure?.message ?? 'The VM is not available.' });
      return { id: run.id, ended: run.promise };
    }
    if (this.#queued) this.#end(this.#queued, { reason: 'stopped' });
    this.#queued = run;
    if (this.#run) this.#stopRun();
    else if (this.#state === 'parked') this.#startQueued();
    else if (this.#state === 'unloaded' || this.#state === 'failed') this.load();
    return { id: run.id, ended: run.promise };
  }

  /**
   * Ends the run for the caller at once, and resolves once the machine is
   * parked again: after the run's EXIT, or 500 ms after STOP, plus one restore.
   * It depends on nothing the guest does.
   */
  stop() {
    if (this.#queued) {
      this.#end(this.#queued, { reason: 'stopped' });
      this.#queued = null;
    }
    if (this.#run) this.#stopRun();
    return this.#whenSettled();
  }

  /** What the close button on window `xid`'s frame does (README 6.10). */
  closeWindow(xid) {
    const run = this.#run;
    if (this.#state !== 'running' || !run || run.ended) return;
    this.#send('CLOSE', { xid }, run.id);
  }

  /**
   * A hidden page stops the guest's CPU; a visible one lets it go on. The run is
   * untouched, and the watchdog does not count while hidden (F2).
   */
  setVisible(visible) {
    if (visible === this.#visible) return;
    this.#visible = visible;
    const machine = this.#machine;
    if (!machine) return;
    machine.setVisible(visible).then(() => {
      // The guest's clock stood still while its CPU did; HELLO puts it right.
      if (visible && this.#visible && machine.running && ['starting', 'running', 'stopping'].includes(this.#state)) {
        this.#hello('clock');
      }
    }).catch(console.error);
  }

  /** Ends every run as `stopped` and frees the machine. */
  async destroy() {
    if (this.#state === 'destroyed') return;
    const machine = this.#machine;
    this.#setState('destroyed');
    if (currentVm === this) currentVm = null;
    this.#loadAbort?.abort(new Error('The VM was destroyed.'));
    this.#stopTrackingVisibility?.();
    clearTimeout(this.#stopTimer);
    if (this.#queued) this.#end(this.#queued, { reason: 'stopped' });
    if (this.#run) this.#end(this.#run, { reason: 'stopped' });
    this.#queued = null;
    this.#run = null;
    this.#abandonHellos();
    this.#settle();
    this.#machine = null;
    this.#bundle?.release?.();
    this.#options.screen?.detach?.();
    if (replacedVms.has(this)) this.#emit(this.#destroyedEvent());
    await machine?.destroy();
  }

  // Loading

  async #load() {
    this.#setState('loading');
    this.#failure = null;
    // A byte count of a load that has failed, or whose Vm is destroyed, would
    // take the page back to its loading panel, or mix into a later load's.
    const attempt = Symbol('load');
    this.#attempt = attempt;
    const report = progress => {
      if (this.#attempt === attempt && this.#state === 'loading') this.#emit({ type: 'progress', ...progress });
    };
    const loadAbort = new AbortController();
    this.#loadAbort = loadAbort;
    try {
      this.#bundle ??= this.#options.bundle
        ? { ...this.#options.bundle }
        : await loadBundle({ ...this.#options, signal: loadAbort.signal }, progress => {
          this.#lastProgress = progress;
          report({ phase: 'download', ...progress });
        });
    } catch (error) {
      if (this.#state === 'destroyed') return this.#destroyedEvent();
      return this.#fail(error.reason ?? 'network', error.message);
    } finally {
      if (this.#loadAbort === loadAbort) this.#loadAbort = null;
    }
    if (this.#state === 'destroyed') {
      this.#bundle.release?.();
      return this.#destroyedEvent();
    }
    const phase = name => report(this.#phaseProgress(name));
    // The state decompresses on another thread while v86 compiles and starts on this one.
    const unpacking = !this.#inflated;
    phase(unpacking ? 'unpack' : 'start');
    const inflated = this.#inflate().then(() => {
      if (unpacking) phase('start');
    });
    const notBuilt = await this.#buildMachine().then(() => null, error => error);
    await inflated;
    if (this.#state === 'destroyed') return this.#destroyedEvent();
    if (notBuilt) return this.#fail('broken', `The emulator did not start: ${notBuilt.message}`);

    for (let attempt = 0; attempt < 2; attempt++) {
      if (this.#state !== 'loading') return this.#failedEvent(this.#failure?.reason ?? 'broken', this.#failure?.message ?? 'Stopped.');
      try {
        await this.#machine.restoreSnapshot(this.#bundle.state);
      } catch (error) {
        this.#dropBundle();
        return this.#fail('broken', `The snapshot did not restore: ${error.message}`);
      }
      this.#resetLine();
      await this.#machine.resume();
      const ready = await this.#greet();
      if (this.#state !== 'loading') {
        return this.#failure ? this.#failedEvent(this.#failure.reason, this.#failure.message) : this.#failedEvent('broken', 'Stopped.');
      }
      if (ready === null) continue;
      if (!ready.warm) return this.#fail('broken', 'The image has no warm interpreter waiting.');
      this.#interpreter = { python: ready.python, tk: ready.tk };
      await this.#machine.pause();
      this.#setState('parked');
      const event = {
        type: 'ready',
        python: ready.python,
        tk: ready.tk,
        imageId: this.#bundle.manifest.imageId,
      };
      this.#emit(event);
      this.#startQueued();
      return event;
    }
    this.#dropBundle();
    return this.#fail('unresponsive', 'The agent did not answer HELLO after two restores.');
  }

  /** What `progress` says once the download is over: all of it held, and `name` under way. */
  #phaseProgress(name) {
    const manifest = this.#bundle?.manifest;
    const total = this.#lastProgress?.total ?? ((manifest?.v86?.wasmBytes ?? 0) + (manifest?.state?.bytes ?? 0));
    return {
      loaded: total,
      total,
      cached: this.#lastProgress?.cached ?? total,
      rate: null,
      remainingMs: null,
      stalled: false,
      keeps: this.#lastProgress?.keeps ?? true,
      slowConnection: false,
      phase: name,
    };
  }

  /**
   * Forgets the bundle whose state would not restore or answer, its cached copy
   * included, so that the next load reads it again rather than failing on the
   * same bytes. The sha256 check makes a bad copy unlikely; this covers a
   * manifest that names none.
   */
  #dropBundle() {
    const bundle = this.#bundle;
    if (!bundle) return;
    this.#bundle = null;
    this.#inflated = false;
    bundle.evictState?.()?.catch(() => {});
    bundle.release?.();
  }

  /** Swaps the bundle's zstd state for a raw one, once per page: every park
   *  after that restores without decompressing. It never rejects. */
  async #inflate() {
    if (this.#inflated) return;
    this.#inflated = true;
    const bundle = this.#bundle;
    try {
      const { state, where, ms } = await inflateState(bundle.state, bundle.wasm, bundle.manifest.state?.rawBytes);
      bundle.state = state;
      if (where) this.#stats.inflate = { where, ms };
    } catch (error) {
      this.#log('warn', `The state stays compressed, and every park decompresses it: ${error.message}`);
    }
  }

  /** Sends the load's HELLO and resolves with READY's body, or null when the
   *  deadline passed. */
  #greet() {
    return new Promise(resolve => {
      const id = this.#hello('load', resolve);
      this.#arm(HELLO_DEADLINE_MS, () => {
        this.#hellos.delete(id);
        this.#strikes++;
        resolve(null);
      });
    });
  }

  async #buildMachine() {
    const { manifest, V86, wasm } = this.#bundle;
    const screen = this.#options.screen ?? null;
    const machine = await createVmHost({
      V86,
      wasm,
      memoryMiB: manifest.memoryMiB,
      vgaMiB: manifest.vgaMiB,
      uart1: manifest.uart1,
      rootfsUrl: this.#bundle.rootfsUrl,
      screen: screen?.container ?? null,
      fetchFile: this.#options.fetchFile,
      fileCache: this.#bundle.rootfsCache ?? null,
      trackVisibility: false,
      now: this.#options.now,
      onEvent: event => this.#onMachineEvent(event),
    });
    if (this.#state === 'destroyed') {
      // destroy() freed the machine it found, and this one was still loading then.
      await machine.destroy();
      throw new Error('The VM was destroyed.');
    }
    this.#machine = machine;
    if (!this.#visible) await this.#machine.setVisible(false);
    const emulator = this.#machine.emulator;
    this.#sender = new CreditedSender(bytes => emulator.serial_send_bytes(1, bytes));
    emulator.add_listener('serial1-output-byte', byte => this.#onSerial(emulator, byte));
    emulator.add_listener('serial0-output-byte', byte => this.#onConsole(byte));
    screen?.attach?.(emulator);
  }

  // Runs

  #startQueued() {
    const run = this.#queued;
    if (!run || this.#state !== 'parked') return;
    this.#queued = null;
    this.#begin(run);
  }

  /** Resumes the parked machine and starts `run` on it: HELLO, then its files, then RUN. */
  async #begin(run) {
    this.#run = run;
    run.phase = 'hello';
    this.#setState('starting');
    try {
      await this.#machine.resume();
    } catch (error) {
      // Only a machine destroyed under the run gets here.
      if (!run.ended) this.#end(run, { reason: 'stopped', message: error.message });
      return;
    }
    if (this.#run !== run || run.ended) return;
    run.helloId = this.#hello('run');
    this.#arm(HELLO_DEADLINE_MS, () => this.#expired('READY to HELLO'));
  }

  async #sendFiles(run) {
    run.phase = 'files';
    this.#machine.watchdog.stop();
    const emulator = this.#machine.emulator;
    for (const [name, bytes] of run.files) {
      await emulator.create_file(inFilePath(run.id, name), bytes);
      if (this.#run !== run || run.ended) return;
    }
    run.phase = 'run';
    this.#send('RUN', {
      entry: run.entry,
      files: [...run.files.keys()],
      argv: run.argv,
      stdin: false,
      output_cap: OUTPUT_CAP,
    }, run.id);
    run.sent = performance.now();
    this.#arm(STARTED_DEADLINE_MS, () => this.#expired('STARTED to RUN'));
  }

  /** Ends the run in progress for the caller now (README 9.5), and parks. */
  #stopRun() {
    const run = this.#run;
    if (!run || this.#state === 'stopping' || this.#state === 'parking') return;
    if (!run.ended) this.#end(run, { reason: 'stopped' });
    if (run.phase === 'run' || run.phase === 'running') {
      this.#send('STOP', {}, run.id);
      run.stopSent = performance.now();
      this.#setState('stopping');
      this.#machine.watchdog.stop();
      this.#stopTimer = setTimeout(() => {
        this.#emit({ type: 'stop-answered', run: run.id, ms: null });
        this.#park();
      }, STOP_GRACE_MS);
    } else {
      this.#park();
    }
  }

  /** A deadline of README 9.7 passed. */
  #expired(what) {
    this.#strikes++;
    const run = this.#run;
    if (this.#strikes >= 2) {
      if (run && !run.ended) this.#end(run, { reason: 'unresponsive', message: `No ${what}.` });
      this.#fail('unresponsive', `No ${what}, twice in a row.`);
      return;
    }
    if (!run) return;
    if (run.phase === 'running') {
      this.#end(run, { reason: 'unresponsive', message: `No ${what}.` });
      this.#park();
      return;
    }
    // Starting: park, and give the same run a second go on the restored machine.
    this.#log('warn', `No ${what}; trying run ${run.id} again.`, run.id);
    this.#queued ??= run;
    this.#park();
  }

  #end(run, fields) {
    if (run.ended) return;
    run.ended = true;
    for (const stream of ['stdout', 'stderr']) {
      const text = run.decoders[stream].decode();
      if (text) this.#emit({ type: 'output', run: run.id, stream, text });
    }
    const event = {
      type: 'ended',
      run: run.id,
      reason: fields.reason,
      code: fields.code ?? null,
      signal: fields.signal ?? null,
      truncated: fields.truncated ?? false,
      ms: fields.ms ?? null,
      message: fields.message ?? null,
    };
    this.#emit(event);
    run.resolve(event);
  }

  /** README 9.4: restore, then stop the CPU. Every run ends in one. */
  #park() {
    if (this.#parking) return this.#parking;
    if (!this.#machine || this.#state === 'destroyed' || this.#state === 'failed') return Promise.resolve();
    clearTimeout(this.#stopTimer);
    this.#stopTimer = null;
    this.#setState('parking');
    this.#machine.watchdog.stop();
    this.#pingId = null;
    this.#parking = (async () => {
      // The caller has heard the run end; its Run button should be on screen
      // before the restore takes the thread.
      await afterPaint();
      if (this.#state === 'destroyed') return;
      try {
        await this.#machine.restoreSnapshot();
      } catch (error) {
        this.#log('error', `The restore failed, building a new emulator: ${error.message}`);
        try {
          await this.#machine.destroy();
          await this.#buildMachine();
          await this.#machine.restoreSnapshot(this.#bundle.state);
        } catch (again) {
          this.#fail('broken', `The machine could not be restored: ${again.message}`);
          return;
        }
      }
      if (this.#state === 'destroyed') return;
      this.#resetLine();
      this.#stats.parks++;
      const run = this.#run;
      this.#run = null;
      // A run whose start timed out once gets its second go (README 9.7).
      if (run && !run.ended && this.#queued === run) run.phase = 'queued';
      this.#setState('parked');
      this.#emit({ type: 'parked' });
      this.#settle();
      this.#startQueued();
    })().finally(() => { this.#parking = null; });
    return this.#parking;
  }

  #fail(reason, message) {
    if (this.#state === 'destroyed') return this.#failedEvent(reason, message);
    this.#failure = { reason, message };
    this.#abandonHellos();
    this.#machine?.watchdog.stop();
    clearTimeout(this.#stopTimer);
    for (const run of [this.#run, this.#queued]) {
      if (run && !run.ended) this.#end(run, { reason: 'broken', message });
    }
    this.#run = null;
    this.#queued = null;
    this.#setState('failed');
    this.#machine?.pause().catch(() => {});
    const event = this.#failedEvent(reason, message);
    this.#emit(event);
    this.#settle();
    return event;
  }

  #failedEvent(reason, message) {
    return { type: 'failed', reason, message };
  }

  #destroyedEvent() {
    return replacedVms.has(this)
      ? this.#failedEvent('replaced', 'A newer openVm() on this page took over the machine.')
      : this.#failedEvent('broken', 'The VM was destroyed.');
  }

  #setState(state) {
    if (this.#state === 'destroyed') return;
    this.#state = state;
  }

  /** Resolves once nothing is in flight: parked, failed or destroyed. */
  #whenSettled() {
    if (!['starting', 'running', 'stopping', 'parking'].includes(this.#state) && !this.#run) {
      return Promise.resolve();
    }
    return new Promise(resolve => this.#parkedWaiters.push(resolve));
  }

  #settle() {
    for (const resolve of this.#parkedWaiters.splice(0)) resolve();
  }

  /** Arms the one deadline of the moment on active time. */
  #arm(ms, onExpire) {
    this.#machine.watchdog.start(ms, onExpire);
  }

  // The line

  #hello(purpose, resolve) {
    const id = this.#nextId++;
    this.#hellos.set(id, { purpose, resolve });
    this.#send('HELLO', { now_ms: Date.now(), tz: timeZone(), entropy: randomHex(64) }, id);
    return id;
  }

  #send(type, body, id) {
    this.#sender.send(encodeMessage({ type, id, body }));
  }

  #resetLine() {
    this.#incoming.length = 0;
    this.#decoder.reset();
    this.#sender.reset();
    this.#abandonHellos();
    this.#pingId = null;
  }

  /** A load waiting on READY learns it will not come. */
  #abandonHellos() {
    for (const hello of this.#hellos.values()) hello.resolve?.(null);
    this.#hellos.clear();
  }

  #onSerial(emulator, byte) {
    // A replaced emulator can still deliver the tail of what it was sending.
    if (emulator !== this.#machine?.emulator) return;
    this.#incoming.push(byte);
    // One decode per v86 slice rather than per byte.
    if (!this.#flushQueued) {
      this.#flushQueued = true;
      queueMicrotask(() => this.#flush());
    }
  }

  #flush() {
    this.#flushQueued = false;
    if (this.#incoming.length === 0) return;
    const bytes = Uint8Array.from(this.#incoming);
    this.#incoming.length = 0;
    for (const event of this.#decoder.push(bytes)) {
      if (event.error) {
        this.#stats.dropped[event.error] = (this.#stats.dropped[event.error] ?? 0) + 1;
        // README section 10: a good CRC with another version is an incompatible
        // agent, and waiting for a deadline would only hide it.
        if (event.error === 'version') this.#fail('incompatible', 'The agent speaks another protocol version.');
        continue;
      }
      this.#stats.frames++;
      this.#onFrame(event.frame);
      if (this.#state === 'failed' || this.#state === 'destroyed') return;
    }
  }

  #onFrame(frame) {
    const decoded = decodeMessage(frame, { from: 'agent' });
    if (decoded.error) {
      this.#stats.invalid[decoded.error] = (this.#stats.invalid[decoded.error] ?? 0) + 1;
      const run = this.#run;
      if (run && frame.id === run.id && !run.ended && ['bad_json', 'not_object', 'field'].includes(decoded.error)) {
        this.#end(run, { reason: 'broken', message: `The agent sent an invalid message (${decoded.error} ${decoded.field ?? ''}).` });
        this.#park();
      }
      return;
    }
    const message = decoded.message;
    const body = message.body;
    switch (message.type) {
      case 'CREDIT':
        this.#sender.grant(body.bytes);
        return;
      case 'LOG':
        this.#log(body.level, body.message, message.id || null);
        return;
      case 'PONG':
        if (message.id === this.#pingId) {
          this.#pingId = null;
          this.#strikes = 0;
          this.#arm(PING_EVERY_MS, () => this.#ping());
        }
        return;
      case 'READY':
        this.#onReady(message.id, body);
        return;
      case 'ERROR':
        this.#onError(message.id, body);
        return;
    }

    const run = this.#run;
    if (!run || message.id !== run.id || run.ended) {
      // Output or an EXIT of a run that has ended for the caller.
      if (run && message.id === run.id && message.type === 'EXIT' && this.#state === 'stopping') {
        this.#emit({ type: 'stop-answered', run: run.id, ms: performance.now() - run.stopSent });
        this.#park();
      } else {
        this.#stats.stale++;
      }
      return;
    }
    switch (message.type) {
      case 'STARTED':
        if (run.phase !== 'run') return;
        run.phase = 'running';
        this.#strikes = 0;
        this.#setState('running');
        this.#emit({ type: 'started', run: run.id, warm: body.warm, pid: body.pid });
        this.#arm(PING_EVERY_MS, () => this.#ping());
        return;
      case 'STDOUT':
      case 'STDERR': {
        const stream = message.type === 'STDOUT' ? 'stdout' : 'stderr';
        const text = run.decoders[stream].decode(message.data, { stream: true });
        if (text) this.#emit({ type: 'output', run: run.id, stream, text });
        return;
      }
      case 'WINDOW':
        this.#emit({ type: 'window', run: run.id, windows: body.windows });
        return;
      case 'HINT':
        // The program's own process can write what the prelude writes, and the
        // output cap bounds no hint, so the agent's filter is not the only one.
        if (!HINT_KINDS.has(body.kind) || run.hints.has(body.kind)) {
          this.#stats.hintsDropped++;
          return;
        }
        run.hints.add(body.kind);
        this.#emit({ type: 'hint', run: run.id, kind: body.kind });
        return;
      case 'EXIT':
        this.#end(run, {
          reason: body.reason,
          code: body.code,
          signal: body.signal,
          truncated: body.truncated,
          ms: body.ms,
        });
        this.#park();
        return;
    }
  }

  #onReady(id, body) {
    if (id === 0) {
      // Unasked: init respawned an agent that died. Whatever it was running is gone.
      const run = this.#run;
      if (run && !run.ended && ['starting', 'running'].includes(this.#state)) {
        this.#end(run, { reason: 'broken', message: 'The agent restarted.' });
        this.#park();
      }
      return;
    }
    const hello = this.#hellos.get(id);
    if (!hello) return;
    this.#hellos.delete(id);
    this.#strikes = 0;
    if (hello.purpose === 'load') {
      this.#machine.watchdog.stop();
      hello.resolve(body);
    } else if (hello.purpose === 'run') {
      const run = this.#run;
      if (run && run.helloId === id && run.phase === 'hello' && !run.ended) {
        this.#sendFiles(run).catch(error => {
          if (run.ended || this.#run !== run) return;
          this.#end(run, { reason: 'broken', message: `The program's files could not be written: ${error.message}` });
          this.#park();
        });
      }
    }
  }

  #onError(id, body) {
    const run = this.#run;
    this.#log('error', `ERROR ${body.code}: ${body.message}`, id || null);
    if (run && id === run.id && !run.ended) {
      this.#end(run, { reason: 'broken', message: `${body.code}: ${body.message}` });
      this.#park();
    }
  }

  #ping() {
    if (this.#state !== 'running') return;
    this.#pingId = this.#nextId++;
    this.#send('PING', {}, this.#pingId);
    this.#arm(PONG_DEADLINE_MS, () => this.#expired('PONG to PING'));
  }

  #onMachineEvent(event) {
    if (event.type === 'fetch-failed') {
      this.#emit(event);
      const message = `${event.path ?? event.url} could not be loaded: ${event.message}`;
      if (this.#state === 'loading') {
        this.#fail('fetch', message);
      } else if (this.#run && !this.#run.ended && ['starting', 'running'].includes(this.#state)) {
        const run = this.#run;
        setTimeout(() => {
          if (this.#run !== run || run.ended) return;
          this.#end(run, { reason: 'fetch', message });
          this.#park();
        }, FETCH_FAILURE_GRACE_MS);
      }
      return;
    }
    this.#emit(event);
  }

  #onConsole(byte) {
    this.#console.push(byte);
    if (this.#console.length > CONSOLE_KEEP_BYTES * 2) {
      this.#console.splice(0, this.#console.length - CONSOLE_KEEP_BYTES);
    }
  }

  #log(level, message, run = null) {
    this.#emit({ type: 'log', level, message, run });
  }

  #emit(event) {
    try {
      this.#onEvent(event);
    } catch (error) {
      console.error(error);
    }
  }

}

/** Validates a program and returns its files as a Map of bytes. */
function checkProgram(files, entry, argv) {
  const entries = files instanceof Map ? [...files] : Object.entries(files ?? {});
  if (entries.length < 1 || entries.length > MAX_FILES) {
    throw new TypeError(`A program has 1 to ${MAX_FILES} files, not ${entries.length}.`);
  }
  const encoder = new TextEncoder();
  const checked = new Map();
  let total = 0;
  for (const [name, content] of entries) {
    if (!FILE_NAME.test(name)) throw new TypeError(`${JSON.stringify(name)} is not a file name the VM takes.`);
    const bytes = typeof content === 'string' ? encoder.encode(content) : content;
    if (!(bytes instanceof Uint8Array)) throw new TypeError(`${name} must be a string or a Uint8Array.`);
    total += bytes.byteLength;
    checked.set(name, bytes);
  }
  if (total > MAX_FILES_BYTES) throw new TypeError(`The files add up to ${total} bytes, over ${MAX_FILES_BYTES}.`);
  if (!checked.has(entry)) throw new TypeError(`The entry ${JSON.stringify(entry)} is not one of the files.`);
  if (!Array.isArray(argv) || argv.some(arg => typeof arg !== 'string' || arg.includes('\0'))) {
    throw new TypeError('argv must be strings without NUL.');
  }
  // RUN has to fit in one frame, which is what bounds argv and the names.
  const body = { entry, files: [...checked.keys()], argv, stdin: false, output_cap: OUTPUT_CAP };
  try {
    encodeMessage({ type: 'RUN', id: 1, body });
  } catch (error) {
    throw new TypeError(`The program does not fit in one RUN: ${error.message}`);
  }
  return { files: checked, entry, argv: [...argv] };
}

/** HELLO's `tz`: the zone the page is in, or UTC for a name the protocol refuses. */
function timeZone() {
  try {
    const zone = Intl.DateTimeFormat().resolvedOptions().timeZone;
    if (typeof zone === 'string' && zone.length <= 64 && /^[A-Za-z0-9_+-]+(?:\/[A-Za-z0-9_+-]+)*$/.test(zone)) return zone;
  } catch {
    // Fall through.
  }
  return 'UTC';
}

function randomHex(bytes) {
  const values = crypto.getRandomValues(new Uint8Array(bytes));
  return Array.from(values, value => value.toString(16).padStart(2, '0')).join('');
}

/** After the next frame has painted in a browser, or 100 ms, since a tab hidden
 *  meanwhile paints nothing; after pending I/O under Node. */
function afterPaint() {
  if (typeof requestAnimationFrame !== 'function') return new Promise(resolve => setTimeout(resolve, 0));
  return Promise.race([
    new Promise(resolve => requestAnimationFrame(() => setTimeout(resolve, 0))),
    sleep(100),
  ]);
}
