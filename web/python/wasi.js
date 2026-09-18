// A minimal WASI preview1 host, purpose-built for running CPython in the browser.
//
// CPython's wasm32-wasi build imports 42 functions from `wasi_snapshot_preview1`.
// This implements the ones it actually uses to start up, import its standard
// library, do console I/O and read and write files, and refuses the rest
// honestly with ENOTSUP rather than pretending.
//
// The filesystem is a tree of nodes held in memory, seeded with what the caller
// puts there — the standard library zip and the program being run — and
// writable from there on. There is no host filesystem behind it, no network,
// and no way to add one: a wasm module can only reach what its imports allow,
// so the sandbox is a property of this file being small rather than of any
// permission check. Nothing a program writes outlives the instance.
//
// Not a general WASI implementation. Do not reuse it as one.

const ERRNO_SUCCESS = 0;
const ERRNO_BADF = 8;
const ERRNO_EXIST = 20;
const ERRNO_INVAL = 28;
const ERRNO_ISDIR = 31;
const ERRNO_NOENT = 44;
const ERRNO_NOSPC = 51;
const ERRNO_NOTDIR = 54;
const ERRNO_NOTEMPTY = 55;
const ERRNO_NOTSUP = 58;
const ERRNO_PERM = 63;

const FILETYPE_UNKNOWN = 0;
const FILETYPE_DIRECTORY = 3;
const FILETYPE_REGULAR_FILE = 4;
const FILETYPE_CHARACTER_DEVICE = 2;

const PREOPENTYPE_DIR = 0;

// wasi-libc's isatty() answers yes only for a character device that is *not*
// seekable, so these two rights are what decide it. Withholding them is the
// only way to tell CPython it is talking to a terminal.
const RIGHTS_ALL = 0xFFFFFFFFFFFFFFFFn;
const RIGHTS_FD_SEEK = 1n << 2n;
const RIGHTS_FD_TELL = 1n << 5n;
const RIGHTS_TERMINAL = RIGHTS_ALL & ~(RIGHTS_FD_SEEK | RIGHTS_FD_TELL);

// There is no O_WRONLY in WASI. What a caller intends to do with an fd arrives
// only as this right in path_open's `fs_rights_base`, which is why refusing a
// write has to be decided from it.
const RIGHTS_FD_WRITE = 1n << 6n;

const OFLAGS_CREAT = 1 << 0;
const OFLAGS_DIRECTORY = 1 << 1;
const OFLAGS_EXCL = 1 << 2;
const OFLAGS_TRUNC = 1 << 3;
const FDFLAGS_APPEND = 1 << 0;

// fd_filestat_set_times' flags: set this time, or set it to now.
const FSTFLAGS_MTIM = 1 << 2;
const FSTFLAGS_MTIM_NOW = 1 << 3;

// poll_oneoff's two fixed-size records, and the one subscription flag that
// matters: whether a clock timeout is a point in time or a duration.
const SUBSCRIPTION_SIZE = 48;
const EVENT_SIZE = 32;
const EVENTTYPE_CLOCK = 0;
const SUBCLOCKFLAGS_ABSTIME = 1;

// A dirent header is fixed-size and the name follows it unpadded.
const DIRENT_SIZE = 24;

/** How many bytes a program may add to the filesystem before writes start
 *  failing with ENOSPC.
 *
 *  The interpreter's own heap is not the only thing that can take the tab down:
 *  `while True: f.write("x" * 1000)` grows this tree instead, and terminating
 *  the worker is the only way out of it. Measured against what was installed at
 *  startup, so the standard library zip does not eat into a program's share.
 *  Generous on purpose — a lesson writes kilobytes. */
const FS_QUOTA_BYTES = 16 * 1024 * 1024;

/** Wall-clock nanoseconds, to the microsecond.
 *
 *  Finer than `Date.now()` on purpose: CPython's import machinery caches a
 *  directory's listing and re-reads it only when that directory's mtime
 *  changes, so two changes a millisecond apart have to be two mtimes. */
function nowNanos() {
  return BigInt(Math.round((performance.timeOrigin + performance.now()) * 1000)) * 1000n;
}

/** Thrown by proc_exit to unwind out of `_start`, which never returns normally. */
export class WasiExit extends Error {
  constructor(code) {
    super(`exit ${code}`);
    this.code = code;
  }
}

/** One file or directory in the tree.
 *
 *  An open fd points at the node and never at its bytes: a Uint8Array cannot
 *  grow, so every write past the end reallocates, and an fd holding the old
 *  array would go on reading a buffer nobody else can see. */
class Node {
  constructor(fs, type) {
    this.fs = fs;
    this.type = type;
    this.ino = fs.nextIno++;
    this.mtime = nowNanos();
    // `buffer` is capacity and `size` is what is live; the two differ because
    // capacity doubles, which is what keeps a byte-at-a-time write linear.
    this.buffer = new Uint8Array(0);
    this.size = 0;
    this.children = type === FILETYPE_DIRECTORY ? new Map() : null;
    // Set on the standard library: a program that truncates the zip it is
    // importing from breaks every later import with an unrelated EOFError.
    this.readOnly = false;
    this.openCount = 0;
    this.unlinked = false;
  }

