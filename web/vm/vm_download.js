// Downloading an image's files into the Cache API: v86.wasm and libv86.mjs as
// they are, and the state in HTTP Range pieces kept as they arrive, so that a
// download that stops resumes where it stopped, in the same load or the next.
// One download per image and page, whoever asked for it, with a smoothed byte
// rate for whoever shows it. Every retry is bounded and the run has a deadline,
// so a download that cannot finish ends in a failure the page can offer a Retry
// for rather than going round for ever.

import { deletePieces, forgetOtherImages, holdImage, listPieces, pieceKey } from './vm_cache.js';

const MiB = 1024 * 1024;

/** The state's pieces: under a second each at 20 Mbit/s, so a connection that
 *  drops loses little, and few enough that a request's own latency hardly
 *  counts. docs/vm-build.md, "download", has the measurements. */
export const PIECE_BYTES = 2 * MiB;

/** Pieces in flight at once. One answer's latency hides behind the others. */
export const PARALLEL = 3;

/** A piece cut short keeps what arrived for this load; past this much it is
 *  also kept for the next one. */
const MIN_KEPT_BYTES = 64 * 1024;

/** What one attempt at a piece must deliver before it counts as progress and
 *  the retries start over. A server or proxy that answers a sliver of every
 *  Range makes headway on each try, so without a bar to clear it would be
 *  resumed for ever, one request per sliver. The same bar as a kept piece: less
 *  than this is not even worth keeping. */
const MIN_PROGRESS_BYTES = MIN_KEPT_BYTES;

/** A request that receives nothing for this long is ended and tried again. */
const STALL_MS = 15_000;

/** Waits before each retry of a request that failed without progress. */
const RETRY_DELAYS_MS = [1000, 2000, 4000, 8000];

/** A retry waits for a browser that says it is offline to come back, this long at most. */
const OFFLINE_WAIT_MS = 30_000;

/** No byte for this long while a request is out is reported as `stalled`. */
const STALLED_AFTER_MS = 3000;

/** A download nobody waits for any more goes on this long, so that a caller
 *  that replaces another, a page opened again, picks it up where it is. */
const LINGER_MS = 5000;

/** The whole run's last word. Every piece is bounded on its own, but a server
 *  can keep a download alive for ever by making just enough headway on every
 *  try; past this the page is told, and offers its Retry. 17 MB in 20 minutes
 *  is 15 kB/s, under which nothing else on the page works either. */
const DEADLINE_MS = 20 * 60_000;

/** How often the rate is folded in and a stall noticed while bytes do not come. */
const TICK_MS = 250;

/** Room asked for beside what is downloaded: libv86.mjs, the manifest, and slack. */
const ROOM_MARGIN_BYTES = 4 * MiB;

/** A whole-file answer this far past the manifest's size is not read further. */
const OVERFLOW_LIMIT_BYTES = 4 * MiB;

/**
 * A byte rate smoothed over a few seconds, and whether there is enough of it
 * to go on. Until `tauMs` has passed it is the plain average since the first
 * byte; after that an exponential moving average with that time constant, so a
 * stall pulls it down within seconds without one slow second swinging it.
 */
export class RateMeter {

  #now;
  #tauMs;
  #minMs;
  #minBytes;
  #first = null;
  #lastSample = null;
  #pending = 0;
  #measured = 0;
  #smoothed = null;
  #lastByte = null;

  constructor({ now = () => performance.now(), tauMs = 3000, minMs = 2000, minBytes = 256 * 1024 } = {}) {
    this.#now = now;
    this.#tauMs = tauMs;
    this.#minMs = minMs;
    this.#minBytes = minBytes;
  }

  /** Bytes that just arrived. The first arrival starts the clock and is not
   *  counted: it was on its way for an unknown time before. */
  add(bytes) {
    if (!(bytes > 0)) return;
    const at = this.#now();
    this.#lastByte = at;
    if (this.#first === null) {
      this.#first = at;
      this.#lastSample = at;
      return;
    }
    this.#pending += bytes;
    this.#measured += bytes;
  }

