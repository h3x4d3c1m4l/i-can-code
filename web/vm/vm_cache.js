// The VM's side of the Cache API: one cache for every image's files, the Web
// Locks that keep a tab's image from being deleted under it, the pieces a file
// is kept in while it downloads, and the rootfs files programs fetched.

const MiB = 1024 * 1024;

const CACHE_NAME = 'icc-vm';

/** Web Lock names are one namespace per origin; the bundle URL follows this. */
const IMAGE_LOCK_PREFIX = 'icc-vm-image ';

/** Rootfs files kept per image. A run's working set beyond what the snapshot
 *  holds open is a few MiB, so this keeps many programs' worth. */
export const ROOTFS_CACHE_BYTES = 32 * MiB;

/** The rootfs cache's own record of what it keeps, beside the files. Not a
 *  rootfs file name: those are ten hex digits and `.bin.zst`. */
const ROOTFS_INDEX = '.icc-index.json';

/** A burst of files a program reads is recorded once, not per file. */
const INDEX_SAVE_DELAY_MS = 1000;

/** The page's cache, or null where the browser refuses the Cache API. */
export async function openCache() {
  try {
    return await globalThis.caches?.open(CACHE_NAME) ?? null;
  } catch {
    return null;
  }
}

/**
 * Claims the image in `bundleUrl` for this page with a shared Web Lock, so that
 * another tab that loads a newer image leaves its cached files alone. Resolves
 * once the lock is held, with the function that lets it go. A page closing lets
 * go of it too.
 */
export async function holdImage(bundleUrl, locks = globalThis.navigator?.locks) {
  if (typeof locks?.request !== 'function') return () => {};
  let release;
  const held = new Promise(resolve => { release = resolve; });
  try {
    await new Promise((granted, refused) => {
      locks.request(IMAGE_LOCK_PREFIX + bundleUrl, { mode: 'shared' }, () => {
        granted();
        return held;
      }).catch(refused);
    });
  } catch {
    // Storage the page may not use has no other tab to protect it from.
    return () => {};
  }
  return release;
}

/**
 * Deletes the cached files of every image under `base` but `keepBundle` that no
 * tab holds (holdImage). An image another tab still runs keeps its files; the
 * tab that next loads with nobody holding it deletes them. Without Web Locks
 * nothing can tell, and every other image goes: a download again in the other
 * tab costs less than leaking 20 MiB per deploy into storage the browser evicts
 * whole, the app's progress included.
 */
export async function forgetOtherImages(cache, base, keepBundle, locks = globalThis.navigator?.locks) {
  try {
    const images = new Map();
    for (const request of await cache.keys()) {
      const url = request.url;
      if (url.startsWith(keepBundle) || !url.startsWith(base)) continue;
      const bundle = url.slice(0, url.indexOf('/', base.length) + 1);
      if (!bundle) continue;
      if (!images.has(bundle)) images.set(bundle, []);
      images.get(bundle).push(request);
    }
    for (const [bundle, requests] of images) {
      const forget = async () => {
        for (const request of requests) await cache.delete(request);
      };
      if (typeof locks?.request !== 'function') await forget();
      else await locks.request(IMAGE_LOCK_PREFIX + bundle, { mode: 'exclusive', ifAvailable: true }, lock => lock && forget());
    }
  } catch {
    // Storage that refuses this is storage that will be refused again next time.
  }
}

// Pieces
//
// A file that downloads in HTTP Range pieces is kept the same way, one entry
// per piece, keyed by its URL with `?bytes=START-END` (END inclusive, as in a
// Range header). An entry without the query is the whole file. Every piece is
// under its bundle's URL, so it goes with its image.

export function pieceKey(url, start, end) {
  return `${url}?bytes=${start}-${end}`;
}

/**
 * The pieces of `url` in `cache`, sorted and apart: `{request, start, end}`.
 * A key that is not a piece of a file of `size` bytes, or that overlaps one
 * before it, is deleted.
 */
export async function listPieces(cache, url, size) {
  let requests;
  try {
    requests = await cache.keys(url, { ignoreSearch: true });
  } catch {
    return [];
  }
  const pieces = [];
  for (const request of requests) {
    const range = pieceRange(request.url, url, size);
    if (range) pieces.push({ request, ...range });
    else await cache.delete(request).catch(() => {});
  }
  pieces.sort((a, b) => a.start - b.start || b.end - a.end);
  const apart = [];
  for (const piece of pieces) {
    if (apart.length && piece.start <= apart.at(-1).end) await cache.delete(piece.request).catch(() => {});
    else apart.push(piece);
  }
  return apart;
}

function pieceRange(key, url, size) {
  if (key === url) return size > 0 ? { start: 0, end: size - 1 } : null;
  const found = /^\?bytes=(\d+)-(\d+)$/.exec(key.slice(url.length));
  if (!key.startsWith(url) || !found) return null;
  const start = Number(found[1]);
  const end = Number(found[2]);
  return start <= end && end < size ? { start, end } : null;
}

/** Deletes every piece of `url`, the whole-file entry included. */
export async function deletePieces(cache, url) {
  try {
    for (const request of await cache.keys(url, { ignoreSearch: true })) await cache.delete(request);
  } catch {
    // What stays is checked against the manifest before anything reads it.
  }
}