  get data() {
    return this.buffer.subarray(0, this.size);
  }

  /** Sets the live length, zero-filling growth. False when the quota refuses it. */
  resize(size) {
    if (size > this.size && !this.fs.claim(size - this.size)) return false;
    if (size < this.size) this.fs.release(this.size - size);
    if (size > this.buffer.length) {
      let capacity = Math.max(64, this.buffer.length);
      while (capacity < size) capacity *= 2;
      const grown = new Uint8Array(capacity);
      grown.set(this.buffer.subarray(0, this.size));
      this.buffer = grown;
    }
    // A seek past the end followed by a write leaves a hole, and a hole reads
    // as zeroes rather than as whatever the buffer was reallocated over.
    if (size > this.size) this.buffer.fill(0, this.size, size);
    this.size = size;
    this.mtime = nowNanos();
    return true;
  }

  /** False when the quota refuses it, in which case nothing is written. */
  writeAt(offset, chunk) {
    if (!this.resize(Math.max(this.size, offset + chunk.length))) return false;
    this.buffer.set(chunk, offset);
    this.mtime = nowNanos();
    return true;
  }

  /** Adds or replaces an entry, and dates the directory.
   *
   *  A directory's own mtime changing is what tells CPython's import machinery
   *  that the listing it cached for that directory is stale — without it, a
   *  module a program writes cannot be imported, because the finder for `/` was
   *  built while working out sys.path and goes on answering from then. */
  link(name, node) {
    this.children.set(name, node);
    this.mtime = nowNanos();
  }

  unlink(name) {
    this.children.delete(name);
    this.mtime = nowNanos();
  }

  setTimes(mtim, flags) {
    if (flags & FSTFLAGS_MTIM_NOW) this.mtime = nowNanos();
    else if (flags & FSTFLAGS_MTIM) this.mtime = mtim;
  }
}

/** One open file descriptor. */
class Fd {
  constructor(type, path, node, append, writable) {
    this.type = type;
    this.path = path;
    this.node = node ?? null; // null for the standard streams
    this.append = append === true;
    // path_open settles the access mode and is the only place that can: WASI
    // has no O_WRONLY, so it lives in the rights mask and is gone by the time a
    // write arrives. Without it here, os.open(p, O_RDONLY) writes through.
    this.writable = writable === true;
    this.offset = 0;
    this.entries = null; // the listing fd_readdir is paging through
  }

  get data() {
    return this.node ? this.node.data : null;
  }
}

export class Wasi {
  /**
   * @param {object} options
   * @param {string[]} options.args        argv, e.g. ["python", "/main.py"]
   * @param {object}   options.env         environment variables
   * @param {Map<string, Uint8Array>} options.files  absolute path -> contents
   *        What the filesystem starts out holding. The program may change all
   *        of it and add to it; nothing is written back.
   * @param {Iterable<string>} options.readOnlyPaths
   *        Of those files, the ones a program may not write to, truncate,
   *        rename or delete. The standard library zip belongs here: zipimport
   *        re-opens it on every import, so a program that empties it breaks in
   *        a way that names nothing useful.
   * @param {Uint8Array} options.stdin     pre-filled standard input
   * @param {{read: (max: number) => Uint8Array}} options.stdinReader
   *        Standard input as a stream instead of a buffer. Its `read` MAY block
   *        the whole thread — that is the point of it, and is what lets CPython
   *        sit at a REPL prompt — and MUST return an empty array for end of
   *        input. Wins over `stdin` when both are given.
   * @param {boolean} options.stdioIsTerminal
   *        Makes `isatty()` true for the three standard streams.
   *
   *        Off by default, and MUST stay off for anything whose output is shown
   *        as plain text: CPython colourises tracebacks when stderr is a
   *        terminal, and those escape codes are only an improvement in front of
   *        something that can render them.
   * @param {(kind: 'stdout'|'stderr', bytes: Uint8Array) => void} options.onOutput
   */
  constructor({ args, env, files, readOnlyPaths, stdin, stdinReader, stdioIsTerminal, onOutput }) {
    this.args = args;
    this.env = env;
    this.stdinReader = stdinReader ?? null;
    this.stdioIsTerminal = stdioIsTerminal === true;
    this.stdinBytes = stdin ?? new Uint8Array(0);
    this.stdinOffset = 0;
    this.stdinAtEof = false;
    this.onOutput = onOutput;
    this.memory = null;
    this.exitCode = null;

    this.nextIno = 1;
    this.usedBytes = 0;
    this.limit = Infinity; // what was installed is not charged to the program
    this.root = new Node(this, FILETYPE_DIRECTORY);
    const protectedPaths = new Set([...(readOnlyPaths ?? [])].map((path) => this.normalise(path)));
    const installed = new Set();
    for (const [path, bytes] of files ?? []) {
      const at = this.normalise(path);
      installed.add(at);
      this.install(path, bytes, protectedPaths.has(at));
    }
    // A typo here would hand the program a writable stdlib, and the first sign
    // of it is an import failing much later with an EOFError naming nothing the
    // caller did.
    for (const path of protectedPaths) {
      if (!installed.has(path)) throw new Error(`readOnlyPaths names ${path}, which is not among the files`);
    }
    this.limit = this.usedBytes + FS_QUOTA_BYTES;

    // tempfile probes /tmp, /var/tmp and /usr/tmp before falling back to the
    // working directory, and only the first is worth having: without it every
    // temporary file a program makes lands beside the program itself, where
    // the next os.listdir('/') in the same lesson finds it.
    this.makeDirectory('/tmp');

    // 0/1/2 are the standard streams; 3 is the single preopened directory that
    // everything else is resolved against.
    this.fds = new Map([
      [0, new Fd(FILETYPE_CHARACTER_DEVICE, '<stdin>', null)],
      [1, new Fd(FILETYPE_CHARACTER_DEVICE, '<stdout>', null)],
      [2, new Fd(FILETYPE_CHARACTER_DEVICE, '<stderr>', null)],
      [3, new Fd(FILETYPE_DIRECTORY, '/', this.root)],
    ]);
    this.nextFd = 4;
  }

