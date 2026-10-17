// An image bundle, web/vm/image/: its manifest, its v86 build and its state,
// read through the Cache API in the browser and from disk under Node, and the
// state made ready to restore.

import { deletePieces, holdImage, openCache, RootfsCache } from './vm_cache.js';
import { joinDownload, mismatch, notIntact, withReason } from './vm_download.js';
import { VERSION } from './vm_protocol.js';
import { isLocalPath, toArrayBuffer } from './vm_util.js';

// The packaging tools hold a bundle to its manifest the way a page does.
export { mismatch };

/** The first four bytes of a zstd frame, read as a little-endian u32. */
const ZSTD_MAGIC = 0xFD2FB528;

/** Past this the worker is taken to be stuck, and the state is restored compressed. */
const INFLATE_TIMEOUT_MS = 30_000;

/**
 * Reads web/vm/image/: the manifest, then the bundle it names.
 *
 * In the browser the files go through the Cache API under their bundle's URLs,
 * which change whenever the image does, so a cached copy never goes stale and a
 * second visit reads them without a request. Only the manifest is revalidated.
 * The state downloads in Range pieces that are kept as they land, and a load
 * that finds some fetches only the rest (vm_download.js). A browser that
 * refuses storage downloads again; that is never a failure.
 *
 * There is one download per image on the page: a load that starts while another
 * caller's, or a prefetchBundle(), is under way joins it and sees the same
 * progress.
 *
 * The wasm and the state are held to the manifest's size and sha256 before they
 * are cached, and again whenever they are read back from the cache. The first
 * file that fails aborts the others, and `onProgress` is not called after it.
 *
 * @param {object} options openVm()'s: `baseUrl`, and `readAsset` for the tools.
 *     `signal` leaves the download; the image's pieces kept so far stay.
 * @param {(progress: object) => void} onProgress What vm_download.js's
 *     BundleDownload reports.
 * @returns {Promise<{manifest: object, V86: Function, wasm: Uint8Array, state: ArrayBuffer,
 *     rootfsUrl: string, release: () => void, evictState: () => Promise<void>,
 *     rootfsCache: RootfsCache | null, keeps: boolean}>} `release` ends this page's claim on the
 *     image's cached files; until then no other tab deletes them. `evictState` deletes the cached
 *     state, so that the next load downloads it again.
 */
export async function loadBundle(options, onProgress) {
  const { base, local } = resolveBase(options.baseUrl);
  const cache = local ? null : await openCache();
  const manifest = await manifestOf(base, local, cache);

  const bundle = `${base}${manifest.imageId}/`;
  const rootfsUrl = `${bundle}${manifest.rootfs.dir}`;
  if (options.readAsset || local) {
    const read = await readDirectly(options, manifest, bundle, local, onProgress);
    return { manifest, ...read, rootfsUrl, release: () => {}, evictState: async () => {}, rootfsCache: null, keeps: false };
  }

  const release = cache ? await holdImage(bundle) : () => {};
  // Promise.all rejects on the first failure but stops nothing: this caller
  // would go on hearing the download's progress after its `failed`, and the page
  // would go back to its loading panel for good.
  const leave = new AbortController();
  const unlink = linkSignal(options.signal, leave);
  const libUrl = `${bundle}${manifest.v86.lib}`;
  let files;
  let V86;
  try {
    [files, { V86 }] = await Promise.all([
      joinDownload(
        { base, bundle, manifest, cache, ...options.download },
        { onProgress, signal: leave.signal },
      ),
      importLib(libUrl, cache).catch(error => {
        leave.abort(error);
        throw withReason(error, 'network', `The VM image could not be downloaded: ${error.message}`);
      }),
    ]);
  } catch (error) {
    leave.abort(error);
    release();
    throw withReason(error, 'network');
  } finally {
    unlink();
  }
  const stateUrl = `${bundle}${manifest.state.file}`;
  return {
    manifest,
    V86,
    wasm: files.wasm,
    state: toArrayBuffer(files.state),
    rootfsUrl,
    release,
    evictState: async () => {
      if (cache) await deletePieces(cache, stateUrl);
    },
    rootfsCache: cache ? new RootfsCache(cache, rootfsUrl, { writable: files.keeps }) : null,
    keeps: files.keeps,
  };
}

