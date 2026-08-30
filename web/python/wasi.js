// A minimal WASI preview1 host, purpose-built for running CPython in the browser.
//
// CPython's wasm32-wasi build imports 42 functions from `wasi_snapshot_preview1`.
// This implements the ones it actually uses to start up, import its standard
// library and do console I/O, and refuses the rest honestly with ENOTSUP rather
// than pretending.
//
// The filesystem is a read-only map held in memory, containing exactly what the
// caller puts there — the standard library zip and the program being run. There
// is no host filesystem behind it, no network, and no way to add one: a wasm
// module can only reach what its imports allow, so the sandbox is a property of
// this file being small rather than of any permission check.
//
// Not a general WASI implementation. Do not reuse it as one.

const ERRNO_SUCCESS = 0;
const ERRNO_BADF = 8;
const ERRNO_EXIST = 20;
const ERRNO_INVAL = 28;
const ERRNO_ISDIR = 31;
const ERRNO_NOENT = 44;
const ERRNO_NOTDIR = 54;
const ERRNO_NOTSUP = 58;
const ERRNO_PERM = 63;
const ERRNO_ROFS = 69;

const FILETYPE_UNKNOWN = 0;
const FILETYPE_DIRECTORY = 3;
const FILETYPE_REGULAR_FILE = 4;
const FILETYPE_CHARACTER_DEVICE = 2;

const PREOPENTYPE_DIR = 0;

// poll_oneoff's two fixed-size records, and the one subscription flag that
// matters: whether a clock timeout is a point in time or a duration.
const SUBSCRIPTION_SIZE = 48;
const EVENT_SIZE = 32;
const EVENTTYPE_CLOCK = 0;
const SUBCLOCKFLAGS_ABSTIME = 1;

/** Thrown by proc_exit to unwind out of `_start`, which never returns normally. */
export class WasiExit extends Error {
  constructor(code) {
    super(`exit ${code}`);
    this.code = code;
  }
}

/** One open file descriptor. */
class Fd {
  constructor(type, path, data) {
    this.type = type;
    this.path = path;
    this.data = data; // Uint8Array for files, null for dirs/streams
    this.offset = 0;
  }
}