  get view() {
    return new DataView(this.memory.buffer);
  }

  get bytes() {
    return new Uint8Array(this.memory.buffer);
  }

  readString(ptr, len) {
    return new TextDecoder().decode(this.bytes.subarray(ptr, ptr + len));
  }

  /** Collapses `.`/`..` so a path can never climb out of the virtual root. */
  normalise(path) {
    const absolute = path.startsWith('/') ? path : `/${path}`;
    const parts = [];
    for (const part of absolute.split('/')) {
      if (part === '' || part === '.') continue;
      if (part === '..') parts.pop();
      else parts.push(part);
    }
    return `/${parts.join('/')}`;
  }

  /** Puts a file in the tree, making the way to it as it goes.
   *
   *  A read-only file shares the caller's array rather than copying it: nothing
   *  can reach it to write to it, and the standard library is 13 MB that would
   *  otherwise be copied again for every run. A writable one is copied, because
   *  a write within its current length would otherwise reach the caller's array
   *  and the next instance started from it. */
  install(path, bytes, readOnly) {
    const parts = this.normalise(path).split('/').filter((part) => part !== '');
    const name = parts.pop();
    let directory = this.root;
    for (const part of parts) {
      let next = directory.children.get(part);
      if (!next) {
        next = new Node(this, FILETYPE_DIRECTORY);
        directory.link(part, next);
      }
      directory = next;
    }
    const node = new Node(this, FILETYPE_REGULAR_FILE);
    node.readOnly = readOnly === true;
    node.buffer = node.readOnly ? bytes : bytes.slice();
    node.size = bytes.length;
    this.claim(bytes.length);
    directory.link(name, node);
  }

  makeDirectory(path) {
    const spot = this.resolve(path);
    if (spot.error || spot.node) return;
    spot.parent.link(spot.name, new Node(this, FILETYPE_DIRECTORY));
  }

  /** Locates a path: the directory holding it, the name in it, and the node if
   *  there is one.
   *
   *  `error` is what the caller MUST return when it is non-zero — the two ways
   *  the walk can fail are different answers to `os.makedirs`, which builds a
   *  path one level at a time and reads ENOENT as "make the parent first". A
   *  missing *last* name is not a failure: `node` is then null, which is what
   *  O_CREAT needs to see. */
  resolve(path) {
    const parts = this.normalise(path).split('/').filter((part) => part !== '');
    if (parts.length === 0) return { error: ERRNO_SUCCESS, parent: null, name: '', node: this.root };

    const name = parts.pop();
    let directory = this.root;
    for (const part of parts) {
      const next = directory.children.get(part);
      if (next === undefined) return { error: ERRNO_NOENT };
      if (next.type !== FILETYPE_DIRECTORY) return { error: ERRNO_NOTDIR };
      directory = next;
    }
    return { error: ERRNO_SUCCESS, parent: directory, name, node: directory.children.get(name) ?? null };
  }

  /** A path as the caller meant it, relative to the directory `dirFd` names.
   *
   *  wasi-libc resolves preopens in userspace and always hands us fd 3 with a
   *  path relative to `/`, so this is the same as ignoring `dirFd` today. It is
   *  honoured anyway because `os.open(d)` plus `dir_fd=` reaches here too, and
   *  would otherwise silently resolve against the root. */
  pathAt(dirFd, pathPtr, pathLen) {
    const base = this.fds.get(dirFd);
    if (!base || base.type !== FILETYPE_DIRECTORY) return null;
    const path = this.readString(pathPtr, pathLen);
    return path.startsWith('/') ? path : `${base.path}/${path}`;
  }

  claim(count) {
    if (this.usedBytes + count > this.limit) return false;
    this.usedBytes += count;
    return true;
  }

  release(count) {
    this.usedBytes -= count;
  }

  /** Takes a name off a node and gives its bytes back — but only once nothing
   *  can reach it any more. A file that is unlinked while it is still open goes
   *  on holding what it holds, and goes on being written to: that is exactly
   *  what tempfile.TemporaryFile does. */
  drop(directory, name, node) {
    directory.unlink(name);
    node.unlinked = true;
    if (node.openCount === 0) this.release(node.size);
  }