/**
 * The rootfs files programs fetched, kept in the Cache API so that a later run
 * or visit reads them without the network. They are named by their content and
 * never change, so a kept copy never goes stale, and they sit under their
 * image's URL, so they go with it.
 *
 * At most `budgetBytes` are kept; past that the least recently used go first.
 * That order is kept in an index entry beside them, written a second after the
 * last change. An entry the index does not name, because a tab closed before
 * its index write, counts as the least recently used.
 *
 * Every method swallows the Cache API's failures: a file it cannot give back is
 * fetched from the network, as it would have been without it.
 */
export class RootfsCache {

  #cache;
  #prefix;
  #indexUrl;
  #budget;
  #writable;
  /** URL to size in bytes, least recently used first. */
  #entries = null;
  #bytes = 0;
  #opening = null;
  #queue = Promise.resolve();
  #saveTimer = null;

  /**
   * @param {Cache} cache
   * @param {string} prefix The image's rootfs directory, as an absolute URL.
   * @param {{budgetBytes?: number, writable?: boolean}} [options] `writable`
   *     false reads what is kept and adds nothing, for a browser with no room.
   */
  constructor(cache, prefix, { budgetBytes = ROOTFS_CACHE_BYTES, writable = true } = {}) {
    this.#cache = cache;
    this.#prefix = prefix;
    this.#indexUrl = `${prefix}${ROOTFS_INDEX}`;
    this.#budget = budgetBytes;
    this.#writable = writable;
  }

  /** The bytes kept, once the index has been read. */
  get bytes() {
    return this.#bytes;
  }

  /** The kept copy of `url`, as served, or null. */
  async get(url) {
    const entries = await this.#open();
    if (!entries.has(url)) return null;
    let bytes = null;
    try {
      const response = await this.#cache.match(url);
      if (response) bytes = new Uint8Array(await response.arrayBuffer());
    } catch {
      bytes = null;
    }
    if (bytes?.byteLength !== entries.get(url)) {
      await this.delete(url);
      return null;
    }
    entries.delete(url);
    entries.set(url, bytes.byteLength);
    this.#scheduleSave();
    return bytes;
  }

  /** Keeps `bytes` as `url`. The caller MUST have checked them: whatever is
   *  kept is served to every later run as it is. */
  put(url, bytes) {
    if (!this.#writable || !url.startsWith(this.#prefix) || bytes.byteLength > this.#budget) return Promise.resolve();
    return this.#serially(async () => {
      const entries = await this.#open();
      if (entries.has(url) || !this.#writable) return;
      try {
        await this.#cache.put(url, new Response(bytes.slice()));
      } catch (error) {
        if (error?.name === 'QuotaExceededError') this.#writable = false;
        return;
      }
      entries.set(url, bytes.byteLength);
      this.#bytes += bytes.byteLength;
      await this.#evict();
      this.#scheduleSave();
    });
  }

  delete(url) {
    return this.#serially(async () => {
      const entries = await this.#open();
      if (entries.has(url)) {
        this.#bytes -= entries.get(url);
        entries.delete(url);
        this.#scheduleSave();
      }
      await this.#cache.delete(url).catch(() => {});
    });
  }

  /** Writes the index now rather than a second after the last change. */
  flush() {
    clearTimeout(this.#saveTimer);
    this.#saveTimer = null;
    return this.#serially(() => this.#save());
  }

  #open() {
    this.#opening ??= this.#read();
    return this.#opening;
  }

  async #read() {
    let index = [];
    try {
      const response = await this.#cache.match(this.#indexUrl);
      if (response) index = JSON.parse(await response.text())?.files ?? [];
    } catch {
      index = [];
    }
    let urls = [];
    try {
      urls = (await this.#cache.keys()).map(request => request.url)
        .filter(url => url.startsWith(this.#prefix) && url !== this.#indexUrl);
    } catch {
      urls = [];
    }
    const present = new Set(urls);
    const indexed = new Map();
    for (const entry of Array.isArray(index) ? index : []) {
      const [url, size] = Array.isArray(entry) ? entry : [];
      if (present.has(url) && Number.isSafeInteger(size) && size >= 0) indexed.set(url, size);
    }
    const entries = new Map();
    for (const url of urls) {
      if (indexed.has(url)) continue;
      try {
        const response = await this.#cache.match(url);
        entries.set(url, (await response.arrayBuffer()).byteLength);
      } catch {
        await this.#cache.delete(url).catch(() => {});
      }
    }
    for (const [url, size] of indexed) entries.set(url, size);
    this.#entries = entries;
    this.#bytes = 0;
    for (const size of entries.values()) this.#bytes += size;
    await this.#evict();
    return entries;
  }

  async #evict() {
    for (const [url, size] of this.#entries) {
      if (this.#bytes <= this.#budget) break;
      this.#entries.delete(url);
      this.#bytes -= size;
      await this.#cache.delete(url).catch(() => {});
    }
  }

  #scheduleSave() {
    if (this.#saveTimer !== null) return;
    this.#saveTimer = setTimeout(() => {
      this.#saveTimer = null;
      this.#serially(() => this.#save()).catch(() => {});
    }, INDEX_SAVE_DELAY_MS);
  }

  async #save() {
    if (!this.#entries) return;
    const body = JSON.stringify({ files: [...this.#entries] });
    await this.#cache.put(this.#indexUrl, new Response(body, { headers: { 'Content-Type': 'application/json' } })).catch(() => {});
  }

  #serially(operation) {
    const result = this.#queue.then(operation);
    this.#queue = result.catch(() => {});
    return result;
  }

}