/**
 * Downloads an image into the Cache API without building a machine, so that a
 * later openVm() finds it there. It joins the image's download when one is
 * under way, and a load that starts while this one is under way joins it, so
 * the image is downloaded once and every caller sees the same progress.
 *
 * Under Node, where a bundle is a directory, there is nothing to download, and
 * it resolves at once.
 *
 * @param {object} options
 * @param {string} options.baseUrl As openVm()'s.
 * @param {(progress: object) => void} [options.onProgress] The `progress`
 *     event's fields but `type` and `phase`, at most every 100 ms, from the
 *     current state of the download at once and never after this settles.
 * @param {AbortSignal} [options.signal] Stops waiting. The download goes on
 *     while another caller waits for it, and stops 5 s after the last one left;
 *     the pieces kept so far stay, and the next download starts from them.
 * @returns {Promise<{imageId: string, total: number, cached: number, fetched: number, keeps: boolean}>}
 *     `cached` of `total` bytes came from the Cache API and `fetched` from the
 *     network; `keeps` false means the browser had no room for them. Rejects
 *     with `reason` `network`, `incompatible` or `aborted`.
 */
export async function prefetchBundle({ baseUrl, onProgress, signal, download } = {}) {
  if (!baseUrl) throw new TypeError('baseUrl is required');
  const { base, local } = resolveBase(baseUrl);
  const cache = local ? null : await openCache();
  const manifest = await manifestOf(base, local, cache);
  const total = manifest.v86.wasmBytes + manifest.state.bytes;
  if (local) return { imageId: manifest.imageId, total, cached: total, fetched: 0, keeps: true };
  const bundle = `${base}${manifest.imageId}/`;
  const files = await joinDownload({ base, bundle, manifest, cache, ...download }, { onProgress, signal });
  return { imageId: manifest.imageId, total, cached: files.cached, fetched: files.fetched, keeps: files.keeps };
}

function resolveBase(baseUrl) {
  const withSlash = baseUrl.endsWith('/') ? baseUrl : `${baseUrl}/`;
  const local = isLocalPath(withSlash);
  // Cache keys and the import below need absolute URLs. A relative base is
  // resolved as fetch() would: against the document's <base href>, which in the
  // app is not the page's own path-routed URL.
  const base = local ? withSlash : new URL(withSlash, globalThis.document?.baseURI ?? globalThis.location?.href).href;
  return { base, local };
}

async function manifestOf(base, local, cache) {
  let manifest;
  try {
    manifest = await readManifest(`${base}manifest.json`, local, cache);
  } catch (error) {
    throw withReason(error, 'network', `The VM image manifest could not be read: ${error.message}`);
  }
  if (manifest.agentProto !== VERSION) {
    throw withReason(new Error(`The image speaks protocol ${manifest.agentProto}, this page ${VERSION}.`), 'incompatible');
  }
  return manifest;
}

/**
 * Imports libv86.mjs from the network, as any module, and from the copy the
 * Cache API keeps where that fails: offline, a module the HTTP cache no longer
 * vouches for fails to import. The copy is imported from a blob URL, and one
 * that does not import is deleted.
 */
async function importLib(url, cache) {
  try {
    return await import(url);
  } catch (error) {
    const kept = await cache?.match(url).catch(() => undefined);
    if (!kept) throw error;
    const blobUrl = URL.createObjectURL(new Blob([await kept.arrayBuffer()], { type: 'text/javascript' }));
    try {
      return await import(blobUrl);
    } catch {
      await cache.delete(url).catch(() => {});
      throw error;
    } finally {
      URL.revokeObjectURL(blobUrl);
    }
  }
}