  /** The import object handed to WebAssembly.instantiate. */
  imports() {
    const ok = () => ERRNO_SUCCESS;
    const unsupported = () => ERRNO_NOTSUP;

    return {
      wasi_snapshot_preview1: {
        // -------------------------------------------------------- process
        proc_exit: (code) => {
          this.exitCode = code;
          throw new WasiExit(code);
        },
        sched_yield: ok,

        args_sizes_get: (countPtr, bufSizePtr) => {
          const encoded = this.args.map((a) => new TextEncoder().encode(`${a}\0`));
          this.view.setUint32(countPtr, encoded.length, true);
          this.view.setUint32(bufSizePtr, encoded.reduce((n, a) => n + a.length, 0), true);
          return ERRNO_SUCCESS;
        },
        args_get: (argvPtr, bufPtr) => {
          let offset = bufPtr;
          this.args.forEach((arg, i) => {
            this.view.setUint32(argvPtr + i * 4, offset, true);
            const encoded = new TextEncoder().encode(`${arg}\0`);
            this.bytes.set(encoded, offset);
            offset += encoded.length;
          });
          return ERRNO_SUCCESS;
        },

        environ_sizes_get: (countPtr, bufSizePtr) => {
          const entries = Object.entries(this.env).map(([k, v]) =>
            new TextEncoder().encode(`${k}=${v}\0`));
          this.view.setUint32(countPtr, entries.length, true);
          this.view.setUint32(bufSizePtr, entries.reduce((n, e) => n + e.length, 0), true);
          return ERRNO_SUCCESS;
        },
        environ_get: (environPtr, bufPtr) => {
          let offset = bufPtr;
          Object.entries(this.env).forEach(([k, v], i) => {
            this.view.setUint32(environPtr + i * 4, offset, true);
            const encoded = new TextEncoder().encode(`${k}=${v}\0`);
            this.bytes.set(encoded, offset);
            offset += encoded.length;
          });
          return ERRNO_SUCCESS;
        },

        // ---------------------------------------------------------- clocks
        clock_res_get: (_id, resPtr) => {
          this.view.setBigUint64(resPtr, 1000000n, true); // 1ms
          return ERRNO_SUCCESS;
        },
        clock_time_get: (_id, _precision, timePtr) => {
          this.view.setBigUint64(timePtr, nowNanos(), true);
          return ERRNO_SUCCESS;
        },
        random_get: (ptr, len) => {
          crypto.getRandomValues(this.bytes.subarray(ptr, ptr + len));
          return ERRNO_SUCCESS;
        },

        // ------------------------------------------------------------- I/O
        fd_write: (fd, iovsPtr, iovsLen, writtenPtr) => {
          const entry = this.fds.get(fd);
          if (!entry) return ERRNO_BADF;
          const toStream = fd === 1 || fd === 2;
          if (!toStream) {
            if (entry.type === FILETYPE_DIRECTORY) return ERRNO_ISDIR;
            if (!entry.node) return ERRNO_BADF;
            if (!entry.writable) return ERRNO_BADF;
            if (entry.node.readOnly) return ERRNO_PERM;
          }

          let written = 0;
          const chunks = [];
          for (let i = 0; i < iovsLen; i++) {
            const ptr = this.view.getUint32(iovsPtr + i * 8, true);
            const len = this.view.getUint32(iovsPtr + i * 8 + 4, true);
            chunks.push(this.bytes.slice(ptr, ptr + len));
            written += len;
          }
          const merged = new Uint8Array(written);
          let offset = 0;
          for (const chunk of chunks) {
            merged.set(chunk, offset);
            offset += chunk.length;
          }

          if (toStream) {
            this.onOutput(fd === 1 ? 'stdout' : 'stderr', merged);
          } else {
            // Append means "at the end as it is now", which is not where this
            // fd last left off once anything else has written to the file.
            const at = entry.append ? entry.node.size : entry.offset;
            // Writing nothing changes nothing, seek past the end or not. Going
            // on would grow the file to `at` and zero-fill the gap, where POSIX
            // makes an empty write a no-op.
            if (merged.length === 0) {
              this.view.setUint32(writtenPtr, 0, true);
              return ERRNO_SUCCESS;
            }
            // Refused whole rather than short: a partial write sends CPython's
            // buffered writer round again for the rest, and it would keep
            // coming back for a remainder that never fits.
            if (!entry.node.writeAt(at, merged)) return ERRNO_NOSPC;
            entry.offset = at + merged.length;
          }
          this.view.setUint32(writtenPtr, written, true);
          return ERRNO_SUCCESS;
        },

        fd_read: (fd, iovsPtr, iovsLen, readPtr) => {
          let read = 0;
          for (let i = 0; i < iovsLen; i++) {
            const ptr = this.view.getUint32(iovsPtr + i * 8, true);
            const len = this.view.getUint32(iovsPtr + i * 8 + 4, true);
            if (len === 0) continue;
            if (!this.hasInput(fd)) break;

            const got = this.readInto(fd, ptr, len);
            read += got;

            // A short read is a complete read — `read(2)` has always been
            // allowed to return less than asked. Stopping here is what keeps a
            // *blocking* stdin from parking a second time on the next iovec
            // after it has already produced the line CPython was waiting for.
            if (got < len) break;
          }
          this.view.setUint32(readPtr, read, true);
          return ERRNO_SUCCESS;
        },

        fd_pread: (fd, iovsPtr, iovsLen, offset, readPtr) => {
          const entry = this.fds.get(fd);
          if (!entry || !entry.node) return ERRNO_BADF;
          let read = 0;
          let at = Number(offset);
          for (let i = 0; i < iovsLen; i++) {
            const ptr = this.view.getUint32(iovsPtr + i * 8, true);
            const len = this.view.getUint32(iovsPtr + i * 8 + 4, true);
            const slice = entry.data.subarray(at, at + len);
            this.bytes.set(slice, ptr);
            read += slice.length;
            at += slice.length;
          }
          this.view.setUint32(readPtr, read, true);
          return ERRNO_SUCCESS;
        },

        fd_pwrite: (fd, iovsPtr, iovsLen, offset, writtenPtr) => {
          const entry = this.fds.get(fd);
          if (!entry || !entry.node) return ERRNO_BADF;
          if (entry.node.readOnly) return ERRNO_PERM;
          let at = Number(offset);
          let written = 0;
          for (let i = 0; i < iovsLen; i++) {
            const ptr = this.view.getUint32(iovsPtr + i * 8, true);
            const len = this.view.getUint32(iovsPtr + i * 8 + 4, true);
            if (!entry.node.writeAt(at, this.bytes.slice(ptr, ptr + len))) return ERRNO_NOSPC;
            at += len;
            written += len;
          }
          this.view.setUint32(writtenPtr, written, true);
          return ERRNO_SUCCESS;
        },

        fd_seek: (fd, offset, whence, newOffsetPtr) => {
          const entry = this.fds.get(fd);
          if (!entry) return ERRNO_BADF;
          if (!entry.node || entry.type !== FILETYPE_REGULAR_FILE) return ERRNO_INVAL;
          const delta = Number(offset);
          if (whence === 0) entry.offset = delta;
          else if (whence === 1) entry.offset += delta;
          else if (whence === 2) entry.offset = entry.node.size + delta;
          else return ERRNO_INVAL;
          // Only the floor is a clamp. Seeking past the end is legal and is how
          // a sparse write asks for a hole; capping at the size would land the
          // write somewhere else entirely and report success.
          entry.offset = Math.max(0, entry.offset);
          this.view.setBigUint64(newOffsetPtr, BigInt(entry.offset), true);
          return ERRNO_SUCCESS;
        },
        fd_tell: (fd, offsetPtr) => {
          const entry = this.fds.get(fd);
          if (!entry) return ERRNO_BADF;
          this.view.setBigUint64(offsetPtr, BigInt(entry.offset), true);
          return ERRNO_SUCCESS;
        },
        fd_close: (fd) => {
          if (fd <= 3) return ERRNO_SUCCESS;
          const entry = this.fds.get(fd);
          if (entry && entry.node) {
            entry.node.openCount--;
            if (entry.node.unlinked && entry.node.openCount === 0) this.release(entry.node.size);
          }
          this.fds.delete(fd);
          return ERRNO_SUCCESS;
        },

        fd_fdstat_get: (fd, statPtr) => {
          const entry = this.fds.get(fd);
          if (!entry) return ERRNO_BADF;

          // Grant every right. wasi-libc asks fd 3 for its rights before every
          // path_open and intersects what the open wants with what came back,
          // so anything narrower here starts refusing ordinary opens with
          // ENOTCAPABLE. What a caller may actually do is decided at the node.
          // The one exception is the pair that makes a stream seekable, which
          // is how isatty() tells a terminal from a redirected file.
          const rights = this.stdioIsTerminal && fd <= 2 ? RIGHTS_TERMINAL : RIGHTS_ALL;

          this.view.setUint8(statPtr, entry.type);
          this.view.setUint16(statPtr + 2, entry.append ? FDFLAGS_APPEND : 0, true);
          this.view.setBigUint64(statPtr + 8, rights, true);
          this.view.setBigUint64(statPtr + 16, rights, true);
          return ERRNO_SUCCESS;
        },
        fd_fdstat_set_flags: (fd, flags) => {
          const entry = this.fds.get(fd);
          if (!entry) return ERRNO_BADF;
          entry.append = (flags & FDFLAGS_APPEND) !== 0;
          return ERRNO_SUCCESS;
        },

        fd_filestat_get: (fd, statPtr) => {
          const entry = this.fds.get(fd);
          if (!entry) return ERRNO_BADF;
          return this.writeFilestat(statPtr, entry.type, entry.node);
        },
        fd_filestat_set_size: (fd, size) => {
          const entry = this.fds.get(fd);
          if (!entry || !entry.node) return ERRNO_BADF;
          if (entry.type === FILETYPE_DIRECTORY) return ERRNO_ISDIR;
          if (!entry.writable) return ERRNO_BADF;
          if (entry.node.readOnly) return ERRNO_PERM;
          return entry.node.resize(Number(size)) ? ERRNO_SUCCESS : ERRNO_NOSPC;
        },
        fd_filestat_set_times: (fd, _atim, mtim, flags) => {
          const entry = this.fds.get(fd);
          if (!entry || !entry.node) return ERRNO_BADF;
          if (entry.node.readOnly) return ERRNO_PERM;
          entry.node.setTimes(mtim, flags);
          return ERRNO_SUCCESS;
        },

        fd_prestat_get: (fd, prestatPtr) => {
          if (fd !== 3) return ERRNO_BADF;
          this.view.setUint8(prestatPtr, PREOPENTYPE_DIR);
          this.view.setUint32(prestatPtr + 4, 1, true); // strlen("/")
          return ERRNO_SUCCESS;
        },
        fd_prestat_dir_name: (fd, pathPtr, pathLen) => {
          if (fd !== 3) return ERRNO_BADF;
          this.bytes.set(new TextEncoder().encode('/'.slice(0, pathLen)), pathPtr);
          return ERRNO_SUCCESS;
        },

        fd_readdir: (fd, bufPtr, bufLen, cookie, sizePtr) => {
          const entry = this.fds.get(fd);
          if (!entry) return ERRNO_BADF;
          if (entry.type !== FILETYPE_DIRECTORY || !entry.node) return ERRNO_NOTDIR;

          const start = Number(cookie);
          // The listing is taken once and paged from, because a cookie is an
          // index into it and the directory may be written to in between.
          if (start === 0 || !entry.entries) entry.entries = [...entry.node.children];

          // `.` and `..` are left out. CPython filters both, and nothing else
          // here can follow a `..` anyway.
          let written = 0;
          for (let i = start; i < entry.entries.length && written < bufLen; i++) {
            const [name, node] = entry.entries[i];
            const nameBytes = new TextEncoder().encode(name);
            const record = new Uint8Array(DIRENT_SIZE + nameBytes.length);
            const header = new DataView(record.buffer);
            header.setBigUint64(0, BigInt(i + 1), true); // d_next: the entry after this one
            header.setBigUint64(8, BigInt(node.ino), true);
            header.setUint32(16, nameBytes.length, true);
            header.setUint8(20, node.type);
            record.set(nameBytes, DIRENT_SIZE);

            // A record cut off mid-way is how the caller is told to come back
            // for more: it drops the partial entry and re-reads from the last
            // whole one's cookie. Stopping short of `bufLen` instead is read as
            // the end of the directory, which truncates a listing silently.
            const take = Math.min(record.length, bufLen - written);
            this.bytes.set(record.subarray(0, take), bufPtr + written);
            written += take;
          }
          this.view.setUint32(sizePtr, written, true);
          return ERRNO_SUCCESS;
        },

        path_open: (dirFd, _dirFlags, pathPtr, pathLen, oflags, rightsBase, _inheriting, fdFlags, fdPtr) => {
          const path = this.pathAt(dirFd, pathPtr, pathLen);
          if (path === null) return ERRNO_BADF;
          const spot = this.resolve(path);
          if (spot.error) return spot.error;

          const forWriting = (rightsBase & RIGHTS_FD_WRITE) !== 0n || (oflags & OFLAGS_TRUNC) !== 0;
          let node = spot.node;

          // Every refusal is settled before anything is created, so a failed
          // open cannot leave an empty file where the caller was told there is
          // none. Nothing stats a path first — CPython goes straight to
          // path_open and expects the errno to come from here — so this is the
          // only place any of these can be said.
          if (!node) {
            if (!(oflags & OFLAGS_CREAT)) return ERRNO_NOENT;
            if (oflags & OFLAGS_DIRECTORY) return ERRNO_NOTDIR;
            node = new Node(this, FILETYPE_REGULAR_FILE);
            spot.parent.link(spot.name, node);
          } else {
            if ((oflags & OFLAGS_CREAT) && (oflags & OFLAGS_EXCL)) return ERRNO_EXIST;
            if (node.type === FILETYPE_DIRECTORY && forWriting) return ERRNO_ISDIR;
            if (node.type !== FILETYPE_DIRECTORY && (oflags & OFLAGS_DIRECTORY)) return ERRNO_NOTDIR;
            if (node.readOnly && forWriting) return ERRNO_PERM;
            if (oflags & OFLAGS_TRUNC) node.resize(0);
          }

          const fd = this.nextFd++;
          node.openCount++;
          this.fds.set(
            fd,
            new Fd(node.type, this.normalise(path), node, (fdFlags & FDFLAGS_APPEND) !== 0, forWriting),
          );
          this.view.setUint32(fdPtr, fd, true);
          return ERRNO_SUCCESS;
        },

        // `time.sleep()` is the whole reason this is implemented rather than
        // refused. wasi-libc builds `nanosleep` on top of poll_oneoff with a
        // single clock subscription, so returning ENOTSUP here turns every
        // sleeping program into `OSError: [Errno 58] Not supported`.
        poll_oneoff: (subsPtr, eventsPtr, count, neventsPtr) => {
          if (count <= 0) return ERRNO_INVAL;

          const events = [];
          let earliest = null;
          let readyNow = false;

          for (let i = 0; i < count; i++) {
            const base = subsPtr + i * SUBSCRIPTION_SIZE;
            const userdata = this.view.getBigUint64(base, true);
            const kind = this.view.getUint8(base + 8);

            if (kind === EVENTTYPE_CLOCK) {
              const timeout = this.view.getBigUint64(base + 24, true);
              const flags = this.view.getUint16(base + 40, true);
              const ms = Number(timeout / 1000000n);
              const deadline = flags & SUBCLOCKFLAGS_ABSTIME ? ms : Date.now() + ms;
              earliest = earliest === null ? deadline : Math.min(earliest, deadline);
            } else {
              // Reported ready immediately. stdout cannot fill up, and stdin
              // is either a fixed buffer or a reader whose own read blocks —
              // so nothing is gained by claiming it is not ready yet, and
              // CPython's interactive loop reaches stdin through fd_read
              // rather than through a poll anyway.
              readyNow = true;
            }
            events.push({ userdata, kind });
          }

          // A poll returns as soon as *any* subscription is ready, and only
          // the ready ones are reported — saying a clock fired when an fd was
          // ready would make every `select` with a timeout claim it timed out.
          const reported = readyNow
            ? events.filter((event) => event.kind !== EVENTTYPE_CLOCK)
            : events.filter((event) => event.kind === EVENTTYPE_CLOCK);

          if (!readyNow && earliest !== null) {
            // A spin, because there is no synchronous sleep in a worker
            // without SharedArrayBuffer. It burns a worker thread that has
            // nothing else to do, and Stop still works because that terminates
            // the worker outright.
            //
            // The reason it is a spin no longer holds. SharedArrayBuffer needs
            // the app served cross-origin isolated, which used to break the
            // cross-origin font loads — but the fonts are bundled now, and
            // every configuration in .vscode/launch.json serves the COOP/COEP
            // headers (verified: crossOriginIsolated === true, shared
            // WebAssembly.Memory and Atomics.wait both available). Replacing
            // this with an Atomics.wait is a real option. It is not done yet
            // because a deployed build is only isolated if its host sets those
            // headers, so this spin has to stay as the fallback either way.
            while (Date.now() < earliest) { /* wait */ }
          }

          reported.forEach((event, i) => {
            const at = eventsPtr + i * EVENT_SIZE;
            this.view.setBigUint64(at, event.userdata, true);
            this.view.setUint16(at + 8, ERRNO_SUCCESS, true);
            this.view.setUint8(at + 10, event.kind);
            this.view.setBigUint64(at + 16, 0n, true); // nbytes
            this.view.setUint16(at + 24, 0, true); // flags
          });
          this.view.setUint32(neventsPtr, reported.length, true);
          return ERRNO_SUCCESS;
        },

        // ------------------------------------------------------ the tree
        path_filestat_get: (dirFd, _flags, pathPtr, pathLen, statPtr) => {
          const path = this.pathAt(dirFd, pathPtr, pathLen);
          if (path === null) return ERRNO_BADF;
          const spot = this.resolve(path);
          if (spot.error) return spot.error;
          if (!spot.node) return ERRNO_NOENT;
          return this.writeFilestat(statPtr, spot.node.type, spot.node);
        },
        path_filestat_set_times: (dirFd, _flags, pathPtr, pathLen, _atim, mtim, flags) => {
          const path = this.pathAt(dirFd, pathPtr, pathLen);
          if (path === null) return ERRNO_BADF;
          const spot = this.resolve(path);
          if (spot.error) return spot.error;
          if (!spot.node) return ERRNO_NOENT;
          if (spot.node.readOnly) return ERRNO_PERM;
          spot.node.setTimes(mtim, flags);
          return ERRNO_SUCCESS;
        },

        path_create_directory: (dirFd, pathPtr, pathLen) => {
          const path = this.pathAt(dirFd, pathPtr, pathLen);
          if (path === null) return ERRNO_BADF;
          const spot = this.resolve(path);
          if (spot.error) return spot.error;
          if (spot.node || !spot.parent) return ERRNO_EXIST;
          spot.parent.link(spot.name, new Node(this, FILETYPE_DIRECTORY));
          return ERRNO_SUCCESS;
        },

        path_unlink_file: (dirFd, pathPtr, pathLen) => {
          const path = this.pathAt(dirFd, pathPtr, pathLen);
          if (path === null) return ERRNO_BADF;
          const spot = this.resolve(path);
          if (spot.error) return spot.error;
          if (!spot.node) return ERRNO_NOENT;
          if (spot.node.type === FILETYPE_DIRECTORY) return ERRNO_ISDIR;
          if (spot.node.readOnly) return ERRNO_PERM;
          this.drop(spot.parent, spot.name, spot.node);
          return ERRNO_SUCCESS;
        },

        path_remove_directory: (dirFd, pathPtr, pathLen) => {
          const path = this.pathAt(dirFd, pathPtr, pathLen);
          if (path === null) return ERRNO_BADF;
          const spot = this.resolve(path);
          if (spot.error) return spot.error;
          if (!spot.node) return ERRNO_NOENT;
          if (spot.node.type !== FILETYPE_DIRECTORY) return ERRNO_NOTDIR;
          if (!spot.parent) return ERRNO_PERM;
          if (spot.node.children.size > 0) return ERRNO_NOTEMPTY;
          this.drop(spot.parent, spot.name, spot.node);
          return ERRNO_SUCCESS;
        },

        path_rename: (oldFd, oldPtr, oldLen, newFd, newPtr, newLen) => {
          const oldPath = this.pathAt(oldFd, oldPtr, oldLen);
          const newPath = this.pathAt(newFd, newPtr, newLen);
          if (oldPath === null || newPath === null) return ERRNO_BADF;
          const from = this.resolve(oldPath);
          const to = this.resolve(newPath);
          if (from.error) return from.error;
          if (to.error) return to.error;
          if (!from.node || !from.parent) return ERRNO_NOENT;
          if (!to.parent) return ERRNO_EXIST;
          if (from.node.readOnly) return ERRNO_PERM;
          // POSIX makes renaming a path onto itself a successful no-op. Falling
          // through would drop the node and re-link it, crediting its bytes back
          // to the quota while they are still held — enough repetitions and the
          // cap stops bounding anything.
          if (to.node === from.node) return ERRNO_SUCCESS;

          const movingDirectory = from.node.type === FILETYPE_DIRECTORY;
          // A directory moved inside itself makes a cycle, which nothing below
          // would notice and os.walk would follow forever.
          if (movingDirectory && this.normalise(newPath).startsWith(`${this.normalise(oldPath)}/`)) {
            return ERRNO_INVAL;
          }
          if (to.node) {
            if (to.node.type === FILETYPE_DIRECTORY && !movingDirectory) return ERRNO_ISDIR;
            if (to.node.type !== FILETYPE_DIRECTORY && movingDirectory) return ERRNO_NOTDIR;
            if (to.node.type === FILETYPE_DIRECTORY && to.node.children.size > 0) return ERRNO_NOTEMPTY;
            if (to.node.readOnly) return ERRNO_PERM;
            this.drop(to.parent, to.name, to.node);
          }
          from.parent.unlink(from.name);
          to.parent.link(to.name, from.node);
          return ERRNO_SUCCESS;
        },

        // ---------------------------------- nothing to do, then refused
        //
        // Advice and syncing have nothing to act on: this filesystem has no
        // slower half behind it to flush to. The rest are things the tree
        // genuinely does not have — links of either kind, and a network — and
        // saying so is more use than a stub that appears to work.
        fd_advise: ok,
        fd_datasync: ok,
        fd_sync: ok,
        path_link: () => ERRNO_PERM,
        // Keeping the tree symlink-free is what lets normalise() alone
        // guarantee that no path can climb out of the virtual root.
        path_symlink: () => ERRNO_PERM,
        path_readlink: () => ERRNO_INVAL,
        sock_accept: unsupported,
        sock_recv: unsupported,
        sock_send: unsupported,
        sock_shutdown: unsupported,
      },
    };
  }