  /** Folds what arrived since the last sample into the rate. */
  sample() {
    if (this.#first === null) return;
    const at = this.#now();
    const dt = at - this.#lastSample;
    if (dt <= 0) return;
    const elapsed = at - this.#first;
    if (elapsed <= this.#tauMs || this.#smoothed === null) {
      this.#smoothed = this.#measured * 1000 / elapsed;
    } else {
      const instant = this.#pending * 1000 / dt;
      this.#smoothed += (1 - Math.exp(-dt / this.#tauMs)) * (instant - this.#smoothed);
    }
    this.#pending = 0;
    this.#lastSample = at;
  }

  /** Bytes per second, or null until `minMs` and `minBytes` have been seen. */
  get bytesPerSecond() {
    if (this.#first === null || this.#smoothed === null) return null;
    const enough = this.#now() - this.#first >= this.#minMs && this.#measured >= this.#minBytes;
    return enough && this.#smoothed > 0 ? this.#smoothed : null;
  }

  /** When the last byte arrived, or null before the first. */
  get lastByteAt() {
    return this.#lastByte;
  }

}

// One image's download, shared

/** Downloads in flight, by bundle URL. Module level, so every caller on the page shares one. */
const inFlight = new Map();

/**
 * Joins the download of an image's files, starting it when none is in flight.
 *
 * @param {object} job What to download; only the first caller's is used.
 * @param {string} job.base The directory that holds the manifest, absolute.
 * @param {string} job.bundle `${base}${manifest.imageId}/`.
 * @param {object} job.manifest
 * @param {Cache | null} job.cache
 * @param {{onProgress?: (progress: object) => void, signal?: AbortSignal}} caller
 * @returns {Promise<{wasm: Uint8Array, state: Uint8Array, keeps: boolean, cached: number, fetched: number}>}
 *     Rejects with `reason` `network` when a file cannot be had, and `aborted`
 *     when `signal` aborts. `onProgress` is not called after it settles.
 */
export function joinDownload(job, { onProgress, signal } = {}) {
  let download = inFlight.get(job.bundle);
  // One that nobody waited for is on its way out, and would only reject.
  if (!download || download.stopping) {
    download = new BundleDownload(job);
    inFlight.set(job.bundle, download);
    const forget = () => {
      if (inFlight.get(job.bundle) === download) inFlight.delete(job.bundle);
    };
    download.finished.then(forget, forget);
  }
  return download.join({ onProgress, signal });
}

/**
 * What a download reports, to every caller alike:
 *
 * - `loaded`, `total`: bytes of v86.wasm and the state held so far, against the
 *   manifest's sizes, which is what a byte count on screen can trust: a server
 *   may compress a file, and then its Content-Length is not the file's.
 * - `cached`: of `loaded`, what the Cache API already held.
 * - `rate`: bytes per second over the network, smoothed; null until there is
 *   enough to go on. `remainingMs`: what is left at that rate, or null.
 * - `stalled`: nothing has arrived for a few seconds, or a request waits to be
 *   tried again. The download goes on by itself.
 * - `keeps`: false when the browser said it has no room: nothing new is kept,
 *   and the next load downloads it again.
 * - `slowConnection`: navigator.connection called the line slow. A hint, not a
 *   promise: it guesses from the page's recent traffic.
 */
class BundleDownload {

  finished;

  #job;
  #now;
  #joiners = new Set();
  #abort = new AbortController();
  #lingerTimer = null;
  #outcome = null;
  #meter;
  #progress;
  #lastReport = -Infinity;
  #requests = 0;
  #waiting = 0;
  #activeSince = null;
  #fetched = 0;

  constructor(job) {
    this.#job = job;
    this.#now = job.now ?? (() => performance.now());
    this.#meter = new RateMeter({ now: this.#now });
    this.#progress = {
      loaded: 0,
      total: job.manifest.v86.wasmBytes + job.manifest.state.bytes,
      cached: 0,
      rate: null,
      remainingMs: null,
      stalled: false,
      keeps: true,
      slowConnection: slowConnection(),
    };
    this.finished = this.#run();
    this.finished.then(
      result => this.#settle({ result }),
      error => this.#settle({ error }),
    );
  }

  /** Every caller left long enough ago that it is being stopped. */
  get stopping() {
    return this.#abort.signal.aborted;
  }

  join({ onProgress, signal }) {
    return new Promise((resolve, reject) => {
      if (this.#outcome) {
        if (this.#outcome.error) reject(this.#outcome.error);
        else resolve(this.#outcome.result);
        return;
      }
      if (signal?.aborted) {
        reject(aborted(signal.reason));
        this.#lingerIfAlone();
        return;
      }
      const joiner = { onProgress, resolve, reject };
      this.#joiners.add(joiner);
      clearTimeout(this.#lingerTimer);
      this.#lingerTimer = null;
      signal?.addEventListener('abort', () => this.#leave(joiner, aborted(signal.reason)), { once: true });
      // A caller that joins part way sees how far it is at once.
      queueMicrotask(() => {
        if (this.#joiners.has(joiner)) tell(joiner, this.#progress);
      });
    });
  }

  #leave(joiner, error) {
    if (!this.#joiners.delete(joiner)) return;
    joiner.reject(error);
    this.#lingerIfAlone();
  }

  #lingerIfAlone() {
    if (this.#joiners.size > 0 || this.#outcome || this.#lingerTimer !== null) return;
    this.#lingerTimer = setTimeout(
      () => this.#abort.abort(aborted('Nobody waits for the download any more.')),
      this.#job.lingerMs ?? LINGER_MS,
    );
  }

  #settle(outcome) {
    this.#outcome = outcome;
    clearTimeout(this.#lingerTimer);
    const joiners = [...this.#joiners];
    this.#joiners.clear();
    for (const joiner of joiners) {
      if (outcome.error) joiner.reject(outcome.error);
      else joiner.resolve(outcome.result);
    }
  }

  async #run() {
    const { base, bundle, manifest, cache } = this.#job;
    const release = cache ? await holdImage(bundle) : () => {};
    const tick = setInterval(() => this.#report(false), TICK_MS);
    const urls = {
      wasm: `${bundle}${manifest.v86.wasm}`,
      state: `${bundle}${manifest.state.file}`,
      lib: `${bundle}${manifest.v86.lib}`,
    };
    const signal = this.#abort.signal;
    const deadlineMs = this.#job.deadlineMs ?? DEADLINE_MS;
    let expire = null;
    try {
      const keeps = await this.#roomFor(urls);
      this.#progress.keeps = keeps;
      // The first file that fails stops the other, whose bytes would otherwise
      // go on arriving after the failure.
      const failFast = new AbortController();
      // Its own error rather than `signal`'s, so that running out of time reads
      // as a failure the page can retry and not as a caller that walked away.
      expire = setTimeout(() => failFast.abort(overdue(deadlineMs)), deadlineMs);
      const unlink = link(signal, failFast);
      const orStop = promise => promise.catch(error => {
        failFast.abort(error);
        throw error;
      });
      const common = {
        cache,
        store: keeps,
        signal: failFast.signal,
        onBytes: (n, fromCache) => this.#count(n, fromCache),
        onRequest: delta => this.#onRequest(delta),
        onWait: delta => {
          this.#waiting += delta;
          this.#report(true);
        },
        fetchImpl: this.#job.fetchImpl,
        retryDelaysMs: this.#job.retryDelaysMs,
        stallMs: this.#job.stallMs,
      };
      let wasm;
      let state;
      try {
        [wasm, state] = await Promise.all([
          orStop(readWhole(urls.wasm, { bytes: manifest.v86.wasmBytes, sha256: manifest.v86.wasmSha256 }, common)),
          orStop(readInPieces(urls.state, { bytes: manifest.state.bytes, sha256: manifest.state.sha256 }, {
            ...common,
            ranges: this.#job.ranges ?? true,
            pieceBytes: this.#job.pieceBytes ?? PIECE_BYTES,
            parallel: this.#job.parallel ?? PARALLEL,
          })),
          keepLib(urls.lib, cache, keeps, this.#job.fetchImpl),
        ]);
      } finally {
        unlink();
      }
      if (cache) await forgetOtherImages(cache, base, bundle);
      this.#report(true);
      return { wasm, state, keeps, cached: this.#progress.cached, fetched: this.#fetched };
    } catch (error) {
      if (signal.aborted) throw aborted(signal.reason?.message ?? 'The download was stopped.');
      throw withReason(error, 'network', error.reason ? error.message : `The VM image could not be downloaded: ${error.message}`);
    } finally {
      clearTimeout(expire);
      clearInterval(tick);
      release();
    }
  }

  /**
   * Whether the browser has room for what is not cached yet. Asked only before
   * a download, never for a load the Cache API can serve. Where it has, a
   * Chromium browser is also asked to keep the origin's storage, which it
   * grants or refuses without asking the student; Firefox would ask, so it is
   * not asked there, and nor is Safari, whose behaviour is not documented.
   */
  async #roomFor(urls) {
    const { cache, manifest } = this.#job;
    if (!cache) return false;
    let missing = 0;
    try {
      if (!(await cache.match(urls.wasm))) missing += manifest.v86.wasmBytes;
      let held = 0;
      for (const piece of await listPieces(cache, urls.state, manifest.state.bytes)) held += piece.end - piece.start + 1;
      missing += manifest.state.bytes - held;
    } catch {
      missing = this.#progress.total;
    }
    if (missing === 0) return true;
    const storage = globalThis.navigator?.storage;
    try {
      const { quota, usage } = await storage.estimate();
      if (Number.isFinite(quota) && Number.isFinite(usage) && quota - usage < missing + ROOM_MARGIN_BYTES) return false;
    } catch {
      // No estimate is no answer: the puts find out, and a refused one is swallowed.
    }
    if (globalThis.navigator?.userAgentData && typeof storage?.persist === 'function') {
      storage.persisted?.().then(persisted => persisted || storage.persist()).catch(() => {});
    }
    return true;
  }

  #count(n, fromCache) {
    if (n === 0) return;
    const progress = this.#progress;
    progress.loaded += n;
    if (fromCache) {
      progress.cached += n;
    } else if (n > 0) {
      this.#fetched += n;
      this.#meter.add(n);
    }
    this.#report(progress.loaded >= progress.total);
  }

  #onRequest(delta) {
    this.#requests += delta;
    if (this.#requests > 0) this.#activeSince ??= this.#now();
    else this.#activeSince = null;
  }

  #report(force) {
    const now = this.#now();
    if (!force && now - this.#lastReport < 100) return;
    this.#lastReport = now;
    this.#meter.sample();
    const progress = this.#progress;
    progress.rate = this.#meter.bytesPerSecond;
    progress.remainingMs = progress.rate ? Math.max(0, (progress.total - progress.loaded) * 1000 / progress.rate) : null;
    const quietSince = Math.max(this.#meter.lastByteAt ?? -Infinity, this.#activeSince ?? Infinity);
    progress.stalled = this.#waiting > 0 || (this.#requests > 0 && now - quietSince >= STALLED_AFTER_MS);
    for (const joiner of this.#joiners) tell(joiner, progress);
  }

}

function tell(joiner, progress) {
  try {
    joiner.onProgress?.({ ...progress });
  } catch (error) {
    console.error(error);
  }
}

/** navigator.connection's guess, where there is one: Chromium only. */
function slowConnection() {
  const connection = globalThis.navigator?.connection;
  if (!connection) return false;
  return connection.saveData === true || ['slow-2g', '2g', '3g'].includes(connection.effectiveType);
}

/**
 * Puts libv86.mjs into the Cache API beside the rest, so a load without the
 * network can still import it. The manifest names no hash for it, so only an
 * answer the server calls JavaScript is kept; a portal's page is HTML. Never
 * rejects: the import is what counts, and it goes to the network first.
 */
async function keepLib(url, cache, keeps, fetchImpl = globalThis.fetch) {
  if (!cache || !keeps) return;
  try {
    if (await cache.match(url)) return;
    const response = await fetchImpl(url);
    if (response.ok && /javascript/i.test(response.headers.get('Content-Type') ?? '')) await cache.put(url, response);
  } catch {
    // Kept or not, the load goes on.
  }
}

// Reading one file

/**
 * Reads a file of the bundle through the Cache API, as one request. A copy that
 * fails the check is never cached, and a cached one that fails it is deleted:
 * either would fail every later load, Retry included. Each is fetched once
 * more past the HTTP cache, which may hold the same bad copy.
 *
 * This is the whole file in one request, with no Range and so no resume: an
 * attempt that fails starts again at byte zero, `RETRY_DELAYS_MS.length` times.
 * Only the state goes through `readInPieces`, because the state is 15 MB and
 * v86.wasm 2, and a piece kept is a piece to be checked, deleted and counted
 * again. docs/vm-build.md, "The download", says the same to a reader of the docs.
 */
export async function readWhole(url, check, options) {
  const { cache, store, onBytes } = options;
  const kept = await cache?.match(url).catch(() => undefined);
  let again = false;
  if (kept) {
    const bytes = await kept.arrayBuffer().then(buffer => new Uint8Array(buffer), () => null);
    if (bytes && !(await mismatch(bytes, check))) {
      onBytes(bytes.byteLength, true);
      return bytes;
    }
    await cache.delete(url).catch(() => {});
    again = true;
  }
  let bytes = await withRetries(() => download(url, again, options), options);
  let problem = await mismatch(bytes, check);
  if (problem && !again) {
    onBytes(-bytes.byteLength, false);
    bytes = await withRetries(() => download(url, true, options), options);
    problem = await mismatch(bytes, check);
  }
  if (problem) {
    onBytes(-bytes.byteLength, false);
    throw notIntact(url, problem);
  }
  if (cache && store) await cache.put(url, new Response(bytes)).catch(() => {});
  return bytes;
}

async function download(url, pastHttpCache, { onBytes, onRequest, signal, fetchImpl = globalThis.fetch }) {
  onRequest?.(1);
  const parts = [];
  let length = 0;
  try {
    const response = await fetchImpl(url, pastHttpCache ? { cache: 'reload', signal } : { signal });
    if (!response.ok) throw httpError(response.status, url);
    const reader = response.body.getReader();
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      parts.push(value);
      length += value.byteLength;
      onBytes(value.byteLength, false);
    }
  } catch (error) {
    onBytes(-length, false);
    throw error;
  } finally {
    onRequest?.(-1);
  }
  const bytes = new Uint8Array(length);
  let at = 0;
  for (const part of parts) {
    bytes.set(part, at);
    at += part.byteLength;
  }
  return bytes;
}

/**
 * Reads `url` in HTTP Range pieces, each kept in the Cache API as it lands, and
 * resolves once the whole file is here and matches `check`. A load that finds
 * pieces from an earlier one fetches only what is missing, and a piece cut
 * short keeps what arrived.
 *
 * The first request goes alone and decides how the rest go. A 206 whose
 * Content-Range fits lets the others follow, `parallel` at a time. A 200, or a
 * 206 of another representation (a server that compresses answers ranges of
 * the compressed bytes, which the Content-Range's total gives away), means the
 * server will not do ranges for this file: the answer is read as the whole
 * file, and whatever pieces were kept are dropped. `ranges: false` asks for the
 * whole file at once.
 *
 * Nothing names a piece's hash, so only the whole file is checked. When it
 * fails, every piece is deleted, since there is no telling which one is wrong,
 * and it is read once more from the network.
 *
 * @param {string} url
 * @param {{bytes: number, sha256?: string}} check
 * @param {object} options
 * @param {Cache | null} options.cache
 * @param {boolean} options.store Whether to keep new pieces.
 * @param {(n: number, fromCache: boolean) => void} options.onBytes Bytes held;
 *     negative for bytes taken back.
 * @param {(delta: number) => void} [options.onRequest] A request starts (1) or ends (-1).
 * @param {(delta: number) => void} [options.onWait] A retry starts waiting (1) or stops (-1).
 * @param {AbortSignal} [options.signal] Stops it; the pieces kept so far stay.
 * @returns {Promise<Uint8Array>}
 */
export function readInPieces(url, check, options) {
  return new PieceReader(url, check, options).read();
}

class PieceReader {

  #url;
  #check;
  #size;
  #options;
  #store;
  #whole = null;
  /** What #whole holds, as [start, end] ranges, sorted and apart. */
  #have = [];
  /** What was counted through onBytes, so a refused file can be taken back. */
  #counted = { cache: 0, network: 0 };
  #queue = [];
  #mode = null;
  #decide = null;
  #decided = null;
  #puts = [];

  constructor(url, check, options) {
    this.#url = url;
    this.#check = check;
    this.#size = check.bytes;
    this.#options = options;
    this.#store = Boolean(options.cache && options.store);
  }

  async read() {
    for (let attempt = 0; ; attempt++) {
      try {
        await this.#fill(attempt > 0);
        const problem = await mismatch(this.#whole, this.#check);
        if (!problem) return this.#whole;
        throw notIntact(this.#url, problem);
      } catch (error) {
        if (!error.notIntact || this.#options.signal?.aborted) throw error;
        await this.#discard();
        if (attempt > 0) throw error;
      }
    }
  }

  async #fill(fresh) {
    const size = this.#size;
    this.#whole ??= new Uint8Array(size);
    this.#have = [];
    this.#mode = null;
    this.#decided = new Promise(resolve => { this.#decide = resolve; });
    if (!fresh) await this.#loadKept();

    const missing = gaps(this.#have, size);
    if (missing.length === 0) return;
    this.#queue = this.#options.ranges === false ? [] : split(missing, this.#options.pieceBytes ?? PIECE_BYTES);
    if (this.#options.ranges === false) this.#setMode('whole');

    const attempt = new AbortController();
    const unlink = link(this.#options.signal, attempt);
    const workers = [];
    try {
      workers.push(this.#work(this.#queue.shift() ?? { start: 0, end: size - 1 }, attempt.signal));
      await Promise.race([this.#decided, workers[0]]);
      if (this.#mode === 'ranged') {
        for (let i = 1; i < (this.#options.parallel ?? PARALLEL); i++) workers.push(this.#work(null, attempt.signal));
      }
      await Promise.all(workers);
    } catch (error) {
      attempt.abort(error);
      await Promise.allSettled(workers);
      throw error;
    } finally {
      unlink();
      await Promise.allSettled(this.#puts);
      this.#puts = [];
    }
    if (gaps(this.#have, size).length > 0) throw notIntact(this.#url, 'ended with bytes missing');
  }

  /** Reads what earlier loads kept. A piece whose body is not its size is deleted. */
  async #loadKept() {
    const cache = this.#options.cache;
    if (!cache) return;
    for (const piece of await listPieces(cache, this.#url, this.#size)) {
      let bytes = null;
      try {
        const response = await cache.match(piece.request);
        if (response) bytes = new Uint8Array(await response.arrayBuffer());
      } catch {
        bytes = null;
      }
      if (bytes?.byteLength !== piece.end - piece.start + 1) {
        await cache.delete(piece.request).catch(() => {});
        continue;
      }
      this.#whole.set(bytes, piece.start);
      this.#hold(piece.start, piece.end);
      this.#count(bytes.byteLength, true);
    }
  }

  async #work(first, signal) {
    let segment = first ?? this.#queue.shift();
    while (segment) {
      await this.#fetchSegment(segment, signal);
      if (this.#mode === 'whole') return;
      segment = this.#queue.shift();
    }
  }

  /**
   * Fetches `segment`, asking again from where it stopped while it makes real
   * progress: an attempt that delivers `MIN_PROGRESS_BYTES` starts the retries
   * over, and one that delivers less does not. A short 206 is a legitimate
   * answer, so a server that keeps giving a sliver of every Range fails here
   * like any other server that cannot deliver, rather than being resumed until
   * the page is closed.
   */
  async #fetchSegment(segment, signal) {
    const delays = this.#options.retryDelaysMs ?? RETRY_DELAYS_MS;
    const enough = this.#options.minProgressBytes ?? MIN_PROGRESS_BYTES;
    let streak = 0;
    for (;;) {
      const got = { bytes: 0 };
      const wanted = segment.end - segment.start + 1;
      let failure = null;
      let short = false;
      try {
        const end = await this.#request(segment, got, signal);
        if (end >= segment.end || this.#mode === 'whole') return;
        failure = tooLittle(this.#url, got.bytes, segment.start, wanted);
        short = true;
        segment = { start: end + 1, end: segment.end };
      } catch (error) {
        if (signal.aborted || isPermanent(error)) throw error;
        failure = error;
        if (this.#mode === 'ranged' && got.bytes > 0) {
          segment = { start: segment.start + got.bytes, end: segment.end };
          if (segment.start > segment.end) return;
        }
      }
      if (got.bytes >= enough) {
        streak = 0;
        // The answer was whole, only smaller than asked for: ask for the rest at once.
        if (short) continue;
      }
      if (streak >= delays.length) throw failure;
      await this.#waitToRetry(delays[streak++], signal);
    }
  }

  /**
   * One request for `segment`: a Range request, or a plain one once the server
   * turned out not to do ranges. Resolves with the last byte it filled in.
   * `got.bytes` counts what arrived, for the caller to resume from.
   */
  async #request(segment, got, signal) {
    for (;;) {
      const end = await this.#requestOnce(segment, got, signal);
      if (end !== UNUSABLE_RANGE) return end;
    }
  }

  async #requestOnce(segment, got, signal) {
    const size = this.#size;
    const own = new AbortController();
    const unlink = link(signal, own);
    const whole = this.#mode === 'whole';
    const init = { cache: 'no-store', signal: own.signal };
    if (!whole) init.headers = { Range: `bytes=${segment.start}-${segment.end}` };
    this.#options.onRequest?.(1);
    let into = null;
    try {
      const response = await (this.#options.fetchImpl ?? globalThis.fetch)(this.#url, init);
      if (response.status === 206 && !whole) {
        const range = contentRange(response.headers.get('Content-Range'));
        // A total of `*` is a server that does not know the complete length
        // (RFC 9110 14.4), which contradicts nothing: only a total that is
        // there and is not the manifest's says this is another representation.
        // What the pieces add up to is held to `check` either way.
        const wrongTotal = range?.total !== null && range?.total !== size;
        if (!range || range.start !== segment.start || range.end > segment.end || wrongTotal) {
          response.body?.cancel().catch(() => {});
          if (this.#mode === 'ranged') {
            throw notIntact(this.#url, `came back as ${response.headers.get('Content-Range')} for bytes ${segment.start}-${segment.end}`);
          }
          this.#setMode('whole');
          return UNUSABLE_RANGE;
        }
        this.#setMode('ranged');
        into = { start: segment.start };
        await this.#stream(response, segment.start, range.end - range.start + 1, got, own);
        if (got.bytes < range.end - range.start + 1) {
          throw new Error(`${this.#url} ended ${got.bytes} bytes into bytes ${range.start}-${range.end}.`);
        }
        return range.end;
      }
      if (response.status === 200) {
        if (this.#mode === 'ranged') {
          response.body?.cancel().catch(() => {});
          throw notIntact(this.#url, 'stopped answering ranges part way');
        }
        this.#setMode('whole');
        this.#queue.length = 0;
        this.#takeBack();
        into = { start: 0, whole: true };
        await this.#stream(response, 0, size, got, own, true);
        if (got.bytes < size) throw new Error(`${this.#url} ended after ${got.bytes} of ${size} bytes.`);
        return size - 1;
      }
      response.body?.cancel().catch(() => {});
      if (response.status === 416) throw notIntact(this.#url, 'is shorter than the manifest says');
      throw httpError(response.status, this.#url);
    } catch (error) {
      if (!into) throw error;
      if (into.whole) {
        // A server without ranges cannot resume: the next try starts over.
        this.#count(-got.bytes, false);
        got.bytes = 0;
      } else if (got.bytes > 0) {
        this.#hold(into.start, into.start + got.bytes - 1);
        this.#keep(into.start, into.start + got.bytes - 1, true);
      }
      throw error;
    } finally {
      unlink();
      this.#options.onRequest?.(-1);
    }
  }

  /** Streams `response` into #whole at `offset`, `expected` bytes of it. */
  async #stream(response, offset, expected, got, controller, whole = false) {
    const stallMs = this.#options.stallMs ?? STALL_MS;
    let timer = null;
    const arm = () => {
      clearTimeout(timer);
      timer = setTimeout(() => controller.abort(new Error(`Nothing arrived for ${stallMs / 1000} s.`)), stallMs);
    };
    let overflow = 0;
    const reader = response.body?.getReader();
    arm();
    try {
      while (reader) {
        const { done, value } = await reader.read();
        if (done) break;
        arm();
        const room = expected - got.bytes;
        const fits = Math.min(room, value.byteLength);
        if (fits > 0) {
          this.#whole.set(value.subarray(0, fits), offset + got.bytes);
          got.bytes += fits;
          this.#count(fits, false);
        }
        overflow += value.byteLength - fits;
        if (overflow > 0 && (!whole || overflow > OVERFLOW_LIMIT_BYTES)) break;
      }
    } finally {
      clearTimeout(timer);
    }
    if (overflow > 0) {
      reader.cancel().catch(() => {});
      const length = overflow > OVERFLOW_LIMIT_BYTES || !whole ? `over ${expected + overflow}` : `${expected + overflow}`;
      throw notIntact(this.#url, `is ${length} bytes, not ${expected}`);
    }
    if (got.bytes === expected) {
      this.#hold(offset, offset + expected - 1);
      if (whole) {
        await deletePieces(this.#options.cache ?? noCache, this.#url);
        this.#keep(0, expected - 1, false);
      } else {
        this.#keep(offset, offset + expected - 1, false);
      }
    }
  }

  #setMode(mode) {
    this.#mode = mode;
    this.#decide?.();
  }

  #hold(start, end) {
    this.#have = merge([...this.#have, [start, end]]);
  }

  /** Puts #whole's bytes `start` to `end` into the cache as a piece. */
  #keep(start, end, partial) {
    if (!this.#store || (partial && end - start + 1 < MIN_KEPT_BYTES)) return;
    const response = new Response(this.#whole.slice(start, end + 1));
    this.#puts.push(this.#options.cache.put(pieceKey(this.#url, start, end), response).catch(error => {
      if (error?.name === 'QuotaExceededError') this.#store = false;
    }));
  }

  #count(n, fromCache) {
    if (n === 0) return;
    this.#counted[fromCache ? 'cache' : 'network'] += n;
    this.#options.onBytes(n, fromCache);
  }

  /** Takes back every byte counted so far and forgets what #whole holds. */
  #takeBack() {
    this.#count(-this.#counted.cache, true);
    this.#count(-this.#counted.network, false);
    this.#have = [];
  }

  async #discard() {
    await Promise.allSettled(this.#puts);
    this.#puts = [];
    if (this.#options.cache) await deletePieces(this.#options.cache, this.#url);
    this.#takeBack();
  }

  async #waitToRetry(delay, signal) {
    this.#options.onWait?.(1);
    try {
      await sleep(delay, signal);
      if (globalThis.navigator?.onLine === false) await online(OFFLINE_WAIT_MS, signal);
    } finally {
      this.#options.onWait?.(-1);
    }
  }

}

const noCache = { keys: async () => [], delete: async () => false };

/** A 206 that is not a range of the file itself: ask again without a Range. */
const UNUSABLE_RANGE = Symbol('unusable range');

/** A 206's Content-Range, `bytes START-END/TOTAL`, or null. */
export function contentRange(header) {
  const found = /^bytes (\d+)-(\d+)\/(\d+|\*)$/i.exec(header?.trim() ?? '');
  if (!found) return null;
  const start = Number(found[1]);
  const end = Number(found[2]);
  return start <= end ? { start, end, total: found[3] === '*' ? null : Number(found[3]) } : null;
}

function merge(ranges) {
  ranges.sort((a, b) => a[0] - b[0]);
  const merged = [];
  for (const [start, end] of ranges) {
    const last = merged.at(-1);
    if (last && start <= last[1] + 1) last[1] = Math.max(last[1], end);
    else merged.push([start, end]);
  }
  return merged;
}

/** The ranges of [0, size) that `have` leaves out, as {start, end}. */
function gaps(have, size) {
  const missing = [];
  let at = 0;
  for (const [start, end] of have) {
    if (start > at) missing.push({ start: at, end: start - 1 });
    at = Math.max(at, end + 1);
  }
  if (at < size) missing.push({ start: at, end: size - 1 });
  return missing;
}

function split(ranges, pieceBytes) {
  const pieces = [];
  for (const { start, end } of ranges) {
    for (let at = start; at <= end; at += pieceBytes) pieces.push({ start: at, end: Math.min(end, at + pieceBytes - 1) });
  }
  return pieces;
}

async function withRetries(attempt, { signal, onWait, retryDelaysMs = RETRY_DELAYS_MS }) {
  for (let tries = 0; ; tries++) {
    try {
      return await attempt();
    } catch (error) {
      if (signal?.aborted || isPermanent(error) || tries >= retryDelaysMs.length) throw error;
      onWait?.(1);
      try {
        await sleep(retryDelaysMs[tries], signal);
        if (globalThis.navigator?.onLine === false) await online(OFFLINE_WAIT_MS, signal);
      } finally {
        onWait?.(-1);
      }
    }
  }
}

/** A 404 means a deploy took the file away, and it will not come back; a
 *  file that is not what the manifest names comes back the same next time. */
function isPermanent(error) {
  if (error?.notIntact) return true;
  const status = error?.status;
  return typeof status === 'number' && status >= 400 && status < 500 && status !== 408 && status !== 429;
}

/** Makes `signal` abort `controller` too; returns the function that stops that. */
function link(signal, controller) {
  if (!signal) return () => {};
  if (signal.aborted) {
    controller.abort(signal.reason);
    return () => {};
  }
  const onAbort = () => controller.abort(signal.reason);
  signal.addEventListener('abort', onAbort, { once: true });
  return () => signal.removeEventListener('abort', onAbort);
}

function sleep(ms, signal) {
  return new Promise((resolve, reject) => {
    if (signal?.aborted) {
      reject(signal.reason);
      return;
    }
    const onAbort = () => {
      clearTimeout(timer);
      reject(signal.reason);
    };
    const timer = setTimeout(() => {
      signal?.removeEventListener('abort', onAbort);
      resolve();
    }, ms);
    signal?.addEventListener('abort', onAbort, { once: true });
  });
}

/** Resolves when the browser says it is online again, or after `ms`. */
function online(ms, signal) {
  const target = globalThis.addEventListener ? globalThis : null;
  if (!target) return sleep(0, signal);
  return new Promise((resolve, reject) => {
    const done = () => {
      clearTimeout(timer);
      target.removeEventListener('online', done);
      signal?.removeEventListener('abort', onAbort);
      resolve();
    };
    const onAbort = () => {
      done();
      reject(signal.reason);
    };
    const timer = setTimeout(done, ms);
    target.addEventListener('online', done);
    signal?.addEventListener('abort', onAbort, { once: true });
  });
}

/**
 * Why `bytes` is not the file the manifest names, or null when it is.
 *
 * @param {{bytes: number, sha256?: string}} check The manifest's size, and its
 *     sha256 where it names one.
 */
export async function mismatch(bytes, check) {
  if (bytes.byteLength !== check.bytes) return `is ${bytes.byteLength} bytes, not ${check.bytes}`;
  // SubtleCrypto exists only in a secure context, and so does the Cache API
  // that could keep a bad copy; elsewhere the size is the whole check.
  const subtle = globalThis.crypto?.subtle;
  if (typeof check.sha256 !== 'string' || !subtle) return null;
  const digest = Array.from(new Uint8Array(await subtle.digest('SHA-256', bytes)), b => b.toString(16).padStart(2, '0')).join('');
  return digest === check.sha256.toLowerCase() ? null : `has sha256 ${digest}, not ${check.sha256}`;
}

export function notIntact(url, problem) {
  return Object.assign(withReason(new Error(`${url} did not arrive intact: it ${problem}.`), 'network'), { notIntact: true });
}

function httpError(status, url) {
  return Object.assign(new Error(`HTTP ${status} for ${url}`), { status });
}

/** A server that answered, and answered with too little of what was asked for. */
function tooLittle(url, bytes, start, wanted) {
  return withReason(new Error(`${url} answered ${bytes} bytes of the ${wanted} asked for from byte ${start}.`), 'network');
}

function overdue(ms) {
  return withReason(new Error(`The VM image did not download within ${Math.round(ms / 1000)} s.`), 'network');
}

function aborted(reason) {
  const message = typeof reason === 'string' ? reason : reason?.message ?? 'The download was stopped.';
  return withReason(new Error(message), 'aborted');
}

export function withReason(error, reason, message) {
  const wrapped = new Error(message ?? error.message);
  wrapped.reason = error.reason ?? reason;
  return wrapped;
}