/** The tools' way: files from disk or from `options.readAsset`, nothing kept. */
async function readDirectly(options, manifest, bundle, local, onProgress) {
  const total = manifest.v86.wasmBytes + manifest.state.bytes;
  const aborter = new AbortController();
  const { signal } = aborter;
  const orAbort = promise => promise.catch(error => {
    aborter.abort();
    throw error;
  });
  let loaded = 0;
  let reported = 0;
  const onBytes = n => {
    if (signal.aborted) return;
    loaded += n;
    const now = performance.now();
    if (now - reported >= 100 || loaded >= total) {
      reported = now;
      onProgress({
        loaded: Math.min(loaded, total), total, cached: 0, rate: null, remainingMs: null,
        stalled: false, keeps: false, slowConnection: false,
      });
    }
  };
  const read = options.readAsset ?? readLocal;
  const checked = async (url, check) => {
    const bytes = await read(url, onBytes, signal);
    const problem = await mismatch(bytes, check);
    if (problem) throw notIntact(url, problem);
    return bytes;
  };
  const libUrl = `${bundle}${manifest.v86.lib}`;
  try {
    const [wasm, state, { V86 }] = await Promise.all([
      orAbort(checked(`${bundle}${manifest.v86.wasm}`, { bytes: manifest.v86.wasmBytes, sha256: manifest.v86.wasmSha256 })),
      orAbort(checked(`${bundle}${manifest.state.file}`, { bytes: manifest.state.bytes, sha256: manifest.state.sha256 })),
      orAbort((local ? fileUrl(libUrl) : Promise.resolve(libUrl)).then(url => import(url))),
    ]);
    return { V86, wasm, state: toArrayBuffer(state) };
  } catch (error) {
    throw withReason(error, 'network', error.reason ? error.message : `The VM image could not be downloaded: ${error.message}`);
  }
}

function linkSignal(signal, controller) {
  if (!signal) return () => {};
  if (signal.aborted) {
    controller.abort(signal.reason);
    return () => {};
  }
  const onAbort = () => controller.abort(signal.reason);
  signal.addEventListener('abort', onAbort, { once: true });
  return () => signal.removeEventListener('abort', onAbort);
}

/**
 * Decompresses a zstd state, once per page, away from the main thread.
 *
 * v86 decompresses a zstd state inside restore_state, synchronously: one long
 * task on every park, 122 ms at 1× and 494 ms at 4× CPU throttling in Chrome,
 * and each one grows its wasm memory. A raw state restores in 49 and 73 ms.
 * v86's own zstd_decompress_worker is not used: it starts from `wasm_source`,
 * which v86 sets only when it fetches its wasm itself rather than through the
 * host's wasm_fn, and it keeps its worker and that worker's 173 MiB for the
 * life of the page. This one ends its worker as soon as the state is back.
 *
 * @param {ArrayBuffer} state The state as the bundle holds it.
 * @param {BufferSource | WebAssembly.Module} wasm The v86.wasm that saved it; its
 *     zstd decoder is the one used.
 * @param {number | undefined} rawBytes The decompressed size, from the manifest.
 * @returns {Promise<{state: ArrayBuffer, where: 'worker' | 'inline' | null, ms: number}>}
 *     `where` is null when there was nothing to do: a raw state, or no size to
 *     decompress to. It rejects when decompression fails; the zstd state still restores.
 */
export async function inflateState(state, wasm, rawBytes) {
  const started = performance.now();
  if (!isZstd(state) || !(rawBytes > 0)) return { state, where: null, ms: 0 };
  const inWorker = typeof Worker === 'function' && typeof Blob === 'function' && typeof URL?.createObjectURL === 'function';
  const raw = inWorker
    ? await inflateInWorker(wasm, state, rawBytes)
    : inflateZstd(wasm, state, rawBytes);
  if (raw.byteLength !== rawBytes) throw new Error(`The state decompressed to ${raw.byteLength} bytes, not ${rawBytes}.`);
  return { state: raw, where: inWorker ? 'worker' : 'inline', ms: performance.now() - started };
}

function isZstd(state) {
  return state.byteLength >= 4 && new DataView(state).getUint32(0, true) === ZSTD_MAGIC;
}