export class Wasi {
  /**
   * @param {object} options
   * @param {string[]} options.args        argv, e.g. ["python", "/main.py"]
   * @param {object}   options.env         environment variables
   * @param {Map<string, Uint8Array>} options.files  absolute path -> contents
   * @param {Uint8Array} options.stdin     pre-filled standard input
   * @param {(kind: 'stdout'|'stderr', bytes: Uint8Array) => void} options.onOutput
   */
  constructor({ args, env, files, stdin, onOutput }) {
    this.args = args;
    this.env = env;
    this.files = files;
    this.stdinBytes = stdin ?? new Uint8Array(0);
    this.stdinOffset = 0;
    this.onOutput = onOutput;
    this.memory = null;
    this.exitCode = null;

    // 0/1/2 are the standard streams; 3 is the single preopened directory that
    // everything else is resolved against.
    this.fds = new Map([
      [0, new Fd(FILETYPE_CHARACTER_DEVICE, '<stdin>', null)],
      [1, new Fd(FILETYPE_CHARACTER_DEVICE, '<stdout>', null)],
      [2, new Fd(FILETYPE_CHARACTER_DEVICE, '<stderr>', null)],
      [3, new Fd(FILETYPE_DIRECTORY, '/', null)],
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

  isDirectory(path) {
    const prefix = path === '/' ? '/' : `${path}/`;
    for (const key of this.files.keys()) {
      if (key.startsWith(prefix)) return true;
    }
    return path === '/';
  }

  /** The import object handed to WebAssembly.instantiate. */
  imports() {
    const ok = () => ERRNO_SUCCESS;
    const unsupported = () => ERRNO_NOTSUP;
    const readOnly = () => ERRNO_ROFS;

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
          this.view.setBigUint64(timePtr, BigInt(Date.now()) * 1000000n, true);
          return ERRNO_SUCCESS;
        },
        random_get: (ptr, len) => {
          crypto.getRandomValues(this.bytes.subarray(ptr, ptr + len));
          return ERRNO_SUCCESS;
        },

        // ------------------------------------------------------------- I/O
        fd_write: (fd, iovsPtr, iovsLen, writtenPtr) => {
          if (fd !== 1 && fd !== 2) return ERRNO_BADF;
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
          this.onOutput(fd === 1 ? 'stdout' : 'stderr', merged);
          this.view.setUint32(writtenPtr, written, true);
          return ERRNO_SUCCESS;
        },

        fd_read: (fd, iovsPtr, iovsLen, readPtr) => {
          let read = 0;
          for (let i = 0; i < iovsLen && this.hasInput(fd); i++) {
            const ptr = this.view.getUint32(iovsPtr + i * 8, true);
            const len = this.view.getUint32(iovsPtr + i * 8 + 4, true);
            read += this.readInto(fd, ptr, len);
          }
          this.view.setUint32(readPtr, read, true);
          return ERRNO_SUCCESS;
        },

        fd_pread: (fd, iovsPtr, iovsLen, offset, readPtr) => {
          const entry = this.fds.get(fd);
          if (!entry || !entry.data) return ERRNO_BADF;
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

        fd_seek: (fd, offset, whence, newOffsetPtr) => {
          const entry = this.fds.get(fd);
          if (!entry) return ERRNO_BADF;
          if (!entry.data) return ERRNO_INVAL;
          const size = entry.data.length;
          const delta = Number(offset);
          if (whence === 0) entry.offset = delta;
          else if (whence === 1) entry.offset += delta;
          else if (whence === 2) entry.offset = size + delta;
          else return ERRNO_INVAL;
          entry.offset = Math.max(0, Math.min(entry.offset, size));
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
          if (fd > 3) this.fds.delete(fd);
          return ERRNO_SUCCESS;
        },

        fd_fdstat_get: (fd, statPtr) => {
          const entry = this.fds.get(fd);
          if (!entry) return ERRNO_BADF;
          this.view.setUint8(statPtr, entry.type);
          this.view.setUint16(statPtr + 2, 0, true); // flags
          // Grant every right; the filesystem is read-only by construction, so
          // there is nothing a generous rights mask can actually reach.
          this.view.setBigUint64(statPtr + 8, 0xFFFFFFFFFFFFFFFFn, true);
          this.view.setBigUint64(statPtr + 16, 0xFFFFFFFFFFFFFFFFn, true);
          return ERRNO_SUCCESS;
        },
        fd_fdstat_set_flags: ok,

        fd_filestat_get: (fd, statPtr) => {
          const entry = this.fds.get(fd);
          if (!entry) return ERRNO_BADF;
          return this.writeFilestat(statPtr, entry.type, entry.data ? entry.data.length : 0);
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

        fd_readdir: (_fd, _bufPtr, _bufLen, _cookie, sizePtr) => {
          // CPython probes directories while working out sys.path; reporting an
          // empty listing is honest and enough, because imports resolve through
          // the stdlib zip rather than by scanning.
          this.view.setUint32(sizePtr, 0, true);
          return ERRNO_SUCCESS;
        },

        path_open: (_dirFd, _dirFlags, pathPtr, pathLen, oflags, _base, _inheriting, _fdFlags, fdPtr) => {
          const path = this.normalise(this.readString(pathPtr, pathLen));
          // O_CREAT — nothing here is writable.
          if (oflags & 1) return ERRNO_ROFS;

          const data = this.files.get(path);
          if (data === undefined) {
            if (this.isDirectory(path)) {
              const fd = this.nextFd++;
              this.fds.set(fd, new Fd(FILETYPE_DIRECTORY, path, null));
              this.view.setUint32(fdPtr, fd, true);
              return ERRNO_SUCCESS;
            }
            return ERRNO_NOENT;
          }
          const fd = this.nextFd++;
          this.fds.set(fd, new Fd(FILETYPE_REGULAR_FILE, path, data));
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
              // Our streams never block: stdin is a fixed buffer and stdout
              // cannot fill up, so an fd subscription is ready immediately.
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

        path_filestat_get: (_dirFd, _flags, pathPtr, pathLen, statPtr) => {
          const path = this.normalise(this.readString(pathPtr, pathLen));
          const data = this.files.get(path);
          if (data !== undefined) {
            return this.writeFilestat(statPtr, FILETYPE_REGULAR_FILE, data.length);
          }
          if (this.isDirectory(path)) {
            return this.writeFilestat(statPtr, FILETYPE_DIRECTORY, 0);
          }
          return ERRNO_NOENT;
        },

        // ------------------------------------------- refused, not pretended
        //
        // A read-only virtual filesystem with no network. CPython probes for
        // these while starting up and copes fine with being told no.
        fd_advise: ok,
        fd_datasync: ok,
        fd_sync: ok,
        fd_filestat_set_size: readOnly,
        fd_filestat_set_times: readOnly,
        fd_pwrite: readOnly,
        path_create_directory: readOnly,
        path_filestat_set_times: readOnly,
        path_link: readOnly,
        path_readlink: () => ERRNO_INVAL,
        path_remove_directory: readOnly,
        path_rename: readOnly,
        path_symlink: readOnly,
        path_unlink_file: readOnly,
        sock_accept: unsupported,
        sock_recv: unsupported,
        sock_send: unsupported,
        sock_shutdown: unsupported,
      },
    };
  }

  hasInput(fd) {
    return fd === 0 ? this.stdinOffset < this.stdinBytes.length : true;
  }

  readInto(fd, ptr, len) {
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

  writeFilestat(ptr, filetype, size) {
    this.view.setBigUint64(ptr, 0n, true); // dev
    this.view.setBigUint64(ptr + 8, 0n, true); // ino
    this.view.setUint8(ptr + 16, filetype);
    this.view.setBigUint64(ptr + 24, 1n, true); // nlink
    this.view.setBigUint64(ptr + 32, BigInt(size), true);
    this.view.setBigUint64(ptr + 40, 0n, true); // atim
    this.view.setBigUint64(ptr + 48, 0n, true); // mtim
    this.view.setBigUint64(ptr + 56, 0n, true); // ctim
    return ERRNO_SUCCESS;
  }
}