  hasInput(fd) {
    if (fd !== 0) return true;
    // A reader always "has" input: asking it is what blocks, and it reports the
    // end of the stream by handing back nothing.
    if (this.stdinReader) return !this.stdinAtEof;
    return this.stdinOffset < this.stdinBytes.length;
  }

  readInto(fd, ptr, len) {
    if (fd === 0 && this.stdinReader) {
      const chunk = this.stdinReader.read(len);
      if (chunk.length === 0) {
        this.stdinAtEof = true;
        return 0;
      }
      this.bytes.set(chunk, ptr);
      return chunk.length;
    }
    if (fd === 0) {
      const slice = this.stdinBytes.subarray(this.stdinOffset, this.stdinOffset + len);
      this.bytes.set(slice, ptr);
      this.stdinOffset += slice.length;
      return slice.length;
    }
    const entry = this.fds.get(fd);
    if (!entry || !entry.data) return 0;
    const slice = entry.data.subarray(entry.offset, entry.offset + len);
    this.bytes.set(slice, ptr);
    entry.offset += slice.length;
    return slice.length;
  }

  /** One 64-byte filestat. All three timestamps report the modification time;
   *  access time is not tracked, and reading a file is not worth a write. */
  writeFilestat(ptr, filetype, node) {
    const time = node ? node.mtime : 0n;
    this.view.setBigUint64(ptr, 0n, true); // dev
    this.view.setBigUint64(ptr + 8, node ? BigInt(node.ino) : 0n, true);
    this.view.setUint8(ptr + 16, filetype);
    this.view.setBigUint64(ptr + 24, 1n, true); // nlink
    this.view.setBigUint64(ptr + 32, BigInt(node ? node.size : 0), true);
    this.view.setBigUint64(ptr + 40, time, true); // atim
    this.view.setBigUint64(ptr + 48, time, true); // mtim
    this.view.setBigUint64(ptr + 56, time, true); // ctim
    return ERRNO_SUCCESS;
  }
}