/**
 * Decompresses `zstd` with the zstd decoder in v86.wasm, in an instance of its
 * own whose memory goes when it does. It closes over nothing, because the
 * worker runs it from its source text.
 */
function inflateZstd(wasm, zstd, size) {
  const module = wasm instanceof WebAssembly.Module ? wasm : new WebAssembly.Module(wasm);
  const imports = {};
  for (const { module: from, name, kind } of WebAssembly.Module.imports(module)) {
    imports[from] ??= {};
    // 1924 entries is what v86's own starter creates the table with. Nothing in
    // the decoder calls out, so every function is a tripwire.
    imports[from][name] = kind === 'table'
      ? new WebAssembly.Table({ element: 'anyfunc', initial: 1924 })
      : () => { throw new Error(`v86.wasm called ${name} while decompressing.`); };
  }
  const { exports } = new WebAssembly.Instance(module, imports);
  const source = new Uint8Array(zstd);
  const context = exports.zstd_create_ctx(source.length);
  new Uint8Array(exports.memory.buffer).set(source, exports.zstd_get_src_ptr(context) >>> 0);
  const at = exports.zstd_read(context, size) >>> 0;
  const raw = exports.memory.buffer.slice(at, at + size);
  exports.zstd_read_free(at, size);
  exports.zstd_free_ctx(context);
  return raw;
}

function inflateInWorker(wasm, zstd, size) {
  const source = `${inflateZstd}
onmessage = ({ data }) => {
  try {
    const state = inflateZstd(data.wasm, data.zstd, data.size);
    postMessage({ state }, [state]);
  } catch (error) {
    postMessage({ error: String(error && error.message || error) });
  }
};`;
  const url = URL.createObjectURL(new Blob([source], { type: 'text/javascript' }));
  let worker;
  try {
    worker = new Worker(url);
  } finally {
    URL.revokeObjectURL(url);
  }
  return new Promise((resolve, reject) => {
    const finish = (error, state) => {
      clearTimeout(timer);
      worker.terminate();
      if (error) reject(error);
      else resolve(state);
    };
    const timer = setTimeout(() => finish(new Error(`No state from the worker within ${INFLATE_TIMEOUT_MS} ms.`)), INFLATE_TIMEOUT_MS);
    worker.onmessage = ({ data }) => finish(data.error ? new Error(data.error) : null, data.state);
    worker.onerror = event => {
      event.preventDefault?.();
      finish(new Error(event.message || 'The decompression worker failed.'));
    };
    // Copied rather than transferred: the zstd state is what restores if this fails.
    worker.postMessage({ wasm, zstd, size });
  });
}

/** The manifest is the one file revalidated on every load, since it names the
 *  image; offline, or behind a portal that answers with a page of its own, the
 *  copy from the last load stands in. */
async function readManifest(url, local, cache) {
  if (local) return parseManifest(await readLocal(url));
  try {
    const response = await fetch(url, { cache: 'no-cache' });
    if (!response.ok) throw Object.assign(new Error(`HTTP ${response.status}`), { status: response.status });
    const bytes = new Uint8Array(await response.arrayBuffer());
    const manifest = parseManifest(bytes);
    cache?.put(url, new Response(bytes)).catch(() => {});
    return manifest;
  } catch (error) {
    const kept = await cache?.match(url).catch(() => undefined);
    if (kept) {
      try {
        return parseManifest(new Uint8Array(await kept.arrayBuffer()));
      } catch {
        // A copy cached before manifests were checked; the network's error says more.
      }
    }
    throw error;
  }
}

function parseManifest(bytes) {
  const manifest = JSON.parse(new TextDecoder().decode(bytes));
  if (typeof manifest?.imageId !== 'string' || !manifest.imageId) throw new Error('The manifest names no image.');
  return manifest;
}

async function readLocal(file, onBytes, signal) {
  const { readFile } = await import('node:fs/promises');
  const bytes = new Uint8Array(await readFile(file, { signal }));
  onBytes?.(bytes.byteLength);
  return bytes;
}

async function fileUrl(file) {
  const { pathToFileURL } = await import('node:url');
  return pathToFileURL(file).href;
}
