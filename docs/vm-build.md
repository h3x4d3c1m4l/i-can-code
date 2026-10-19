# The Tkinter VM

The Tkinter playground runs a student's program in a real Linux with a real X
server, emulated in the browser by [v86](https://github.com/copy/v86). This
document covers everything below the Dart side: the guest image and the agent in
it, the protocol between them and the page, the JS host that runs programs and
stops them, how all of it is built, and the corpus of student programs that holds
it to what a student should see.

The guest is Alpine 3.24 for i386, Python 3.14 with Tk 8.6, and Xorg on fbdev. It
has no window manager and an 800 × 600 screen; the app draws each window's frame
itself. The kernel is Alpine's `linux-virt` version, but not its binary: the build
cuts that config down to what v86 offers and builds it ("The kernel").

The image boots once, at build time. The agent then prepares a warm machine (X
running, a Python with Tk loaded and its fonts drawn once), and that machine is
saved. Every page restores the saved state; none boots.

## Regenerating the image

[`vm/README.md`](../vm/README.md) is the runbook: build, update to the newest
Alpine, check, package and publish. This section is why it works the way it does.

**One release, named once.** `ARG ALPINE_VERSION` at the top of
`vm/image/Dockerfile` is the only place the Alpine release appears. Both of its
stages build `FROM alpine:${ALPINE_VERSION}`, and `just build-vm-agent` passes the
same value to `vm/agent/Dockerfile`, which has no default so that forgetting it
fails. Python is whatever that release ships, and nothing names its version: the
Dockerfile asks `sysconfig` for the stdlib, and the corpus takes `python3.X` from
the manifest's `interpreter`, which the saved machine's READY reported. Tcl and
Tk 8.6 are still named, by the resident list in `build-state.mjs`. A release that
moves to Tk 9 stops the state build with `no file in the image matches the
resident entry`, and that list is where to start.

**Today's packages.** `just update-vm-image` (`vm/tools/update-image.sh`) takes the
newest stable release from `latest-stable/releases/x86/latest-releases.yaml`, the
index Alpine's download page reads, writes it into the pin and runs
`build-image.sh --fresh`: `--pull` for the base image, and `--no-cache-filter
image`, which reinstalls every package of the image stage. The agent's stage
keeps Docker's cache, since its Rust toolchain does not ship and rebuilding it
costs three minutes under QEMU; a new base image rebuilds it anyway. The agent is
linked statically, so its musl is as old as that cached layer, and the `musl-dev`
line in `NOTICES.txt` says which. A GitHub runner starts with no cache, so its
builds are fresh throughout.

**The lock.** `vm/image/packages.lock` is every apk package in the image, one per
line: name, version, SPDX licence, origin and the aports commit it was built at,
tab-separated because a licence expression holds spaces. It is read from the
image's own `/lib/apk/db/installed`; `apk info` leaves out the licence and the
commit. `build-image.sh` rewrites it on every build of the pinned release into
`vm/build/`, and leaves it alone for a build of another release or into another
directory. It lives under `vm/image/`, so it counts towards `sourceHash`: a
rebuild that picked up new packages has a new `sourceHash`, and a pin committed
without the lock it was built with reads as stale to `check-vm-image-pin`.
`update-vm-image` prints the diff against the committed lock and keeps it in
`<build>/packages.diff`.

**A failed update puts the committed files back.** The pin is written into
`vm/image/Dockerfile` before the build, and `build-image.sh` copies the new
`packages.lock` over the committed one as soon as the image builds, so a run that
fails a check afterwards would leave the tree saying the app ships a release
nothing checked. An `EXIT` trap restores both, and the failure says which files
it put back. `web/vm/image/` it cannot: `build-state.mjs` removes the bundle it
replaces, so a run that got that far says the app's image is now the one that
failed, and that `just build-vm-image` at the restored pin or `just
fetch-vm-image` brings a checked one back. `vm/tools/test/update_image.test.mjs`
drives the script against a repository of its own, with everything it shells out
to stubbed, and forces a failure before and after the bundle is replaced.

**A trial.** `ICC_VM_BUILD_DIR` moves the whole build, the bundle and every report
into a directory of its own (`vm/tools/lib/dirs.mjs`), and `--keep-pin` leaves the
Dockerfile as it is. Together with `--tag` they leave `vm/build/`, `web/vm/image/`,
the committed lock and the `icc-vm-image` Docker tag untouched.

**On GitHub.** `.github/workflows/vm-image.yml` runs the same `update-vm-image` on
`ubuntu-24.04`, monthly and by hand. There `linux/386` runs natively, with no
QEMU. On the schedule it moves to the newest release; by hand it rebuilds the
pinned one unless told otherwise. It runs `check-vm-image`, `check-vm-state` and
the corpus, none of which needs a browser, then `package-vm-image`, and uploads
the archive, its pin, `NOTICES.txt`, the lock, its diff, the reports and
`pin.patch`, the Dockerfile and lock changes it built with. Its `publish` input
creates the release as well; it is off unless ticked, and committing
`vm/image.lock` stays a person's step either way. It has not run on GitHub yet.
The checks' time limits were set on an M1 (READY within 300 ms of a restore, for
one), and a runner may need them loosened.

### The move to Alpine 3.24

The pin was 3.22 until 20 September 2026. It moved for one reason worth having:
3.24 ships Python 3.14, which was the version the lessons themselves taught, so the
Tkinter page and the lesson runtime were no longer a minor version apart. Newer
security fixes come with it. 3.22 is supported until 2027, so nothing forced it.

On 17 October 2026 the lessons moved to CPython 3.15, and the page is a minor
version behind them again. That stays until an Alpine release ships 3.15: the
image takes Alpine's Python and nothing else, and the page names the version it
has.

It was tried first, with `update-vm-image --keep-pin` into `vm/build/regen/`:
Alpine 3.24.2, Python 3.14.7, Tk 8.6.17, kernel 6.18.52, musl 1.2.6, apk-tools 3.
81 packages changed, 3 came and 3 went (`llvm20-libs` for `llvm22-libs`, `libapk2`
for `libapk`, `wayland-libs-server` out, `mesa-gles` in). Nothing in the Dockerfile
or the tools had to change for it. It took 17 minutes on an M1: 8.5 to build, 4 to
save the state and its debug twin, 4.5 to check. Every check passed:
`check-vm-image` 23 of 23 (the kernel check came later), `check-vm-state` 20 of
20, the corpus 33 of 33.

**3.24 by itself is not slower.** The first reports said it was, by 30 to 60% on
every window, but they were taken hours apart while other builds shared the
machine. Run back to back, twice each, the trial bundle is level or ahead:

| | 3.22 (`298ac660`) | 3.24 trial (`f295c6c1`) |
|---|---:|---:|
| Python, Tk | 3.12.14, 8.6.16 | 3.14.7, 8.6.17 |
| `state.bin.zst` | 20.6 MB | 21.1 MB |
| rootfs | 4,218 files, 52.8 MB | 4,290 files, 54.2 MB |
| A run's memory budget | 26,168 kB | 27,536 kB |
| Restore to READY, median of 10 | 146 ms | 136 ms |
| RUN to window, `check-vm-state` | 341, 393 ms | 255, 294 ms |
| Window, corpus `label` / `ttk` / `messagebox-close` | 397 / 655 / 988 ms, then 334 / 521 / 938 | 303 / 551 / 1016 ms, then 261 / 521 / 802 |
| `cold`, a run with no restore before it | 8,264, 7,261 ms | 7,369, 7,591 ms |
| A traceback, RUN to EXIT | 990, 878 ms | 3,268, 3,035 ms |
| A syntax error, RUN to EXIT | 892, 870 ms | 3,375, 3,036 ms |
| Files the corpus `traceback` fetches | 0 | 8 |

Only the build is slower: kernel 6.18 took 32 to 52 s to boot to the agent against
6.12's 24, and PREPARE 39 s against 18, on a machine other builds were sharing.
No page boots or prepares.

**The error message was the one regression, and the prelude fixed it.** From 3.13
on, CPython prints an uncaught exception, a `SyntaxError` included, through
`traceback._print_exception_bltin`, so the first one of a run imports
`traceback`, and with it `_colorize`, `dataclasses`, `textwrap`, `codeop`,
`__future__` and `warnings`. The warm interpreter had never imported them, so in a
page each was a fetch over the network, on the one outcome students meet most:
3.0 s against 3.22's 0.9. `prelude.py` now imports `traceback` in its warm-up,
and `difflib` beside it, which a misspelled keyword reaches for and `traceback`
does not pull in. The corpus `traceback` case is back to 0 fetches and 1,351 ms
end to end, and `check-vm-state` reads nothing over 9p for either the traceback
or the syntax-error check.

### What shipped

The pin moved together with four size changes, so the bundle a student downloads
changed by much more than the release did: the kernel this build now makes
("The kernel"), `init_on_free=1` on the cmdline ("The machine"), zstd -22 rather
than -19 ("The warm snapshot"), and the rootfs prune in the Dockerfile's cleanup
("Inside the image"). Both bundles were measured back to back on one M1, two
rounds each:

| | 3.22 (`298ac660`) | shipped (`dda79f22`) |
|---|---:|---:|
| Python, Tk | 3.12.14, 8.6.16 | 3.14.7, 8.6.17 |
| Kernel | Alpine `linux-virt` 6.12 | this build's 6.18.52 |
| `state.bin.zst` | 20,574,491 B | **15,301,311 B** (-25.6%) |
| Raw state | 76,000,544 B | 57,666,944 B |
| Cold download, state and wasm | 22,676,112 B | **17,402,932 B** (-23.3%) |
| rootfs, the release asset and the deploy | 4,218 files, 52.8 MB | 2,909 files, 28.6 MB |
| Restore to READY, median of 5, two rounds | 144, 136 ms | 104, 120 ms |
| RUN to window, `check-vm-state` | 323, 338 ms | 242, 316 ms |
| Decompressing the state, in the host's own worker path | 123 ms | 97 ms |
| Bundle `load()` to `ready`, from disk | 269 ms | 201 ms |
| The 13 corpus windows a restore serves, summed | 5,098 ms | 4,928 ms |

The rootfs is served, not downloaded: a page fetches a file from it only when the
guest reads one the state does not already hold, which the resident list is there
to prevent. Halving it is a smaller release asset and a smaller deploy, and worth
about 24 KB to the student, who gets a smaller 9p inode table in the state.
`package-vm-image` packs the shipped bundle into 42.4 MiB, against 72.7 MiB for
the 3.24 trial before the prune. The 3.22 bundle cannot be packed for comparison:
it predates `NOTICES.txt`, which `package-vm-image` requires.

The window times are one corpus run each, so read the sum and not the cases: they
range from 25% faster to 13% slower and the sum moves 3%. Only the `cold` case is
plainly slower, 6,978 against 8,010 ms, because 6.18 boots slower than 6.12 —
and no page boots. A traceback is the one thing a student meets that is still
slower than on 3.22: 1,351 against 887 ms, both fetching nothing, against the
3,268 ms it cost on 3.24 before the prelude imported `traceback`.

**The build is not slower after all.** The 3.24 trial above was built with
Alpine's kernel, and that one boots slowly; the kernel this build makes reaches
the agent in 10.2 s, against 3.22's 23 to 31, and PREPARE takes 19.3 s. What is
left is the kernel stage itself, about 4.5 min, and only when the Alpine pin
moves.

Every check passed on the shipped bundle: `check-vm-image` 24 of 24,
`check-vm-state` 20 of 20, the corpus 33 of 33, and `check-vm-app` 39 of 39 in
headless Chrome. It was checked again at integration, on the same bundle and the
same machine, with the same results, and driven through five scenarios in a
Dutch headless Chrome besides ("The app in Chrome").

### Licences

`NOTICES.txt` (`vm/tools/lib/notices.mjs`) is written by `build-state.mjs` into
every bundle and named in its manifest, and `package-vm-image` refuses a bundle
without one. It carries v86's BSD-2-Clause licence in full and names the parts of
v86 under other licences; the SeaBIOS images the saved memory holds (LGPL-3.0),
with the v86 commit whose `bios/` built them; every Alpine package with its
version, SPDX licence, origin and aports commit, with where Alpine keeps the
APKBUILDs and its copies of the upstream sources; and the agent's crates with
their licences, and the Rust and musl it is linked with. Under all of that come a
`Source` section and the licence texts themselves.

The app's licence screen shows the file whole, as one component under *Tkinter*,
in every build that ships the image. It fetches the file the manifest's `notices`
names and holds it to `notices.bytes` (`lib/services/vm/vm_manifest.dart`,
`docs/licenses.md`).

**The texts travel with the binary.** The GPL and the LGPL ask for it, and the
image itself keeps one licence file, CPython's `LICENSE.txt`: Alpine puts the
rest in `-doc` packages, which the image does not install. So `NOTICES.txt` ends
with the text of every licence anything above it declares, out of
[`vm/licences/`](../vm/licences/) (`vm/tools/lib/licences.mjs`), one file per
SPDX identifier and `packages/<name>.txt` for a package whose licence is its own,
which is how the two that declare `custom` carry theirs at all.
[`vm/licences/README.md`](../vm/licences/README.md) says where each text came
from and how to add one. Three things hold it together:

- A text is carried **word for word**. The notices wrap their own prose at 80
  columns and stop wrapping at the `Licence texts` heading; what follows is the
  file as it is.
- One text answers a whole family, so a `GPL-2.0-or-later` text covers a package
  under `GPL-2.0-only`, and the notices print such a pair as one section under
  both names.
- **A gap cannot ship.** `just package-vm-image` reads the notices the way a
  reader would, and refuses a bundle that names a copyleft licence above the
  texts and carries no text for it. `vm/tools/test/licences.test.mjs` says the
  same thing earlier, holding `vm/licences/` against the committed
  `packages.lock`, so an image update that brings in a new licence fails a test
  rather than a release.

Correcting a text needs no image rebuild: `node vm/tools/write-notices.mjs`
writes `NOTICES.txt` again from the build directory the bundle came from and
names it in the manifest, and neither is part of the saved machine.

**The source is an asset on the same release.** The kernel and busybox are
GPL-2.0-only and much else is GPL or LGPL. GPL-2.0 §3 asks for the complete
source with the binaries, or a written offer of it good for three years. A
pointer at someone else's server is not one of its options (GPL-3.0 §6(d) allows
one, GPL-2.0 does not), and Alpine's `distfiles/<branch>/` is not promised to
keep every version. What §3 does accept is equivalent access from the same place
the binaries come from, which here is one more asset beside the image:
`vm-image-<imageId>-source.tar.zst`. `NOTICES.txt` names it, so publishing the
image without it makes the notices wrong as well as the licence unmet. What goes
in it, and how it is built, is vm/README.md, "The source archive".

**The written offer is the fallback, not the plan.** `NOTICES.txt` also carries a
§3(b)-shaped offer: to any third party, good for three years from the release,
answered at the repository's issues. It is what stands where the archive is not
attached, and it binds whoever distributes the image: taking it means being able
to produce that source for three years. Build the archive instead.

Two things this still does not do. The copyright lines MIT, BSD and Apache ask
for are in each package's own source, which the source archive carries, and not
in `NOTICES.txt`. And the agent's crates are held to the texts only at build
time, since `agent-crates.txt` lives in the build directory rather than the tree.

Nobody with legal training has read any of this.

## The pieces

| Where | What | Language |
|---|---|---|
| `vm/image/` | The guest: Dockerfile, config files, the warm interpreter's prelude, `machine.mjs`, and `packages.lock`, every package in it ("Regenerating the image") | Docker, Python |
| `vm/agent/` | `icc-agent`, the one process the page talks to, on ttyS1 | Rust (`rust-version` 1.96) |
| `vm/protocol/` | The control line's spec, `README.md`, and its byte-exact fixtures | |
| `web/vm/vm_protocol.js` | The host's codec for that line | JS |
| `web/vm/vm_host.js` | The host's entry point: `openVm()` loads a bundle, runs programs, stops them, parks the machine; `prefetchBundle()` downloads a bundle without a machine (see "The host") | JS |
| `web/vm/vm_screen.js` | The display in the page, for Flutter's platform views | JS |
| `vm/tools/` | Building the image and the state, the checks, the corpus, the bench, and the host's tests (`test/`) | Node, shell |
| `vm/build/`, `web/vm/image/` | Build output and the bundle a page loads; both gitignored | |
| `vm/image.lock` | The pin: which released image a deploy ships (see "Publishing the image"). Not created yet | JSON |

A run, end to end:

1. The machine is parked: the snapshot restored, the CPU stopped.
2. `run()` resumes the CPU and sends HELLO with the page's clock, time zone and
   64 random bytes. The agent sets `CLOCK_REALTIME`, feeds the bytes to the
   kernel's pool and answers READY.
3. The host writes the files into the guest's 9p tree as `/icc/in/r<id>-<name>`
   and sends RUN. The agent copies them to `/run/icc/work`, owned by the student
   (uid 1000), and writes one line to the warm interpreter's go pipe.
4. The prelude runs `main.py` as `__main__`; its first `Tk()` gets the root the
   warm-up prepared. STARTED, then STDOUT, STDERR, WINDOW and HINT frames come
   back; the agent's X watcher is what sends WINDOW, and it gives the windows
   keyboard focus.
5. The program exits, or Stop sends STOP and the agent kills its process group.
   Either way EXIT arrives, and the host parks: it restores the snapshot and
   stops the CPU, so the next Run starts from the same warm machine.

## Prerequisites

| | |
|---|---|
| **Docker** | With `linux/386` emulation. Docker Desktop on an M-series Mac runs it through QEMU. |
| **Python 3.14**, or any Python 3 with the `zstandard` module | `copy-to-sha256.py --zstd` compresses every rootfs file with zstd. |
| **Node 22 or newer** | For the state and the checks. The recipes install `vm/tools/`, which pins v86 0.5.461. |
| **Disk** | About 1 GB beside Docker's own layers. `build-image.sh` and `build-state.mjs` stop with `DISK_LOW` under 5.5 GB free. `package-image.mjs` and `fetch-image.mjs` write about 45 MB and run in CI, so they stop under three times what they write instead; `ICC_VM_MIN_FREE_KB` sets their floor in KB. |

## What the build does

```bash
just build-vm-image      # vm/tools/build-image.sh, then just build-vm-state
just build-vm-state      # vm/tools/build-state.mjs: the saved machine and the bundle
just build-vm-state --debug-shell   # the same with a root shell, into vm/build/debug-image/
just check-vm-image      # vm/tools/check-image.mjs: the image, booted
just check-vm-state      # vm/tools/check-state.mjs: the bundle, restored
just check-vm-corpus     # vm/tools/corpus.mjs: student programs, the way the page runs them
just check-vm-app        # vm/tools/check-app.mjs: the app from build/web/ in headless Chrome
just test-vm-agent       # cargo fmt, clippy for the Mac and for i686 musl, cargo test
just test-vm             # vm/tools/test: the codec against the fixtures, the host against fakes
just package-vm-image    # vm/tools/package-image.mjs: the bundle as a release asset, and its pin
just fetch-vm-image      # vm/tools/fetch-image.mjs: the pinned image into web/vm/image/, checked
just check-vm-image-pin  # vm/tools/check-image-pin.mjs: whether the pin was built from this tree
```

`build-vm-image` does this. Step 1's build runs the `kernel` stage too, which is
the subject of "The kernel" below: it is cached on everything but a move of the
Alpine pin, so it costs nothing on an ordinary rebuild.

1. `stage-context.mjs` copies the files under `vm/image` and `vm/agent` that
   `sourceHash` hashes ("The bundle") into `vm/build/context/`, and `docker build
   --platform linux/386 --build-context agent-src=vm/build/context/vm/agent -t
   icc-vm-image vm/build/context/vm/image` builds from that copy. Built from
   `vm/image` itself, `COPY files/ /` also took git-ignored files, and a
   `__pycache__/prelude.cpython-314.pyc` that the Mac's own python3 had left beside
   the prelude was in the shipped image while `sourceHash` knew nothing of it. The
   Dockerfile's first stage builds `icc-agent` from the named context, step for
   step as `vm/agent/Dockerfile` does, so the two share Docker's cache of the Rust
   toolchain. The agent is copied in last, so changing it rebuilds nothing else.
2. `docker create`, then `docker export` of that container.
3. `split-export.py` takes the kernel, its config and `kernel.txt` out of `/boot`,
   and writes the rest as `rootfs.tar` without `/boot`, `.dockerenv` or device
   nodes. v86 is handed the kernel directly and there is no initramfs, since the
   kernel mounts the 9p root itself; devtmpfs mounts over `/dev`.
4. `fs2json.py --zstd` writes `fs.json`, the tree v86's 9p server serves.
5. `copy-to-sha256.py --zstd` writes `rootfs-flat/`, one zstd file per distinct
   content, named by its hash. It skips blobs that already exist, so a rebuild
   compresses only what changed; blobs the new `fs.json` no longer names are
   deleted afterwards.
6. `rootfs-stats.json`; `packages.lock`, every apk package with its version,
   licence, origin and aports commit, also copied to `vm/image/packages.lock` for
   the pinned release ("Regenerating the image"); and `agent-crates.txt`, the
   crates the agent is linked from, out of the Dockerfile's `agent-licences`
   stage. `build-state.mjs` writes the bundle's `NOTICES.txt` from both.
7. `fetch-bios.sh` downloads SeaBIOS and the VGA BIOS from the v86 commit the npm
   package was built from, and checks both against pinned hashes. Only a boot needs
   a BIOS, and only the build boots: a browser restores a saved state.

Everything lands in the gitignored `vm/build/`:

| | |
|---|---|
| `bzImage` | 4.4 MB, Linux 6.18.52, built by the `kernel` stage |
| `kernel.config`, `kernel.txt` | The config that was built, and the version, source URL and checksum it came from |
| `fs.json` | 249 KB |
| `rootfs-flat/` | 2,909 blobs, 28.6 MB |
| `bios/` | `seabios.bin`, `vgabios.bin` |

The root filesystem holds 3,224 files (78.4 MB raw), 390 directories and 434
symlinks. The largest parts are the Python stdlib (1,211 files, 27.4 MB), fonts
(91 files, 11.0 MB) and the X data under `/usr/share/X11` (465 files, 4.5 MB).
There is no initramfs and no `/lib/modules`.

The first build took 1 min 22 s on an M1, apk downloads included; a rebuild after
a change under `files/` takes about 12 s. The fs tools, `copy-to-sha256.py` and
`fs2json.py`, are vendored unchanged from v86 apart from a provenance header;
`vm/tools/v86-LICENSE` is their licence.

The image is not reproducible bit for bit. `apk add` takes whatever the pinned
Alpine release publishes that day, which is what `packages.lock` records. The
pinned artefact is the release bundle, not this recipe.

A full rebuild after a change to the agent or the prelude is about 5.5 min on an
M1: 3 min for the agent's release build under QEMU, a minute of image layers, and
a minute and a half to boot, prepare and save the state.

## The warm snapshot

`vm/tools/build-state.mjs` boots `vm/build/` in v86 under Node and speaks the
protocol of `vm/protocol/README.md` to the agent: HELLO, then PREPARE, then
PARKED. It stops the machine, saves it, compresses the state with zstd -22, and
writes the bundle. Nothing is sent between PARKED and the save.

**-22 rather than -19**, because the student downloads this once per image and
the build is where the time belongs: 1,146,464 B less on the 3.22 raw state, and
626,064 B on the shipped one (15,927,375 against 15,301,311 B), for about twice
the compression time. It is also the first level that emits a
single-segment frame, and v86's decoder — the host's own path — gave identical
bytes from it at the same speed (109 against 105 ms) and in the same 100 MiB.
`xz -9e` is 1.58 MB smaller again and was not taken: it needs an LZMA decoder in
the worker and decodes eight times slower, and the cache holds the compressed
state, so that cost is paid on every page open. Brotli saves 0.65 MB and needs a
decoder too, since Chrome 153 has no brotli or zstd `DecompressionStream`.

### What PREPARE does

`vm/agent/src/prepare.rs`, in order:

1. Sets its own `oom_score_adj` to -1000, which Xorg inherits.
2. Mounts tmpfs: 12 MiB on `/run/icc`, which holds a run's files (8 MiB at most,
   each rounded up to a page) beside Xorg's log; 8 MiB on each of `/tmp` and
   `/home/student`; and 8 MiB over `/dev/shm`, which Alpine mounts with no size at
   all, so it was a 29 MiB tmpfs anyone could write.
3. Starts `Xorg :0 -nolisten tcp -noreset -s 0 -dpms vt7` in a session of its own,
   and waits on `-displayfd` until it accepts clients (about 2 s).
4. Starts the warm interpreter, `python3 /usr/lib/icc/prelude.py`, as uid 1000 in
   a session of its own, with `oom_score_adj` 1000 and `RLIMIT_NPROC` 64. Its fd 3
   is the go pipe and its fd 4 the status pipe. It waits for the `warm` line
   (14 to 20 s).
5. Connects the X watcher (`x11.rs`) to the display and starts its thread, after
   the warm-up so it hears nothing of the warm-up's windows, and before the
   zero-fill so the memory the connection and the thread hold is not zeroed
   under them.
6. Remounts `/` read-only. A plain `remount,ro` works on the 9p root; a bind
   remount is the fallback, and neither was needed. It then proves it: statvfs
   reports `ST_RDONLY`, and creating a file fails with `EROFS`.
7. `sync`, then `drop_caches`.
8. Zero-fills free memory, in 1 MiB and then 64 KiB steps, down to `reserve_mib`
   (2) above zero free memory, and gives it back. It stops at free memory rather
   than at MemAvailable, which counts page cache the kernel would reclaim: that
   would evict the warm interpreter's own libraries. The LOG shows the zone
   watermarks and the vmstat counters around the fill; `pgscan` and `pgsteal`
   do not move and no `RssFile` drops. That holds because watermark boosting is
   off (`vm.watermark_boost_factor = 0` in `sysctl.d/10-icc.conf`). With it on,
   two of the builds logged a Normal zone boosted to a 4.7 MiB minimum rather
   than 0.65, and the fill ran into reclaim and took the warm interpreter's
   mapped pages.
9. Reads back whole every file Xorg, the warm interpreter and the agent itself
   map, then the `resident` list. A page of a mapped library the warm-up never
   touched is not in the page cache, and touching it later would have v86 fetch
   the whole file. Before the agent's own binary was on the list, the first
   HELLO after a restore fetched it (370 KB).
10. Mounts cgroup2 on `/sys/fs/cgroup`, hands the memory controller down, and
    creates `run`, the group every program runs in (see "The run's memory"
    below). A budget under 16 MiB fails PREPARE, and with it the build.
11. Caps Xorg's `RLIMIT_DATA` at 16 MiB over the VmData it holds warm (23,424 kB
    in all), room the run's budget leaves free for it ("The run's memory").
12. Locks the agent's own memory with `mlockall(MCL_CURRENT | MCL_FUTURE)`: about
    750 kB that memory pressure can then never evict.
13. Credits every byte it read and sends PARKED.

`resident` comes from `build-state.mjs`: Tcl's and Tk's library scripts and
msgcat, which a second interpreter in one program reads again, `/etc/passwd` and
`/etc/group`, the regular, bold, italic and bold-italic DejaVu Sans, Serif and
Mono, which is what fontconfig gives the families programs name, and the zone
files of `Europe/Amsterdam` and `Europe/Brussels`. Every run reads the zone HELLO
names; any other zone costs the first run of a page one fetch of a few kB, and
the host keeps it for the runs after. tzdata's links are files of their own in
the guest, each with its own page cache, so it is the zone's own path that has to
be read back. PREPARE's whole payload has to fit in 4,096 bytes, which is what
ruled out all of `Europe/`.

### The warm interpreter

`vm/image/files/usr/lib/icc/prelude.py` is the only Python in the guest that is
not the student's. It pre-imports tkinter and what programs import, draws every
widget type once in a root of its own (both font families, a PhotoImage, named
colours, a focused Entry, a messagebox answered by `after`), and destroys that
root. Tk keeps the display connection, and Xft's fonts with it.

It then creates the root the program will get and hands it over through a
wrapper around `_tkinter.create`, so `class App(tk.Tk)` and every other use of
the class keeps working. That root has never been mapped: it is in the state a
cold `Tk()` leaves its root in, so it maps at the program's first idle unless the
program withdraws or iconifies it first. `root = Tk(); root.withdraw();
messagebox.showinfo(...)` shows only the dialog, and the root is never on screen
at all. This is F1's outcome without a deiconify: the root was never withdrawn.

- `Tk(className=...)` gets the warm root too. The handover sets the application
  name and, through ctypes and `Tk_SetClass`, the class, as a new interpreter
  would. `.cget("class")` still says `Tk`, the one difference measured.
- A second `Tk()`, or `Tcl()`, creates an interpreter of its own, as without the
  prelude. A second `Tk()` costs about 1.6 s in v86.
- The program runs as `__main__` with `sys.argv`, `__file__` (absolute, as Python
  3.9 and later give it), the working directory and `sys.path[0]` as `python3
  main.py` would set them, and its traceback starts at its own module.
- **A run may carry the page's setup**: `icc_setup.py` beside the program,
  `vmSetupFile` on the Dart side. The prelude reads it and removes it, then runs it
  in a namespace of its own, once the working directory and `sys.path` are the
  program's and before `__main__` exists. Its source goes into `linecache`, so a
  traceback still quotes the lines of a file that is gone. A setup that raises
  prints its traceback and the program still runs. The Tkinter page fills it from
  the code editor settings, which is how turtle gets its defaults ("Turtle").
- A program that ends without ever entering `mainloop()`, leaving a root it
  neither destroyed nor withdrew, makes the prelude write `hint tk_no_mainloop`
  before it exits. That includes a root never drawn at all, because nothing ran
  the event loop: the window never appearing is the likelier form of the mistake.
  A program that withdraws its root to show only a dialog gets no hint.
- The message box's script and the named fonts are loaded into the handed-over
  root before the snapshot. Both belong to one interpreter, so the warm-up's went
  with its own root, and a first `messagebox` took 1.15 s to appear in v86, 434 ms
  of it sourcing `msgbox.tcl`. Neither processes an event, which is what keeps the
  root unmapped.
- When the program's code returns or raises, the prelude does what `python3`
  does up to its own teardown, in the same order: the traceback or SystemExit's
  message, then the program's threads (`threading._shutdown`), then its atexit
  handlers, then a flush. It then writes `done` to fd 4, and the agent kills
  every other process of the run; the interpreter's teardown, module `__del__`
  methods included, runs as it always did. Neither the threads' wait nor the
  atexit handlers run twice. Checked with the image's own `python3` and a harness
  that runs `run()` on ten programs: exit codes, output order, a thread that
  prints late and a `__del__` at exit came out as `python3 main.py` gives them,
  and a program that calls `os._exit` sends no `done`.
- fd 4 is closed in every child the program forks (`os.register_at_fork`), and
  close-on-exec keeps it from anything it starts. The program itself can still
  write to it, since it runs in the prelude's own process; the agent takes each
  line once per run and only the hint kinds the protocol has.
- **Every run shares the warm interpreter's hash seed**, so the iteration order of
  a set of strings is the same on every run, where `python3` varies it between
  runs. It cannot be varied in a warm interpreter. CPython reads the secret once,
  at start-up, every `str` caches its hash the first time it is hashed, and every
  dict stores its keys' hashes. A new secret would give a string made after it a
  different hash from an equal one made before, so lookups in every dict the
  warm-up built, module globals and interned names among them, would miss.
  `random` is reseeded per run.

Every case was measured against `python3 main.py` without the prelude, first in
an i386 container with Xvfb and then in v86 by `check-state.mjs`.

### The bundle

`web/vm/image/` is gitignored; a deploy fetches it ("Publishing the image").
`build-state.mjs` writes:

| | |
|---|---|
| `<imageId>/state.bin.zst` | The saved machine. `imageId` is the first 16 hex digits of its sha256. |
| `<imageId>/rootfs/` | Hard links to `vm/build/rootfs-flat/`, which the state's 9p tree names. |
| `<imageId>/libv86.mjs`, `v86.wasm` | The v86 build that saved it. A state restores into no other. |
| `<imageId>/manifest.json` | Below. |
| `manifest.json` | A copy of the newest bundle's manifest: the entry point a page fetches. |

It deletes the bundles of earlier builds beside it.

The manifest holds `imageId`, the v86 version with the wasm's size and sha256,
`stateVersion` (read from the state's header), the state's file, size, sha256 and
raw size, the rootfs directory with its file count, `memoryMiB`, `vgaMiB`,
`uart1`, `screen`, `agentProto` (the frame version byte), `agent`, `interpreter`
(Python and Tk, from the READY of a restored machine, since PARKED does not carry
them), `sourceHash` and `builtAt`. `sourceHash` is sha256 over every file under
`vm/agent`, `vm/image`, `vm/tools/build-state.mjs` and `web/vm/vm_protocol.js` that
git tracks or would track, each as its path, its mode as git records it (`100755`
with the owner's exec bit, else `100644`) and the sha256 of its content. The mode
counts because `COPY files/ /` carries the exec bit into the image, and
`mdev-input` runs only because it is set; the other bits follow the checkout's
umask and are left out, so a CI runner and a Mac hash one tree the same way. It
hashes the working tree rather than git's trees, so a build from uncommitted
changes names them too (`vm/tools/lib/source-hash.mjs`).

**What a loader can check.** The state is compressed with zstd's content checksum,
and `state.zstdChecksum` says so; the build fails without it. A state that is
corrupt but the right size then fails to decompress, in v86's decoder (as a wasm
trap, `memory access out of bounds`, not a named error) as in Node's, instead of
restoring a guest that is wrong in ways only a run would find. `state.sha256` and
`v86.wasmSha256` are the sha256 of `state.bin.zst` and `v86.wasm` as served, so the
host can check a download before it caches it. `libv86.mjs` has no hash in the
manifest. A rootfs file needs none: `copy-to-sha256.py` names it by the first 10 hex
digits of the sha256 of its uncompressed content, and `fs.json` gives that content's
size. Those 40 bits catch a corrupt or wrong file, not a forged one. The rootfs
files carry no zstd checksum of their own, so checking one means decompressing it
and hashing the result, which `package-image.mjs` and `fetch-image.mjs` do for
every one (`verifyBundle` in `vm/tools/lib/image-archive.mjs`). One byte flipped near the start of the shipped state, in
its middle, or in the checksum at its end fails both decoders.

Before it writes the interpreter into the manifest, `build-state.mjs` restores the
new state into a fresh `vm_host.js` host and says HELLO; a READY without `warm`
fails the build.

### The checks

`just check-vm-state` restores the bundle through `web/vm/vm_host.js` with its own
`libv86.mjs` and `v86.wasm`, the way a page does, and writes
`vm/build/check-state.json`. Every run starts from its own restore, because the
warm interpreter takes one program. It checks that:

- READY `{warm: true}` arrives within 300 ms of each of five restores;
- `/` is mounted read-only and `/tmp` is not;
- a Tk window from the warm interpreter reaches v86's framebuffer, and STOP ends it;
- each handover case above gives what a cold `python3` gives;
- a program drawing text in eight font families and four styles, and one using
  the usual widgets, read no file over 9p.

`check-vm-state` drives the agent through `vm/tools/lib/agent_line.mjs` rather
than through `openVm()`, so it can run many programs on fresh restores and read
what the guest read over 9p. The corpus below is the check of the run layer.

## Publishing the image

`web/vm/image/` is not committed. A deploy ships the image `vm/image.lock` pins:
a release asset, named by URL and sha256, that the workflow downloads and checks
before `flutter build web`. Without a pin the deploy builds without
`--dart-define=ICC_VM_IMAGE=true`, which leaves the Tkinter page out of the app
("Flutter side"). **No pin exists yet**, so every deploy leaves the page out
until the steps below are done once.

```bash
just package-vm-image    # web/vm/image/ -> vm/build/vm-image-<imageId>.tar.zst, .sha256 and .lock
just fetch-vm-image      # vm/image.lock -> web/vm/image/, checked against the pin
just check-vm-image-pin  # whether vm/image.lock was built from the sources in this tree
```

`just build` passes the define whenever `web/vm/image/manifest.json` exists, so a
local build after `just build-vm-image` or `just fetch-vm-image` has the page.

### To publish an image

1. Build it from the tree you mean to commit, and check it: `just build-vm-image`,
   `just check-vm-state`, `just check-vm-corpus`, then `just build` and `just
   check-vm-app`.
2. `just package-vm-image`. It refuses a bundle that does not match its manifest,
   one whose `<imageId>/` holds a file the manifest does not name, one with a
   rootfs file whose content is not what its name says, one saved with
   `--debug-shell`, one whose protocol is not the page's, one whose `NOTICES.txt`
   names a copyleft licence and carries no text for it ("Licences"), and one whose
   `sourceHash` is not the tree's (`--allow-stale` overrides only that).
   It writes three files to `vm/build/`:

   | | |
   |---|---|
   | `vm-image-<imageId>.tar.zst` | `manifest.json` and `<imageId>/`, as a ustar archive compressed with zstd, 42.4 MiB for the shipped bundle. The same bundle packs to the same bytes. |
   | `vm-image-<imageId>.tar.zst.sha256` | Its sha256, in the format `shasum -a 256 -c` reads. |
   | `vm-image-<imageId>.lock` | The pin for it. |

3. Build the source archive, `vm-image-<imageId>-source.tar.zst`. `NOTICES.txt`
   names it as the complete corresponding source, so it goes on the same release
   as the image. What it holds and how to build it is vm/README.md, "The source
   archive"; no tool does it yet.
4. Upload both as release assets. On GitHub, a release tagged
   `vm-image-<imageId>` with the image archive attached under its own name is
   where the pin's `url` already points, taken from the `origin` remote:

   ```bash
   gh release create vm-image-<imageId> vm/build/vm-image-<imageId>.tar.zst \
     vm/build/source/vm-image-<imageId>-source.tar.zst \
     --latest=false --title "VM image <imageId>" --notes "Built from <sourceHash>."
   ```

   Any other host works too: pass `--url` to `just package-vm-image`, or edit the
   pin's `url`. It MUST be downloadable without credentials, since the workflow
   sends none.
5. `cp vm/build/vm-image-<imageId>.lock vm/image.lock`, then `just fetch-vm-image
   --force`. That downloads the asset from the pin's URL and checks it, exactly as
   the deploy will; `--force` is what replaces the local build in `web/vm/image/`.
6. Commit `vm/image.lock`. The next deploy fetches the image and offers the page.

Keep both assets for as long as a commit that may be deployed again pins the
image. Deleting the image fails the next deploy of that commit, not the live
site: Pages serves the copy it deployed. Deleting the source leaves the notices
promising an asset that is not there, and the written offer standing alone.

### The pin

`vm/image.lock` is JSON. `package-image.mjs` writes every field, and `url` is the
only one to edit by hand. This one is the pin a local packing of the shipped
image produced, which was never uploaded:

```json
{
  "imageId": "dda79f227497cc75",
  "url": "https://github.com/h3x4d3c1m4l/i-can-code/releases/download/vm-image-dda79f227497cc75/vm-image-dda79f227497cc75.tar.zst",
  "sha256": "32085ad63be97d360dbb80413f09f91457c9f9c3b22ce75e6ced1b633a148ebf",
  "bytes": 44468532,
  "sourceHash": "sha256:7631e06c7d2de3fda009d9b713fce4e4b105ca783e55a2d8ce81220e7f61eaf3",
  "agentProto": 1,
  "builtAt": "2026-09-19T22:41:08.943Z"
}
```

| Field | |
|---|---|
| `imageId` | The bundle's directory under `web/vm/image/`: 16 hex digits, the start of its state's sha256. |
| `url` | Where the archive downloads from: `https:`, `http:` or `file:`. |
| `sha256`, `bytes` | The archive's, as uploaded. |
| `sourceHash` | The manifest's: what the image was built from ("The bundle"). |
| `agentProto` | The protocol version the image speaks; the page's has to be the same. |
| `builtAt` | When the state was saved. Informational. |

### What the deploy does

Both workflows run the same two steps before `flutter build web`, so a PR builds
what main will:

- **Fetch the VM image** runs `just fetch-vm-image` when `vm/image.lock` exists,
  and then passes `--dart-define=ICC_VM_IMAGE=true` to the build. A fetch that
  fails fails the build: shipping the page without its image would tell every
  student their connection failed. Without a pin it leaves a notice and builds
  without the page.
- **Check the VM image pin** runs `just check-vm-image-pin`, which holds the pin's
  `sourceHash` to the tree, and only warns: a stale image still loads, it is just
  not what this commit builds.

`fetch-image.mjs` refuses, and unpacks nothing, when:

- the download is not the pin's size or sha256; it stops reading at the pin's
  size rather than fill the disk;
- the pin's `agentProto` is not the page's, before it downloads anything;
- an archive entry is not a file or a directory, would land outside
  `web/vm/image/`, or belongs to another image;
- the bundle does not pass `package-image.mjs`'s own checks, or names another
  `imageId` or `sourceHash` than the pin.

Only then does it swap the new bundle in. An image already in place that the pin
names is kept when it passes the same checks, every rootfs file decompressed and
hashed against its name included (under a second for the 2,909 it holds), and anything
else in `web/vm/image/` is removed, since `flutter build web` would ship it. One
that fails a check is fetched again. One the pin does not name, such as a local
build, is replaced only with `--force`.

Both tools stop with `DISK_LOW` when the disk has less free than three times what
they write, about 135 MB for a 45 MB archive: the download, its unpacked copy, and
a copy across file systems. The 5.5 GB that the image and state builds keep to is
a floor for a Mac that builds images, not for a runner that downloads one.

The tar is written and read by `vm/tools/lib/image-archive.mjs` rather than the
system's `tar`: bsdtar and GNU tar disagree on zstd and add headers of their own,
and Node has zstd built in, so the tools need nothing beyond Node 22.15. The
archive is plain ustar all the same, and `zstd -dc vm-image-<imageId>.tar.zst | tar -t` lists it.

## The agent

`icc-agent` (crate `vm/agent/`, package `icc-vm-agent`) is the only process in
the guest the page talks to. It owns ttyS1, all of the protocol, the student's
files, process control, the clock, the random pool and the X window watcher.
busybox init starts it from `/etc/inittab` and restarts it if it dies. It has
two threads and no async runtime. The main one runs one `poll(2)` over the serial
port, the X watcher's notes, the program's pipes and a pidfd per process, and
waits on nothing else, so it answers PING whatever the program does. The X
watcher's thread owns the X connection and is the only one that waits for the X
server.

| Module | |
|---|---|
| `frame.rs`, `proto.rs` | COBS, CRC and the messages, held to `vm/protocol/fixtures/` by `cargo test` |
| `agent.rs` | The protocol's logic without I/O: bytes and time in, frames and actions out |
| `outbox.rs`, `log_limit.rs` | Frames waiting for the line; LOG at 20 a second |
| `output.rs` | A run's STDOUT and STDERR: batched and capped |
| `supervisor.rs` | A run from its files to its EXIT; the warm or a cold interpreter |
| `prepare.rs` | PREPARE, and how a student's process is started |
| `files.rs` | `/icc/in/r<id>-<name>` to `/run/icc/work`, as the student |
| `clock.rs`, `entropy.rs` | HELLO's `now_ms` and `entropy` |
| `x11.rs` | The X window watcher and its thread: WINDOW, focus and CLOSE |
| `wake.rs` | A channel a `poll(2)` can wait on: how the two threads reach each other |
| `cgroup.rs` | The run's cgroup: its memory budget, its kill and its OOM count |
| `serial.rs`, `event_loop.rs`, `main.rs` | The port, the loop, the command line |

The release binary is 785,168 B, static-pie, built inside the image build with
whatever Rust the pinned Alpine ships, 1.96.1 on 3.24. The crate's
`rust-version` is 1.96 to match, and it is the floor `cargo clippy` holds it to.
Its dependencies are `libc`, `serde`, `serde_json`,
`crc32fast` and `x11rb` 0.14 without default features, a pure-Rust X client
that needs nothing from the image.

**A run.** RUN copies the files (8 MiB at most, each checked to exist, and all of
them checked against the free space of `/run/icc`) into a new `/run/icc/work`
owned by uid 1000, dropping each source's pages from the page cache as it goes,
and lowers the run's `memory.max` by what the copies occupy ("The run's
memory"). It moves the warm interpreter into the run's cgroup and writes the go
line to its fd 3. STARTED says `warm: true`. Should no warm interpreter be
waiting, which only happens when a RUN reaches a machine that was not restored
after the last one, the agent starts `python3 main.py` as the student instead
and says `warm: false`: 6.1 to 6.6 s to a first window rather than 0.23 s, and no
`tk_no_mainloop` hint, since that comes from the prelude.

**Output.** One batch rather than one per stream, so the host sees stdout and
stderr in the order they were read and a traceback cannot overtake the prints
before it. A batch leaves at 4,096 bytes or 16 ms after its first byte, split
into frames of 16 KiB at most. Past `output_cap` (256 KiB from the page) the
agent keeps reading and discarding, so the program never blocks on a full pipe,
and EXIT says `truncated`.

**The end of a run.** A program that exits by itself is reaped, its last output
and any HINT are forwarded, everything left in the run's cgroup is killed with
`cgroup.kill`, and then EXIT. A warm program is done before that: once its code,
threads and atexit handlers have finished, the prelude writes `done`, and the
agent kills every other process in the cgroup then, so the interpreter's teardown
does not share the CPU with them. Forty spinning children held a finished
program's EXIT up for 15.7 s before that; ten now cost 0.8 to 0.9 s. The OOM killer
shows as the `oom_kill` counter of the run's cgroup (`memory.events`) or of
`/proc/vmstat` moving during the run, and makes the reason `oom`; a LOG says which.
Before each EXIT the agent LOGs the cgroup's `memory.peak` at debug level, which
the corpus records. A run the agent kills, for STOP or for a CLOSE the window cannot
take, ends the moment SIGKILL is sent: EXIT reached the host 2.1 to 9 ms after
STOP. The kernel's teardown of a python3 holding Tk takes 70 to 230 ms more in
v86 (measured with a root shell and a pidfd), and waiting for it only held up the
park that discards it anyway. The agent reaps it in the background.

**The X watcher.** It watches the root window's children with
SubstructureNotify, so it sees top-levels come and go without redirecting
anything; it is not a window manager. It keeps the list from the events
themselves: CreateNotify and ConfigureNotify carry each window's geometry and
where it sits in the stacking order, and MapNotify, UnmapNotify, DestroyNotify
and ReparentNotify the rest. A list needs the server only for a window's title
and `WM_TRANSIENT_FOR`, read once per window, in one round trip for every window
that needs it, and again after a PropertyNotify says one changed. A sibling the
events name that the watcher does not know makes it read the stacking order with
QueryTree instead. The first change after a quiet spell goes out at once, the
rest at most every 16 ms, and a list goes out only when it differs from the last.
Asking the server for the whole list each time, five requests a window, took a
round trip that grew to 150 ms with thirteen windows while Tk was drawing them,
and the corpus's `window-follows` saw a WINDOW 137 ms after the window's pixels;
from the events every WINDOW came before the pixels were read back. It runs on a
thread of its own that owns the connection and talks to the main one through two
channels (`wake.rs`); after anything that waited for a reply it handles every
queued event before it goes back to `poll(2)`. Both are fixes. With the watcher
on the main thread, another client's `XGrabServer`, or a Canvas large enough to
keep the server busy, stopped the agent answering PING, and the run ended
`unresponsive`; and a MapNotify read during a reply wait sat in x11rb's queue
until the next wakeup, up to a PING later, which is what made WINDOW and F4's
focus late in Chrome at 4x and 6x. The Tk root the warm interpreter handed
over is the `root` entry, found as the parent of its `.` window once Tk has
wrapped it at the first map. Focus (F4) goes to each top-level as it is mapped
and back to the latest one still showing when the focused one leaves; a passive
button grab on each top-level sends clicks to the agent first, which focuses
that top-level and replays the click to where it was going. CLOSE sends
`WM_DELETE_WINDOW` when the window lists it, as a window manager's close button
does.

**HELLO.** `clock_settime(CLOCK_REALTIME)` from `now_ms`, then `RNDADDENTROPY`
with the 64 bytes, credited as 512 bits, and `RNDRESEEDCRNG` so the CRNG takes
them now rather than at its next scheduled reseed. The prelude reseeds `random`
from that pool when the program arrives, which is why dice differ between runs
that all start from the same snapshot.

**What the student cannot reach.** The program runs as uid 1000 in a session of
its own with `RLIMIT_NPROC` 64, in the run's cgroup, which only root can leave.
`/icc/in` is root's (0700), ttyS1 is not the student's to open, the agent's
`/proc` files are unreadable to it and its signals do not reach it, `/` is
read-only, and the writable places are tmpfs mounts of 8 MiB, and 12 MiB for
`/run/icc`, where the working directory sits beside Xorg's log. The prelude's
status pipe is closed in any child the program forks; the program itself can
write to it, and the agent sends at most one HINT of each kind the protocol has
per run, whatever arrives there. The agent sets `no_new_privs` before it drops to
uid 1000, so no exec can hand the program root back, and the image has no setuid or
setgid file for one to try: `busybox-suid` is not installed, which leaves `su` a
plain busybox applet that refuses to run, and `Xorg.wrap` lost its bit, since the
agent starts Xorg as root. The Dockerfile fails the build on any such file. The
corpus's `sandbox` case checks each of these from inside a program, `su` among
them, and floods the status pipe with 2,000 hint lines.

**The run's memory.** Everything a run's processes allocate is charged to its
cgroup, the pages it writes into tmpfs included, so one `memory.max` bounds all of
it, and running out is an OOM inside the group: `memory.oom.group` kills the whole
run and the rest of the guest keeps its memory. The budget is what PREPARE finds
free plus the page cache nothing maps, less the high watermarks, the 16 MiB Xorg
may grow by (below) and 2 MiB for the kernel: 40,284 kB on the shipped image,
against 25,604 to 26,304 kB before this build's own kernel gave back the RAM
Alpine's was holding ("The kernel").
At 96 MiB, with 2 MiB set aside for Xorg and the kernel together, it was 9,504 to
10,244 kB. Beyond it the kernel reclaims pages Xorg, the agent and the warm
interpreter map, and fetches them again over the network while the run goes on;
before the cgroup, `oom.py` got to 29 MiB and then the agent itself was evicted
and the run ended `unresponsive`. Now it ends `oom` with no fetch at all, after
1.06 s with 39 MiB allocated (0.73 to 1.2 s and 25 MiB before the slim kernel;
0.73 to 0.9 s at 96 MiB, with less to
fill). Only what the program
allocates counts: the warm interpreter joins the group at the handover, and its
warm-up's memory stays charged where it was. What that leaves, measured through
the cgroup's `memory.current`, at 128 MiB unless a row says otherwise:

| Program | New memory |
|---|---:|
| Every corpus program that draws | under 256 kB (the kernel charges 64 pages at a time) |
| `sandbox.py` | 1.7 MB (1.2 MB before it ran `su`) |
| A PhotoImage of 640 x 480 | 3.0 MB at its peak, at 96 MiB |
| A PhotoImage of 1024 x 768 | 6.5 MB at its peak, at 96 MiB |
| A PhotoImage of 1920 x 1080, in a Label | 16.4 MB at its peak; at 96 MiB, past the budget: `oom` |
| Each `os.fork()` of the warm interpreter, the child asleep | about 1 MiB, so the 27th fills it; at 96 MiB, 15 did |

More would need more guest RAM (`memoryMiB` in `vm/image/machine.mjs`), which the
page pays for in wasm memory ("The machine").

**The budget has a floor.** A 96 MiB build with 18 MiB set aside for Xorg and the
kernel came out at 0 kB, wrote that `memory.max` and saved the machine anyway,
and every run in it would have ended `oom`. So PREPARE fails under 16 MiB
(`MIN_BUDGET_KB` in `cgroup.rs`), and with it the build, in a message that gives
the budget, what it was measured from and the reserve that took it. 16 MiB leaves
a run with the most files it may have about 8 MiB. `build-state.mjs --memory-mib
96` stops at PREPARE with "the run's memory.max would be 0 kB, under the 16384 kB
floor: 13640 kB of free memory and unmapped page cache, less 1616 kB of high
watermarks and the 18432 kB reserved for Xorg and the kernel", and writes no
bundle.

The run's files are the one part of a run not charged to it: the agent copies them
into `/run/icc`, so their pages are the agent's. They come out of the same free
memory all the same, so RUN lowers `memory.max` by what the copies occupy, each
file rounded up to a page, for that run alone; the next restore brings the whole
budget back. Before that, a run with 8 MiB of files still had its whole budget,
allocated 9 MiB of it, and the kernel found the difference by evicting
`libpython3.12.so` and Xorg's binary, which a page fetches again over the network
(7.4 MB). Now such a run gets what is left, 32,084 kB on the shipped image
(17,808 to 18,104 kB before the slim kernel, 1,748 to 1,940 kB at 96 MiB),
allocates it, and ends `oom` with no fetch, as `big-files` checks. The copy also drops each source file's
pages from the page cache as it goes: the files arrive over 9p, whose pages the
guest caches too, and 8 MiB of them read at once would compete with the pages
the rest of the guest maps.

Xorg allocates what a program's windows need, and that is not the run's. Tk
redraws a Canvas through a pixmap the size of the part it redraws: 7.9 MiB at
1920 x 1080, 9.8 MiB at 1600 x 1600, and 36 MB at 3000 x 3000. Uncapped, the
kernel evicted every mapped page to find that last one, the agent's own binary
among them, and the run ended `unresponsive` in 3.1 s. `RLIMIT_DATA` 16 MiB over
what Xorg holds warm turns it into a BadAlloc for the program, which Xlib reports
and exits on: `X Error of failed request: BadAlloc`, exit code 1, 0.4 to 0.7 s
after it began. Measured as Xorg's VmHWM over its warm 10,348 to 10,404 kB:

| Program | Xorg's peak | |
|---|---:|---|
| A Canvas of 1920 x 1080 (`hd-canvas`) | +8,192 kB | draws |
| A Canvas of 1600 x 1600 (`hd-canvas`) | +10,276 kB | draws |
| A Canvas of 1980 x 1980 | +15,616 kB | draws |
| A PhotoImage of 1920 x 1080 in a Label | +16,088 kB | draws, and Xorg holds 8.1 MB of it afterwards |
| A PhotoImage of 1920 x 1080 on a Canvas of its size | | BadAlloc: the photo's pixmap and the Canvas's, 16.2 MB at once |
| A Canvas of 1990 x 1990, or 3000 x 3000 | | BadAlloc |

At 96 MiB the cap was 8 MiB, and a 1920 x 1080 Canvas was a BadAlloc, shown to
the student as a crash of their own program.

**Those 16 MiB are left out of the run's budget.** At 96 MiB, Xorg's 8 MiB came out
of the 2 MiB of headroom and memory the budget had already counted as the run's.
A program holding 9 MiB that then drew a 1600 x 1200 Canvas made the kernel find
Xorg's pixmap by evicting mapped pages, and `libpython3.12.so`, `libpng` and
`libbz2` were fetched again during the run (probed on image `7580ed6dc2732d62`).
Now `near-budget` fills its budget to within 1.5 MiB and draws a 1920 x 1080
Canvas with no fetch, the pixmap taken from free memory. With a 1980 x 1980 Canvas
instead, Xorg at 15.6 MB over its warm size, the kernel reclaimed 1.9 MB of page
cache that nothing maps, left every mapped page (`Mapped` stayed at 16,048 kB) and
fetched nothing. The agent's `mlockall` keeps it answering PING even when
something else runs the guest short.

## The host

`web/vm/vm_host.js` is the entry point the page and the tools import, and holds
nothing of its own:

| Module | |
|---|---|
| `vm_run.js` | `openVm()`: README section 9's state machine on top of the machine. What the app uses. |
| `vm_machine.js` | `createVmHost()`: the machine. A v86 built without firmware, restored from a snapshot, its CPU stopped whenever nothing needs it to run, with the TSC workaround, its own rootfs fetching and its own yield. The build tools use it directly. |
| `vm_bundle.js` | Reading a bundle: the manifest, `loadBundle()` and `prefetchBundle()`, libv86.mjs, and decompressing the state. |
| `vm_download.js` | Downloading one: the state in Range pieces, the one download per image that every caller joins, and the byte rate. |
| `vm_cache.js` | The Cache API: the image locks, the pieces a file is kept in, and the rootfs files programs fetched. |
| `vm_watchdog.js` | README 9.7's deadlines, on active time. |
| `vm_util.js` | The few helpers the others share. |

"Host API" below is the contract the Dart side binds to.

- **Loading.** `manifest.json` is revalidated on every load, and its
  `agentProto` checked before anything else is fetched. The wasm, the state and
  `libv86.mjs` go through the Cache API under their bundle's URLs, which change
  with every image, so a second visit reads them without a request. Offline, the
  manifest from the last load stands in, and `libv86.mjs` is imported from the
  kept copy (through a blob URL) once its own import fails. A browser that
  refuses storage downloads again. Under Node the same code reads the files from
  disk.
- **The state comes down in pieces, and a download that stops resumes.** The
  state is fetched in HTTP Range requests of 2 MiB, three at a time, with `cache:
  'no-store'` so the HTTP cache keeps no second copy; each piece goes into the
  Cache API as it lands, keyed `state.bin.zst?bytes=START-END`. A load that finds
  pieces fetches only the gaps; a piece whose connection drops keeps what arrived
  (for the next load too, from 64 KiB) and its retry asks for the rest. A request
  that fails is tried again after 1, 2, 4 and 8 s, a browser that says it is
  offline is waited for up to 30 s first, a request that receives nothing for
  15 s is ended and tried again, and a 404 is never retried. The first request
  goes alone and decides the rest: a 206 whose `Content-Range` fits lets the
  others follow, and a 200, the answer of a server that ignores ranges (`flutter
  run`'s does), is read as the whole file in that one request, dropping any
  pieces. A 206 whose total is there and is not the manifest's size is a range of
  another representation, which is what GitHub Pages sends a client that asks for
  gzip; it is taken as no ranges and the file is asked for again without one. A
  total of `*`, the wildcard RFC 9110 14.4 allows a server that does not know the
  complete length, contradicts nothing and is read as a range of the file; what
  the pieces add up to is held to the manifest either way.
- **A download that cannot finish ends, and the page offers its Retry.** A short
  206 is a legitimate answer, so a server or proxy that truncates every Range
  makes headway on every try and would be resumed until the tab was closed, one
  request per sliver. An attempt has to deliver 64 KiB, the same bar as a piece
  worth keeping, before the retries start over; below it the attempt counts as no
  progress, and the file fails once the four waits are used up. Over the whole
  run there is a 20 minute deadline, which is 15 kB/s for the 17 MB and under
  that nothing else on the page works either. Either way the page is told
  `failed` with `VmFailure.network`, which is the failure card and its Retry;
  before this, both cases were a download that went round for ever behind a
  loading panel that offers nothing to press.
- **The wasm has no resume.** `readWhole` fetches v86.wasm, 2 MiB and compressed
  by Pages, in one request with no Range, so an attempt that fails starts again at
  byte zero, four times. Only the state resumes: it is 15 MB against 2, and every
  piece kept is a piece to check, delete and count again. `vm_download.js` says so
  where `readWhole` is defined.
- **One download per image, whoever asks.** The download lives at module level,
  keyed by the bundle's URL, and every caller joins the one in flight: a second
  `openVm()`, and `prefetchBundle()`, which downloads into the Cache API without
  building a machine. A caller that joins part way hears the current progress at
  once. A caller that leaves (its `signal`, or a `Vm` destroyed while it loads)
  stops only its own wait; the download stops 5 s after the last caller left,
  which lets a page opened again, or an `openVm()` that replaced another, pick it
  up where it is. What it kept stays either way.
- **Progress counts against the manifest.** `loaded` and `total` are the bytes
  of the wasm and the state as the manifest names them, counted as the body
  arrives, so a server that compresses on the way does not skew them (its
  `Content-Length` would be the compressed size). Bytes from the Cache API count
  as `cached`. The rate is the network's alone, averaged until 3 s in and then an
  exponential moving average with a 3 s time constant, and is reported only after
  2 s and 256 KiB of it; `remainingMs` follows from it. `stalled` says nothing has
  arrived for 3 s or a retry is waiting. `navigator.connection` is read once, as
  `slowConnection`, and only ever shown as a hint.
- **Room first.** Before a download that has anything to fetch, the host asks
  `navigator.storage.estimate()`. With less room than what is missing plus
  4 MiB, it downloads all the same but keeps nothing new, and says so as `keeps:
  false`. A load the Cache API can serve asks nothing. Where there is room, a
  Chromium browser (one with `navigator.userAgentData`) is asked to `persist()`
  the origin's storage, which it grants or refuses without asking; Firefox
  would put a prompt in front of the student, so it is not asked, and neither is
  Safari.
- **Nothing is used unchecked.** The wasm is held to the manifest's size and
  sha256 before it goes into the Cache API, and again each time it comes out. A
  copy that fails is deleted, never cached, and fetched once more with `cache:
  'reload'`, past the HTTP cache; a second failure fails the load as `network`.
  The manifest names no hash per piece, so the state's pieces are cached as they
  land, and the whole state is held to the manifest's sha256 before it is used,
  from the network or the cache alike; when it fails, every piece is deleted,
  since nothing says which one is wrong, and the state is read once more. A
  manifest is cached only once it parses, and `libv86.mjs` only when it came as
  JavaScript. So a captive
  portal that answers with a page of its own, or a proxy that cuts a file short,
  fails that one load, and Retry on a working network loads. A state that will
  not restore, or whose agent does not answer HELLO after two restores, is
  dropped from memory and from the cache, so the next load reads it again. Only
  a secure context has SubtleCrypto, and only a secure context has the Cache API;
  elsewhere the size is the whole check. The sha256 of the two files added 7 to
  17 ms to reading them from the Cache API at 1× and 35 to 79 ms at 4× CPU
  throttling in headless Chrome (bench `park`, with and without the check).
- **The state is decompressed once, in a worker.** v86 restores a zstd state by
  decompressing it inside `restore_state`, on the main thread, and every run ends
  in a restore; at 4× CPU throttling that froze the page for half a second after
  each run. So once the zstd state is read, the host decompresses it with
  v86.wasm's own decoder in a worker of its own, ends the worker as soon as the
  55.0 MiB raw state is back, and restores from that raw state at the load and at
  every park. The worker runs while v86 compiles and starts, so the load only
  waits for whichever of the two takes longer. v86's own `zstd_decompress_worker`
  is not used: it starts from `wasm_source`, which v86 sets only when it fetches
  its wasm itself, and it keeps its worker, and that worker's 173 MiB, for the
  life of the page. Under Node, which has no `Worker`, the state is decompressed
  in place. If it will not decompress, the zstd state restores as before, and a
  `log` event says so.
- **Other tabs.** A page holds a shared Web Lock named for the image it loaded,
  from before it reads the image's files until its `Vm` is destroyed or the page
  closes. A page that loads a newer image deletes an older image's cached files
  only when it can take that image's lock exclusively, so a tab still on the older
  image keeps its copy, and the first load after that tab is gone cleans up.
  Without Web Locks it cannot tell, and deletes them.
- **Runs.** `run()` supersedes: the run in progress ends as `stopped` and the new
  one starts after the park. A `run()` before the machine is ready waits for it.
  Every run ends in a park, which the host starts only after a frame has painted.
- **The watchdog** (F2) counts active time only: it samples every 100 ms, adds at
  most 100 ms per sample, and adds nothing while the page is hidden or the CPU is
  stopped; the last of those to go restarts the deadline in full. A backgrounded
  tab cannot run it out. A rootfs file on its way suspends the count instead,
  for at most 30 s per deadline, and the count goes on from where it stood once
  the file lands: restarting on every file would let an agent that hung while its
  guest reads files live for good.
- **Yielding.** v86 hands the main thread back after every slice of about a
  millisecond, and in a browser it waits for a round trip through a blob worker
  to get it back. That round trip queues behind whatever else the page does, so a
  page that works on every frame starved the guest (see "frame-load"). The host
  replaces it with a `MessageChannel` to the page itself (`yieldThroughChannel`)
  and ends v86's worker. An idle guest still waits for its next timer, on a
  timeout set from the channel's message task, so a chain of idle waits never
  nests deep enough for the browser's 4 ms clamp. Under Node v86 yields with
  `setImmediate`, and that stays.
- **The clock.** The host stops the guest's TSC with its CPU, so a guest never
  sees parked or hidden time pass at once. The wall clock falls behind by that
  much, so HELLO follows every resume, the one after a hidden page included.
- **Rootfs files** (F3). v86 never settles a failed load, so the host fetches
  them itself. A 404 fails at once, a network error or a 5xx is retried once
  after a second, and a failure ends the run as `fetch` 50 ms later, which lets
  through what the program printed before the read. A load that lands after a
  restore is dropped. Closed files are kept up to 16 MiB, where v86 drops each on
  close.
- **Rootfs files outlive the page.** A file fetched over the network goes into
  the Cache API too (`RootfsCache` in `vm_cache.js`), once its content's sha256
  starts with the ten hex digits its name has, so a second run or visit, or a
  page without a network, reads it from there (`rootfs-cached`, not
  `rootfs-fetched`). They are kept up to 32 MiB per image, the least recently
  used going first, in an order kept in an index entry beside them; they sit
  under the image's URL, so they go with the image. A file named any other way is
  not kept, since nothing could check it.
- **Hints.** The host passes on only the hint kinds README 6.8 lists, and each
  once per run: the student's own process can write to the pipe the prelude's
  hints travel on, and no output cap bounds them.

## Host API

What the Dart side binds to: `openVm()`, the `Vm` it returns, its events and
states, `prefetchBundle()`, and `VmScreen`. Anything else the modules export is
for the tools and the tests. A later version may add options, members, event
types and event fields; the names, shapes and meanings below stay.

`web/vm/vm_host.js` exports `openVm` and `prefetchBundle` (and `createVmHost`
and `Watchdog`, for the tools and tests); `web/vm/vm_screen.js` exports
`createVmScreen` and `VmScreen`. Both are ES modules the app loads from its
`vm/` directory.

```js
import { openVm } from './vm/vm_host.js';
import { createVmScreen } from './vm/vm_screen.js';

const screen = createVmScreen({ onFocus: ({ viewId, inside }) => {} });
const vm = openVm({ baseUrl: 'vm/image/', screen, onEvent: event => {} });
await vm.load();                    // never throws: the `ready` or the `failed` event
const run = vm.run({ files: { 'main.py': source }, entry: 'main.py' });
run.id;                             // every event about this run carries it as `run`
await run.ended;                    // the `ended` event, exactly once, however it ended
vm.closeWindow(xid);                // the close button on a window's own strip
await vm.stop();                    // ends the run for the caller at once; resolves once parked
await vm.destroy();                 // when the student leaves the screen
```

### `openVm(options)`

Returns a `Vm` at once and downloads nothing until `load()` or `run()`. There is
one per page: opening another destroys the one before without waiting for it.
The old one's runs still get their `ended` events, and then its `onEvent` gets
`failed` with the reason `replaced`, so a page whose machine another page took
does not wait on it. A `load()` on it afterwards resolves as that same `failed`.

| Option | Type | Default | |
|---|---|---|---|
| `baseUrl` | string | required unless `bundle` is given | The directory that holds `manifest.json`: in the browser a URL, absolute or relative to the document's base URL (the app's `<base href>`), as `fetch` resolves it; under Node a path. |
| `onEvent` | `(event) => void` | none | Receives every event below. Whatever it throws is caught and logged to the console. |
| `screen` | `VmScreen` | none | The display. Without one the machine runs headless, with no keyboard or mouse. |
| `trackVisibility` | boolean | true where there is a `document` | Follows `document.visibilityState`. With false, the caller calls `setVisible()`. |
| `fetchFile` | `(url, signal) => Promise<Uint8Array>` | `fetch`, or the file system under Node | How rootfs files are fetched. It MUST reject on failure and MAY set `status` on the error; a 4xx other than 408 or 429 is not retried. |
| `readAsset` | `(url, onBytes, signal) => Promise<Uint8Array>` | the Cache API, or the file system under Node | How `v86.wasm` and the state are read. What it returns is held to the manifest's size and sha256 all the same. `signal` aborts once the other file has failed, and bytes reported after that are not counted. |
| `bundle` | `{manifest, V86, wasm, state, rootfsUrl, release, evictState}` | none | A bundle already in memory, which skips the download; `release` and `evictState` are optional. For tools and tests. |
| `download` | `{pieceBytes, parallel, ranges, retryDelaysMs, stallMs, lingerMs}` | vm_download.js's | The download's knobs; `ranges: false` asks for the state in one GET. Taken from whichever caller starts the download. For tests and the bench. |
| `now` | `() => number` | `performance.now()` | The watchdog's clock, in ms. For tests. |

It throws `TypeError` when neither `baseUrl` nor `bundle` is given.

### `prefetchBundle(options)`

Downloads the image `baseUrl` names into the Cache API without building a
machine, so that a later `openVm()` finds it there, and resolves once all of it
is there and checked. **There is one download per image on a page**: a
`prefetchBundle()` or `openVm().load()` that starts while one is under way joins
it rather than starting another, hears the same `progress` from where it is at
once, and gets the same outcome. It is what a page that wants the machine soon,
but not yet, calls; the `openVm()` that follows joins the download or reads the
finished one from the cache.

| Option | Type | |
|---|---|---|
| `baseUrl` | string | As `openVm()`'s. Required. |
| `onProgress` | `(progress) => void` | The `progress` event's fields but `type` and `phase`, at most every 100 ms and once at the end. Never after the promise settles. |
| `signal` | `AbortSignal` | Stops this caller's wait, which rejects with `reason` `aborted`. The download goes on while another caller waits for it and stops 5 s after the last one left; what it kept stays, and the next download starts from it. |

It resolves with `{imageId, total, cached, fetched, keeps}`: of `total` bytes,
`cached` came from the Cache API and `fetched` over the network, and `keeps`
false means the browser had no room to keep them. It rejects with `reason`
`network`, `incompatible` or `aborted`, and a message for developers. Under
Node, where a bundle is a directory, it resolves at once.

### `Vm`

| Member | |
|---|---|
| `state` | A string, one of the states below. |
| `interpreter` | `{python, tk}` as the guest names them, once ready; null before. |
| `manifest` | The loaded image's manifest, or null. |
| `load()` | Downloads the bundle, builds the machine and parks it. Resolves with the `ready` or the `failed` event and never rejects. Calls share one load; after a failed one, the next call tries again. |
| `run({files, entry, argv})` | Starts a program and returns `{id, ended}` at once: the run's id, and a promise of its `ended` event that never rejects. See "Runs" below. |
| `stop()` | Ends the run in progress, and a queued one, as `stopped` at once. Resolves once the machine is parked again (after the run's EXIT, or 500 ms after STOP, plus one restore), failed or destroyed. It depends on nothing the guest does. |
| `closeWindow(xid)` | What the close button on window `xid`'s own strip does: CLOSE for the running run. Does nothing in any other state. |
| `setVisible(visible)` | The page was hidden or shown, for a `Vm` opened with `trackVisibility: false`. |
| `destroy()` | Ends every run as `stopped`, frees the machine and lets go of the image. Resolves once the emulator is gone, one that was still loading included. |
| `consoleText()` | The kernel console's last 16 KiB, as text, for failure reports. |
| `stats` | Counters for diagnostics. Not a contract. |
| `emulator` | The raw V86. For the tools only. |

**Runs.** `files` maps flat names to contents, a string (sent as UTF-8) or a
`Uint8Array`: 1 to 64 files, each name matching `^[A-Za-z0-9_][A-Za-z0-9._-]{0,63}$`,
8 MiB together. `entry` is the file run as `__main__` and MUST be one of them.
`argv`, optional, is strings without NUL. A program that breaks any of this, or
whose RUN would not fit in one frame, throws `TypeError`, and nothing is sent.

- A run supersedes: one in progress ends as `stopped`, and the new one starts
  after the park. It never waits for the old one. A run queued behind it that has
  not started yet ends as `stopped`.
- A run asked for before the VM is ready loads it first, and starts once it is. A
  load that failed is tried again. When the VM failed after it was ready, or was
  destroyed, the run ends at once as `broken`.
- Every accepted run gets exactly one `ended` event.

### States

| `state` | |
|---|---|
| `unloaded` | Nothing downloaded yet. |
| `loading` | Downloading, building the machine and greeting the guest. |
| `parked` | Ready: restored and waiting, its CPU stopped. |
| `starting` | A run was asked for; its HELLO, files and RUN are on their way. |
| `running` | The program is running. |
| `stopping` | The run has ended for the caller; the host waits up to 500 ms for its EXIT. |
| `parking` | Restoring the snapshot after a run. |
| `failed` | It cannot run programs. A failed load is tried again by the next `load()` or `run()`; after the machine was ready, only a new `openVm()` leaves this state. |
| `destroyed` | `destroy()` was called. |

No event announces a state change as such; `ready`, `started`, `ended`,
`parked` and `failed` mark the moments that matter.

### Events

Plain objects with a `type`. Every event about a run carries its id as `run`.

| `type` | Fields | When |
|---|---|---|
| `progress` | `phase`; `loaded`, `total`, `cached`, in bytes; `rate` or null; `remainingMs` or null; `stalled`, `keeps`, `slowConnection`: booleans | While the machine loads. `phase` is `download` while the bundle is read, at most every 100 ms and once at the end, from the cache as from the network; then `unpack` once, as the state decompresses, and `start` once, as the machine starts. `loaded` and `total` count the wasm and the state as the manifest names them; `cached` is what the Cache API held of `loaded`. `rate` is bytes per second over the network, smoothed, and null until 2 s and 256 KiB of it; `remainingMs` is what is left at that rate. `stalled`: nothing arrived for 3 s, or a retry waits; the download goes on by itself. `keeps` false: the browser has no room, or no storage, and the next load downloads again. `slowConnection`: `navigator.connection` guesses the line is slow, a hint only. Never after the load's `failed`: the first file that fails aborts the other's download. |
| `ready` | `python`, `tk`: strings, as the guest names them; `imageId` | The machine is parked and waiting. Once per successful load. |
| `failed` | `reason`, `message` | The VM cannot run programs (reasons below). |
| `started` | `run`; `warm`: boolean; `pid` | The program is running. `warm` false is the cold interpreter, 6.1 s to a first window. |
| `output` | `run`; `stream`: `stdout` or `stderr`; `text` | What the program printed, in the order the agent read it, decoded per stream so that a character split across frames arrives whole. |
| `window` | `run`; `windows` | The run's top-level windows, the whole list every time, bottom to top: `{xid, title, x, y, w, h, mapped, root, transient_for}` (README 6.7). |
| `hint` | `run`; `kind` | `tk_no_mainloop`: the program ended without `mainloop()` and left its root (README 6.8). At most once per run, and before its `ended`. |
| `ended` | `run`, `reason`, `code`, `signal`, `truncated`, `ms`, `message` | Exactly once per run, however it ended. `code` and `signal` are the exit status and the signal, either or both null; `truncated` says the output passed 256 KiB; `ms` is the guest's time for the run, null when the host ended it; `message` explains an end the host decided, else null. No `output`, `window` or `hint` for the run follows it. |
| `parked` | none | The machine was restored and stopped after a run. |
| `log` | `level`, `message`, `run` or null | The agent's LOG and the host's own notes. For developers. |
| `stop-answered` | `run`; `ms` or null | Diagnostics: how long after STOP the stopped run's EXIT came, null when the host parked without it. |
| `rootfs-fetched` | `path`, `bytes`, `ms` | Diagnostics: a rootfs file loaded over the network. |
| `rootfs-cached` | `path`, `bytes`, `ms` | Diagnostics: a rootfs file read from the Cache API, which an earlier run fetched. |
| `fetch-failed` | `path`, `url`, `status`, `message`, `attempts` | Diagnostics: a rootfs file that could not be loaded. The run ends as `fetch` 50 ms later. |

A listener SHOULD ignore a `type` it does not know.

**Why a run ended** (`ended.reason`, README 9.3):

| `reason` | |
|---|---|
| `exit` | The program ended by itself, an uncaught exception included (code 1, the traceback on stderr). |
| `closed` | The close button ended it: the window did not take `WM_DELETE_WINDOW`. |
| `oom` | The guest ran out of memory for it. |
| `stopped` | `stop()`, a newer `run()`, or `destroy()`. |
| `unresponsive` | The watchdog: the guest stopped answering. |
| `fetch` | A file the program needed could not be loaded. What it printed before still arrives. |
| `broken` | The agent refused the run, restarted or sent an invalid message about it, or the VM is failed or destroyed. |

**Why the VM failed** (`failed.reason`):

| `reason` | |
|---|---|
| `network` | The manifest, v86 or the state could not be downloaded. The next `load()` or `run()` tries again. |
| `incompatible` | The image speaks another protocol version than the page. Only a deploy of both fixes it. |
| `fetch` | A rootfs file the load needed could not be loaded. The next `load()` or `run()` tries again. |
| `unresponsive` | The guest did not answer, twice in a row. |
| `broken` | Anything else: the emulator did not start, the snapshot did not restore, or the image had no warm interpreter. |
| `replaced` | A newer `openVm()` on this page destroyed this `Vm`. Only a new `openVm()` gives the page a machine again. |

A listener MUST treat a `failed.reason` or an `ended.reason` it does not know as
`broken`: later versions may add reasons, and none of them is the student's doing.

### `VmScreen`

`createVmScreen({document, width, height, onFocus})` returns one. `width` and
`height` are the guest's screen, 800 × 600 by default; `onFocus({viewId, inside})`
reports DOM focus entering or leaving a view's element.

| Member | |
|---|---|
| `viewElement(viewId)` | Flutter's platform-view factory: a new element for view `viewId`. The screen moves into it, as the newest view. |
| `releaseView(viewId)` | Flutter disposed view `viewId`. If it held the screen, the newest view left takes it. |
| `viewId` | The view the screen is in, or null. |
| `scale` | CSS pixels per guest pixel, as the screen is drawn now. |
| `setViewport({x, y, width, height, scale})` | Shows only that part of the screen, in guest pixels and clamped to it, at `scale`. Without a scale the part fits the view; with no arguments it is the whole screen, which is where it starts. A caller that passes a scale MUST size the view to the part times the scale: the view clips to its own box. |
| `viewport` | The part shown, `{x, y, width, height}` in guest pixels. |
| `setKeyboardEnabled(on)`, `setMouseEnabled(on)` | Whether keys and the mouse reach the guest. Both start off: v86 listens for keys on the whole window. |
| `focusElement()` | Moves DOM focus into the view that shows the screen. |
| `releaseFocus()` | Moves DOM focus to the enclosing `flutter-view`, without the blur Flutter would read as its whole view losing focus. |
| `setBackground(css)` | The colour around the screen where the view is larger than it. |
| `destroy()` | Releases every view. |
| `container`, `attach(emulator)`, `detach()` | For `openVm()`, which hands the container to v86 and attaches the machine; not for the app. |

## The screen

`web/vm/vm_screen.js` is the display in the page. v86 draws into one element
tree; Flutter may hold two platform views of it at once, because a layout
switch or a route replacement builds the new view before it disposes the old.
So every view id gets an element of its own from `viewElement(viewId)`, the view
factory, and the one screen moves into the newest; `releaseView(viewId)` hands it
back to the newest left. Handing every view the same element would let the old
view's teardown take it from the new one.

It shows one part of the screen, the viewport: the app asks for the region
around the program's windows at the scale its frame drew them, and without a
scale the part is fitted to its view, snapping to 1 within 2 %. The screen box
v86 draws into is the whole screen at that scale, and it sits at a negative
offset inside a crop box of its own, `.icc-vm-crop`, which is exactly the part
shown and clips the rest. v86 maps a pointer through the screen box's
`getBoundingClientRect()`, which includes that offset, so a click lands on the
guest pixel under it at any crop and scale with nothing added to it; clicks
outside the crop never reach the canvas at all. A stylesheet makes the canvas
fill the box whatever inline size v86 gives it: v86 divides its own scale by a
fractional devicePixelRatio, which would leave the canvas smaller than the box.
It also decides `image-rendering`, with `!important`, because v86 sets
`pixelated` inline whenever its own scale is whole, which here it always is:
nearest-neighbour only where a guest pixel covers whole device pixels, and a
resample anywhere else, where nearest-neighbour would drop a one-pixel line of a
screen drawn smaller. Keys and the mouse start
disabled, since v86 listens for keys on the whole window, and `attach()` applies
what `setKeyboardEnabled` and `setMouseEnabled` asked for again once the CPU
runs. `releaseFocus()` moves DOM focus to the enclosing `flutter-view` rather
than blurring, which Flutter would read as its whole view losing focus.

It is tested against a fake DOM (`vm/tools/test/vm_screen.test.mjs`), and the
bench drives it in headless Chrome, real clicks and keys included ("Checks in
the browser").

## Flutter side

The page is `TkinterScreen` at `/learn-python/tkinter`, in
`lib/views/tkinter_screen/`. Its machine half, which a project on
`runtime: tkinter` holds as well, is the session in `lib/views/components/vm/`,
and the Dart half of the host is `lib/services/vm/`. CLAUDE.md's *The Tkinter
page and the VM* has the page's rules; this is how it binds to the Host API
above.

| File | |
|---|---|
| `vm_runtime.dart` | `VmRuntime`, `VmProgram`, `VmExit`, `VmWindow` and the events, `VmLoadProgress` and `VmLoadPhase` among them, and the conditional import |
| `vm_runtime_stub.dart` | Every platform but the web, `flutter test` included: `isSupported` is false and nothing throws |
| `vm_runtime_web.dart` | `WebVmRuntime`: imports `vm/vm_host.js` and `vm/vm_screen.js` and opens the VM on `vm/image/` |
| `vm_host_event.dart` | `parseHostEvent`: one host event, converted with `dartify()`, as a `VmEvent` |

- **What it uses.** `openVm({baseUrl, onEvent, screen})`, `load()`, `run({files,
  entry})` with `main.py` as UTF-8 bytes, `stop()`, `closeWindow(xid)` and
  `destroy()`; `createVmScreen({width, height, onFocus})` and the screen's
  `viewElement`, `releaseView`, `setViewport`, `setKeyboardEnabled`,
  `setMouseEnabled`, `focusElement`, `releaseFocus`, `setBackground` and
  `destroy`. Of the events it
  reads `progress` (every field, as `VmLoadProgress`), `ready`, `failed`,
  `started`, `output`, `window`, `hint` (`tk_no_mainloop` only) and `ended`. `log`
  goes to the browser console at debug level, and everything else is ignored. An
  `ended` or `failed` reason it does not know counts as `broken`, which the page
  never puts on the student; a `phase` it does not know counts as `download`. It
  does not call `prefetchBundle()` yet: what starts a download before the page
  opens, and the catalog card that shows it, are a design of their own.
- **Run ids are the runtime's own.** A run asked for before the host module has
  even been imported needs an id at once, so `WebVmRuntime` numbers its runs and
  maps the host's ids onto them. A run ends on its `ended` event, and on
  `run().ended` as well: a VM that failed after it was ready ends a run inside
  `run()`, before its host id is known.
- **One view factory per page**, `icc-vm-display`. Every `HtmlElementView` carries
  its runtime's serial as creation parameters, so a view built while a replaced
  page is still being disposed asks the right runtime. The factory returns a
  holder `div` of our own, sized 100 %, around `screen.viewElement(viewId)`;
  `VmDisplay` calls `releaseView` when the view goes.
- **`releaseFocus()` only while DOM focus is on the screen.** The Dart side checks
  `document.activeElement` first: focus that has already moved on to a text
  field's hidden input must not be taken from it.
- **The page disposes the runtime when it goes**, which destroys the `Vm` and the
  screen. The next visit loads again, from the Cache API. A session whose `Vm` a
  newer one's `openVm()` destroyed builds a new runtime once that newer session
  is disposed, as Retry would: the newest `VmSessionController` still standing
  holds the machine, and one that goes hands it to the one under it.
- **A build says whether it has a bundle.** `--dart-define=ICC_VM_IMAGE=true`
  turns the page on (`lib/services/vm/vm_image.dart`), and the `tkinter`
  feature toggle then shows it (`tkinterShown`); without the define the catalog
  offers no card, `createVmRuntime()` returns the stub and the page says the
  machine is not in this version of the app, downloading nothing. A build that
  passes it without `web/vm/image/` fails the load as `network` with the
  manifest's 404 in its message, which the failure card keeps folded under
  "Technical details".
- **The failure card words the reason, never the message.** `failed`'s `reason`
  picks the card's title and body in the page's language, `replaced` included
  (`VmFailure.replaced`: "Another page took over the machine"). The
  `message` is the host's English, for whoever helps the student, so `NoticeCard`
  folds it under a toggle (`detailLabel`) rather than print it under a Dutch
  sentence.
- **Tab is the program's while the display is there**, which is while a run is:
  `VmDisplay.holdsTab` is on, and the frame states the way out, Escape then Tab,
  whenever the display has the keyboard. The flag is still a flag because a
  display without a program is a state the widget can be built in, and a Tab
  into a guest that has nothing to give it to is what it is for.
- **A load that fails without a `failed` event still fails the page.** A `Vm`
  that a newer `openVm()` destroyed emits `failed` (`replaced`) once, and a later
  `load()` on it resolves as failed and emits nothing, so `WebVmRuntime` emits
  `VmFailed(broken)` itself whenever a load resolves failed and no `failed` event
  came first. Retry never loads that `Vm` again: it throws the runtime away and
  builds a new one, whose load opens a new `Vm`.
- **Only Retry leaves a failure.** The view model takes a byte count only while
  the machine is loading. The host sends none after `failed` any more, but the
  page does not count on it: a state that answered 404 at once, while the wasm
  still streamed, put the page back on its loading panel for good, with no card
  and no Retry.
- **The editor does not take the keyboard as the page opens.** Tab indents in it,
  so a keyboard user who started there had to find the way out before reaching
  Run or the failure card. Escape then Tab leaves it, as it leaves the display,
  and the editor's strip says so while it has focus (`EscapeThenTabExit`).

- **The display's `Focus` adds nothing to the semantics tree.** With semantics on,
  which a screen reader turns on, Flutter web moves DOM focus onto the element of
  whichever semantics node is focused. The display's node took DOM focus from the
  view the moment Run gave it Flutter focus, the view's `focusout` turned the
  guest's keyboard off, and nothing typed reached the program, after Run or after
  a click. Found in Chrome; `tkinter_widgets_test.dart` now holds it.
- **One display, whatever the page does around it.** A second `VmDisplay` built
  for the same machine binds first, and the old one's unbind then turned the
  keyboard off under a node that still had focus, so no click brought it back.
  The page keys the display with `GlobalObjectKey(controller.display)`, which
  moves it and its platform view instead. A display also turns off only a
  binding it still owns, and a press turns the keyboard back on for a node that
  kept focus, but those alone do not hold in Chrome: a build with the old key
  and both of them lost DOM focus to `body` as the old view went, and the leave
  hint with it. A probe that types into a Tk Entry across 1440 → 900 → 1440 got
  every key through with the global key and none after the first switch without
  it. The page had two layouts then, split and stacked; it has one now, and the
  key stays because the rule is about the machine, not the layout.
- **The program is a dialog, and the page behind it is blocked three ways.**
  `ProgramDialog` is built while, and only while, a run is: the editor has the
  page's whole column, and the display and its platform view are created on Run
  and released when the run ends. The dim absorbs the pointer, `ExcludeFocus`
  keeps Tab inside the dialog and the bar, and `BlockSemantics` drops the page
  from the semantics tree. The last one is not manners: Flutter places a
  semantics element by its rect and puts the semantics host over the platform
  view, so with semantics on the editor's own `flt-tappable` element covered the
  display. v86 walks up from a mouse event's target to its screen container and
  ignores anything outside it (`may_handle` in `libv86`), so every click on the
  program was lost — only with a screen reader on, and silently. The checks now
  drive the crop page, the survey and the over-the-display page with semantics
  on for that reason.
- **Run asks for the keyboard before there is anything to give it to.** The view
  calls `requestFocus()` in the same gesture that starts the run, a frame before
  the display is built; a `FocusNode` asked while it is out of the tree takes
  focus as it is reparented, so Flutter focus lands. DOM focus does not:
  `focusElement()` reaches the view's element before the engine has put it in the
  page, and `element.focus()` on an unconnected element does nothing. `VmScreen`
  therefore keeps the request and retries it for up to ten animation frames,
  dropping it if `releaseFocus()` comes first.
- **The page shows the program's windows, not the screen.** `windowRegion`
  (`vm_session_view_model.dart`) is the smallest rectangle around every
  mapped top-level in the run's latest WINDOW, each clipped to the 800 × 600
  screen first. A dialog widens it to hold both, closing the dialog shrinks it
  back, and a window that moves or resizes moves it in the same frame, with no
  animation: the emulator shares the thread one would take. `WindowFrame` hugs
  the region at `displayScale`, never above 1 and on whole device pixels where
  that costs little, and is never narrower than 320, where the region sits
  centred, so the strip keeps room for a title beside the way out and the close
  button. The way out is the short "Esc, then Tab to leave" and gets its room
  before the title does. `VmDisplay` hands the region and the scale to
  `VmDisplayBinding.showRegion`, which is `VmScreen.setViewport`, and the frame
  lays the display out at exactly the region times the scale.
- **The loading panel says what the student waits for, and nothing in it
  moves by itself.** `VmLoadPanel` names the step in its title and in a row of
  three (download, unpack, start, the done ones ticked), with a bar and "4,7 van
  17,4 MB" under it. Once the download has measured them, a second line adds the
  speed ("2,3 MB/s", or kB/s under 1 MB/s) and the time left, rounded coarsely
  so a smoothed estimate that still moves by a second does not change the words:
  "bijna klaar" under 5 s, up to 5 s under a minute, whole minutes past one. A
  stalled download quotes no speed. Under them is at most one note, most pressing
  first: the connection is slow or gone and the download carries on by itself;
  the browser cannot keep the machine; the browser guesses the line is slow (only
  until a speed is measured); the download carries on where the last one
  stopped. The note is a live region. The byte line is laid out before the first
  report, and the speed line and the note each hold the room of their longest
  wording, so nothing moves as they arrive; with the app's own fonts the panel
  fits the frame's 480 × 300 stand-in in both languages
  (`test/views/vm_load_panel_fit_test.dart`, which loads them, in a file of its
  own because a loaded font stays loaded for the rest of the process).
- **No window, a stand-in of a fixed size.** Before the first run, until a run
  maps a window, and after one that printed only or has ended, the frame takes
  480 × 300, the loading panel's size too, so it does not jump when the machine
  is ready. `NoWindowPanel` covers the display then rather than replacing it:
  Run gives the display the keyboard before any window exists, and a display
  taken out of the tree would take the keyboard with it. It ignores the pointer,
  so a press on it still reaches the display and takes the keyboard, as a press
  on the empty screen did.

It is tested under `flutter test` against a fake runtime and a fake platform view
(`test/services/vm_host_event_test.dart`, `test/views/tkinter_controller_test.dart`,
`test/views/tkinter_widgets_test.dart`, `test/views/vm_load_panel_fit_test.dart`
and, for a project on the machine, `test/views/project_screen_test.dart`),
and in headless Chrome by `just check-vm-app` ("The app in Chrome", under
"Measurements").

## The machine

`vm/image/machine.mjs` is the emulated machine: 128 MiB of RAM, 4 MiB of VGA
memory, the second UART, an 800 × 600 screen and the kernel command line. A
saved state restores only into the settings it was saved with, so everything
that boots the image or writes its manifest reads them from that one file.

**128 MiB rather than 96, so that a full-HD Canvas draws.** Xorg allocates a
program's pixmaps outside the run's cgroup, and a 1920 × 1080 Canvas takes it
8,192 kB over its warm size ("The run's memory"). That room has to come out of the
free memory the run's budget is measured from, or the kernel finds it by evicting
files the guest maps, which the run then fetches again. At 96 MiB there is not
enough for both. `build-state.mjs --memory-mib 96 --out DIR` built the same
sources at 96 MiB (image `b457a74096cc05c2`): after PREPARE it had 12,204 kB of
free memory and unmapped page cache above the high watermarks, 10,156 kB once the
kernel's 2 MiB is set aside. What each way of giving Xorg its room leaves a run:

| Xorg's room | The run's budget at 96 MiB | At 128 MiB |
|---|---:|---:|
| 8 MiB inside the budget, the old way | 10,156 kB; a 1920 × 1080 Canvas is a BadAlloc, and a run near its budget has Xorg evict mapped files | |
| 9 MiB outside it: a full-HD Canvas and 1 MiB spare | 940 kB | |
| 16 MiB outside it, as shipped | 0 kB | 25,604 to 26,304 kB |

Both columns were measured with Alpine's kernel. The build's own kernel keeps
14 MiB less of the guest's RAM, so the shipped image's budget is 40,284 kB
("The kernel"); the choice between the three rows is unchanged.

940 kB is less than `sandbox.py` takes, and a run's files come out of the budget
too, so raising Xorg's cap at 96 MiB was no option. The 0 kB build is one PREPARE
refuses now, since the budget has a 16 MiB floor ("The run's memory"). Below, what 128 MiB costs
beside that 96 MiB build, and beside `7580ed6dc2732d62`, the last image shipped
at 96 MiB (an older agent, and no zstd checksum). Node 26 at 1× on the M1, one
process alternating the three bundles, medians of 6 loads and 30 parks each, in
two runs; in the first, the 128 MiB bundle was `f80cad4ea7348500`, built from
the same sources but for one comment:

| | 96 MiB, `7580ed6dc2732d62` | 96 MiB, same sources | 128 MiB, `7668214b5d9fad5e` |
|---|---:|---:|---:|
| `state.bin.zst` | 20,318,542 B | 20,138,574 B | 20,619,195 B (19.66 MiB) |
| The raw state, which the page keeps for parks | 75,242,108 B | 74,820,108 B | 75,644,428 B |
| v86's wasm memory | 109.3 MiB | 109.3 MiB | 141.3 MiB |
| Decompressing the state | 106–111 ms | 111–113 ms | 108–112 ms |
| `openVm().load()` to `ready`, from disk | 165–172 ms | 198–201 ms | 196–200 ms |
| Restore, fresh host | 23.1–23.8 ms | 23.7–23.9 ms | 25.8–26.4 ms |
| Restore, park | 16.1–16.2 ms | 16.0–16.1 ms | 16.7–17.1 ms |
| Restore to READY, park | 21.9 ms | 21.8 ms | 22.5–23.0 ms |

The 32 MiB cost 32 MiB of wasm memory, 1 to 3 ms a restore (v86 zeroes the
whole of guest RAM before it copies the saved pages in), and up to 5 % of the
state: v86 saves only the pages that are not zero, and most of the 32 MiB is
free memory PREPARE zeroes. A build at 128 MiB came out at 20,619,195 to
21,165,655 B: over the 20 MiB target (20,971,520 B) at worst, under the 21 MiB
(22,020,096 B) this choice was held to. The 30 ms that
`load()` gained since `7580ed6dc2732d62` are not the RAM, since the 96 MiB build
of the same sources has them too: READY arrives as soon as before, and the
host's `pause()` after it takes the rest. In Chrome, `just check-vm-app` found
the Tkinter page parked at 331.3 MiB of heap and a 433 MiB renderer, against
298.6 and 400 at 96 MiB ("The app in Chrome"); the bench's own figures in
"Measurements" are for 96 MiB, except the shipped image's run at the end of
"final".

The command line, beyond v86's own Alpine recipe:

- **`rootflags=…,ignoreqv`.** v86's 9p server reports every file's qid version
  as 0, and Linux 6.12 takes version 0 to mean "this file cannot be cached": each
  open file is read directly from the server and the page cache never holds its
  data. v86 also drops a file from its own cache whenever the guest closes it, so
  every exec fetched its binary again. A boot fetched 5,991 files (319 MB, 272 of
  them `ld-musl`) without `ignoreqv` and 139 (8.4 MB) with it, and a second run of
  `python3` fetches nothing. The price is that the guest can keep a stale copy of a
  file the host rewrites under the same name, which is why run files get new names.
- **`video=800x600`.** The X screen size. `bochs-drm` binds v86's VGA and its fbdev
  emulation starts in this mode; the fbdev X driver cannot change it.
- **`nowatchdog nosoftlockup rcupdate.rcu_cpu_stall_suppress=1`.** v86's TSC
  keeps running while its CPU is stopped, so a resume would look like a hang to
  the lockup and stall detectors. The host now stops the TSC with the CPU, so
  nothing should trip them; the corpus's `park-detectors` case switches them
  back on and pauses a run for 15 minutes to show it.
- **`mitigations=off`.** Page-table isolation and retpolines defend against
  speculative-execution flaws, and v86's CPU does not speculate. Measured with
  20,000 `os.getpid()` calls: 0.13–0.18 s with it, 0.42–0.70 s without, while a
  pure Python loop took the same time either way. The host was shared with other
  builds during both runs, so treat the ratio as the finding, not the numbers.
- **`init_on_free=1`.** A freed page keeps whatever the last owner wrote, and v86
  saves every page that is not zero, so the state carried the rubble of the boot.
  Zeroing on free makes the pages that PREPARE's own zero-fill cannot reach
  compress alike. It took 1.2 MB off the 3.22 state and 1.67 MB off 3.24, and it
  narrowed the build-to-build spread from 0.5 to 0.19 MB, which is what makes a
  size claim about this image measurable at all. No slowdown showed over the
  corpus (first-window sums 5,989 against 6,057 ms). It does not replace the
  zero-fill: with both, a no-fill build measured the same size, but that was one
  build and the fill also sets the watermark trap straight ("Traps").

**4 MiB is the least VGA memory `bochs-drm` accepts.** At 2 MiB it logs "less than
4 MB video memory, ignoring device" and there is no `/dev/fb0` at all. At 4 MiB it
rejects any mode whose frame does not fit twice, so `video=1024x768` falls back to
800 × 600 with "User-defined mode not supported". 800 × 600 is the largest screen
4 MiB allows.

## The kernel

The guest boots a kernel this build makes, not the `linux-virt` binary Alpine
ships. The Dockerfile's `kernel-config` stage takes Alpine's config and its
kernel version out of the package; the `kernel` stage downloads that version from
kernel.org, checks it against the `sha256sums.asc` beside it, runs
`vm/image/kernel/configure.sh` over the config and builds it. Nothing is
committed: `just build-vm-image` reproduces the kernel, and the tarball lives in
a Docker cache mount so the 145 MB tree never becomes a layer.

**What comes out is a kernel for one machine.** v86 has one CPU and no ACPI, the
root is 9p so there is no block layer, and with `CONFIG_MODULES` off everything
the guest used to load is built in. That last one is why the image needs neither
`mkinitfs` nor `/lib/modules`, and why the kernel mounts the root itself. The
rest is code a v86 guest cannot reach: tracing, BPF, audit, LSMs, IPv6,
netfilter, the other hypervisors' guest support, sound and USB.

Measured on Alpine 3.24.2, the same tree either way, into a throwaway build
directory:

| | Alpine's `linux-virt` | This build |
|---|---:|---:|
| `state.bin.zst`, zstd -19 | 21,597,554 B | 17,221,363 B |
| Kernel text, rodata, data and bss in RAM | 14.1 MB | 7.7 MB |
| `MemAvailable` after PREPARE | 58,952 kB | 69,556 kB |
| A run's memory budget | 28,792 kB | 40,288 kB |
| `rootfs-flat/` | 4,290 blobs | 3,332 blobs |
| apk packages | 114 | 102 |
| Restore to READY, fresh host | 471 ms | 168 ms |

The state is the point: 4.4 MB, a fifth of the download. The 11 MB of run budget
is the second prize, and it is free — it is the RAM the kernel stopped holding.
First windows came out 16 % faster and v86's decoder 22 % faster on 3.22, where
that was measured against replicates.

The build costs about 4.5 min cold on an M1 (`-j8`, clang cross-compiling for
i386 on the build machine's own architecture, since under QEMU it would take an
hour) and nothing afterwards, because only a new Alpine release changes the
stage's inputs.

**What it costs is that kernel updates are ours.** Alpine's are not, any more.
The pin moves the kernel with it, so `vm/build/kernel.txt` names the version, the
source URL and its checksum, and `vm/build/kernel.config` is what was built. Read
both when the pin moves.

**`configure.sh` fails the build rather than boot without something.** Its
`NEEDED` list is what the guest cannot do without, and after two
`olddefconfig` passes it checks every entry is still `=y`. Two passes because
`olddefconfig` can turn a new option's default back on. The check is there
because a kernel can move an option under a different parent and `olddefconfig`
drops it without a word: **which helpers `DRM_BOCHS` selects already changed
between 6.12 and 6.18** (TTM and VRAM, then GEM SHMEM), which is exactly the
failure that would otherwise be a black screen.

It is built with clang, since `LLVM=1 ARCH=i386` cross-compiles without a
cross-toolchain, while Alpine builds its own with GCC. Every size above is an
end-to-end measurement of this build, so the compiler is part of what was
measured, not a variable left over.

A config cut further for size (`-Os`, no `KALLSYMS`, no stack protector, no CPU
mitigations, no perf, PSI, net or user namespaces) took another 0.40 MB off the
state and made first windows 4 % slower, with oopses that name no symbols. Not
taken: it trades what is left of the guest's own hardening for a fifth of a
percent of the download.

## Inside the image

**Input without udev.** Alpine runs mdev, and Xorg's hotplug needs udev's
properties, so on its own Xorg opens no input devices at all. `10-v86.conf` turns
hotplug off and names three evdev devices. `/usr/lib/icc/mdev-input`, an mdev hook
added to `/etc/mdev.conf` for every event device, gives them fixed names under
`/dev/input/`, since event numbers follow probe order:

| name | device |
|---|---|
| `icc-keyboard` | the AT keyboard |
| `icc-pointer` | the VMMouse's absolute half: motion and buttons |
| `icc-wheel` | the VMMouse's relative half, which is where the kernel reports the wheel |

The keymap is US only.

**Nothing on the display but X.** `/etc/inittab` has no getty on any terminal, and
no `ctrlaltdel` entry, so busybox init ignores Ctrl+Alt+Del. `10-v86.conf` sets
`DontVTSwitch` and `DontZap`, and `kernel.sysrq = 0`, because every key a student
presses reaches the guest.

**The console shows errors.** Alpine's `dmesg` service sets the console level
from `/etc/conf.d/dmesg`, whose `dmesg_level="1"` let only emergencies through,
so the ttyS0 tail the host keeps for failure reports stayed empty across an OOM
kill. The image ships `dmesg_level="4"`: KERN_ERR and worse reach ttyS0, an OOM
kill's `Out of memory: Killed process` line among them, which the corpus's `oom`
case checks.

**No blanking and no DPMS.** A resume after a long park looks like minutes of idle
time. The screen saver timeouts are zero and DPMS is off in `10-v86.conf`, so it
does not depend on Xorg being started with `-s 0 -dpms`, and the check asks the
running server through Xlib.

**Unchecked-hash pycs.** Alpine ships checked-hash pycs, so each import also reads
and hashes the `.py` beside the pyc, and over 9p that read is a fetch. The
Dockerfile recompiles the stdlib with `--invalidation-mode unchecked-hash` and
fails the build if any pyc is left in another mode.

**What is left out.** No syslog, no `hwdrivers`, and nothing that loads a module,
because the kernel has no loader: `mkinitfs` and `/lib/modules` are both gone
with it ("The kernel"). The spike's packages `agetty`, `xinit`,
`xf86-video-vesa` and `xf86-input-libinput` are gone, and so are `ensurepip`,
`lib2to3`, `turtledemo`, Python's build config and optimised pycs. Mesa's
Gallium drivers and LLVM are deleted after install, with `glx` and `glamoregl`
disabled. `busybox-suid`, which `alpine-base` would bring, is never installed:
the Dockerfile names `alpine-base`'s other dependencies instead. tzdata is
complete: 598 zones.

**And then a second pass, for the release rather than the student.** A file the
guest never reads is never fetched, so deleting one saves a student almost
nothing — 24 KB of 9p inode table across the whole list. It is the release asset
and the deploy that carry the rootfs whole, and that is 15.9 MB of it: the
libraries only Mesa's GL, the SPIR-V tools or each other link, those tools, the
bitmap fonts but for the cursor and the 6x13 Xorg falls back to, the Tcl packages
Tk never loads, and CPython's own test modules.

A delete list rots, so the same step ends by running `scanelf` over everything
left and resolving every library each ELF file still names. A package that starts
linking one of these stops the build there, rather than a student's run. Python's
`.py` sources stay, because a traceback quotes the stdlib lines it names, and so
do the CJK codecs.

**The student.** uid 1000, `/home/student`, no password and `/sbin/nologin`.
`/icc/in` is root's, mode 0700: the host drops a run's files there over 9p and only
the agent reads them.

### Turtle

`turtle` is in the image, from Alpine's `python3-tkinter`; only `turtledemo` is
deleted. The prelude imports it during the warm-up, so a run reads none of it over
9p, and the corpus's `turtle` case draws with it.

**It is slow, and most of that is turtle's own pause.** Turtle animates a line or a
turn as a series of frames and sleeps `delay` ms after each, 10 by default. At the
default speed of 3, a line of 150 pixels is 13 frames and a turn of 144° is 17, so
a five-pointed star is 150 frames: 1.5 s of sleep on any machine before anything
is drawn. The VM adds its redrawing to that. Measured in one run on image
`45a388e7a3e9bc90`:

| Drawing | Time |
|---|---:|
| `Screen()`, the window | 0.67 s |
| star, speed 3 and delay 10, the defaults | 3.57 s |
| star, speed 3, delay 0 | 1.25 s |
| star, speed 0, delay 10 | 0.20 s |
| star, speed 0, delay 0 | 0.05 s |
| star, `tracer(0)` then `update()` | 0.02 s |
| spiral of 100 lines, speed 0, delay 0 | 1.65 s |
| spiral of 100 lines, `tracer(0)` then `update()` | 0.05 s |

**A program that draws many lines turns the animation off.** `screen.tracer(0)`
before the drawing and `screen.update()` after it draw everything in one frame.
`speed(0)` is not enough: it skips the frames within a line but still redraws once
per line, and 100 lines take 1.65 s. A small drawing whose point is watching the
turtle walk can keep the defaults.

**The page sets two of turtle's defaults, not the image.** Turtle reads
`turtle._CFG` when the first `Screen()` is made, so the page's setup
(`icc_setup.py`, "The warm interpreter") changes it before the program starts. Its
default, `EditorSettingsBase.defaultTkinterSetup`, sets two values, and the code
editor settings can change or empty it:

- `delay = 0`. A star then takes 1.1 to 1.4 s once turtle has drawn before, against
  at least 1.5 s of sleep on a PC. The first drawing of a run takes about a second
  longer (2.2 s for the star) whatever the delay; drawing something with turtle in
  the warm-up might take that away, and has not been tried. Big drawings still need
  `tracer(0)`.
- `width = 600` and `height = 500`. turtle's own default is half the screen's width
  and three quarters of its height, 400 × 450 on the 800 × 600 screen, narrower than
  its 400-pixel canvas once the border is taken off, so the window showed both
  scroll bars. The window's size costs no speed: the star took as long at 400 × 450.

A `turtle.cfg` is not read at all, beside `turtle.py` or beside the program,
because the prelude imported turtle before either could matter.

**`turtle.done()` runs a main loop the prelude does not see.** It calls
`_tkinter`'s own `mainloop()` on the canvas's interpreter, past the
`tkinter.Misc.mainloop` that `watch_mainloop` wraps, so `looped` stays false. No
`tk_no_mainloop` hint follows, because `done()` returns only once the root is
destroyed and the hint asks whether a root is still open. The corpus case holds
that.

### Known noise in the Xorg log

`(EE) FBDEV(0): FBIOPUTCMAP: Invalid argument`, 240 times per palette load (720
by the end of a check). In TrueColor, DRM's fbdev emulation takes a colormap only
for the console's 16 entries, so the other 240 of fbdev's 256 fail. A TrueColor
visual never reads the colormap; the check reads a Tk colour back out of v86's
framebuffer to prove it. The modesetting driver drives KMS directly and may not
hit this at all; it is untried.

## The checks

`just check-vm-image` boots `vm/build/` in v86 under Node and runs 24 checks,
writing them to `vm/build/check-image.json`. It exits 1 if any fails. Flags such
as `--vga-mib 8` or `--cmdline "…"` override `machine.mjs` for one run.

The image has no shell, so `vm/tools/lib/image-boot.mjs` adds one: before the
guest starts, it appends `ttyS0::respawn:-/bin/sh` to its own in-memory copy of
`/etc/inittab`. What is checked is the image as it ships, plus one line that only
exists in the checker's RAM. The same module records every rootfs file v86 loads.

What it holds:

- no getty, syslogd or klogd running, and no getty in `inittab`;
- the student, `/icc/in`, complete tzdata;
- `import random`, and the modules students use most, fetch pycs and never a `.py`;
  no `.py` is fetched over the whole session;
- a second `python3` fetches nothing;
- Xorg starts, the root window is 800 × 600 × 24, all three input devices are open,
  and the log has no errors besides `FBIOPUTCMAP`;
- the kernel has no module loader and the image no `/lib/modules`, which is what
  says the build's own kernel booted and not Alpine's ("The kernel");
- the server reports a screen saver timeout of 0 and no DPMS;
- a Tk program running as the student opens, sees an 800 × 600 screen, and its
  colours reach v86's framebuffer, which is what the browser draws;
- a synthetic absolute click reaches a Tk Button, scancodes typed into an Entry
  the pointer clicked arrive as `hi`, and the wheel scrolls a Listbox;
- no lockup, stall or oops in `dmesg`.

This check starts Xorg and the program itself, from a shell, with no agent in
the way, so it clicks into the Entry before typing. Where keys go when nothing
was clicked is the agent's focus rule, which the corpus covers.

Every result is polled for rather than read after a fixed sleep: a host sleep
says nothing about how far the guest got on a loaded machine.

## The corpus

`just check-vm-corpus` runs `vm/tools/corpus.mjs`: the student programs in
`vm/tools/corpus/` through `openVm()` on the bundle in `web/vm/image/`, the same
module and bundle a page loads. It drives them the way a student would, with
clicks and US-layout scancodes on v86's input bus and the close button through
`closeWindow()`, and reads pixels back out of v86's framebuffer, which is what
the browser draws. Every case ends parked, so each starts from the snapshot. It
writes `vm/build/corpus.json` and exits 1 if a case failed.

| Case | Program | What it holds |
|---|---|---|
| `label` | `label.py` | The window's colour is on screen; CLOSE ends `mainloop()` and the program exits 0 |
| `button` | `button.py` | Two synthetic clicks run the Button's command twice |
| `entry` | `entry.py` | Keys typed with nothing clicked reach the newest window's Entry; after a click into the first window they reach its Entry (F4) |
| `canvas` | `canvas.py` | A rectangle, an oval and bold text in their colours |
| `ttk` | `ttk_widgets.py` | Notebook, Combobox, Scale, Progressbar, Spinbox and Treeview in `clam`, no stderr, CLOSE |
| `messagebox-close` | `messagebox_close.py` | CLOSE on an `askokcancel` makes it answer `False` |
| `withdraw-dialog` | `withdraw_dialog.py` | `root.withdraw()` then `showinfo`: only the dialog is mapped in any WINDOW, and the screen where the root would be stays black (F1) |
| `askstring` | `askstring.py` | Typing into `simpledialog.askstring` with nothing clicked (F4) |
| `animation` | `animation.py` | An `after(50)` loop: steps per second, the guest's monotonic clock against the host's, the wall clock |
| `dice` | `dice.py` | Three runs from one snapshot roll different dice and read different `os.urandom` |
| `clock` | `clock.py` | `time.time()` within 2 s of the host, and the host's UTC offset |
| `class-app` | `app_class.py` | `class App(tk.Tk)` is the `root` window, at its geometry |
| `grid` | `grid.py` | A 3 × 3 grid of coloured Labels, cell by cell |
| `photo` | `photo.py` | A PNG the run sends as a second file, shown with `PhotoImage` |
| `setup` | inline | `icc_setup.py` runs before the program, in the same interpreter, and is gone from the work directory when the program starts; one that raises prints its traceback, quoting its own line, and the program still runs and exits 0 |
| `turtle` | `turtle_line.py` | A line drawn with `turtle`, in its colour, with no rootfs fetch; CLOSE ends `turtle.done()`, the program exits 0, and no `tk_no_mainloop` hint comes although the prelude never sees that main loop ("Turtle") |
| `traceback` | `exception.py` | Three frames, all of `main.py`, and nothing of the prelude |
| `stop` | `busy.py` | `while True: pass`: `ended` at once, EXIT within 50 ms of STOP, then the park |
| `print-loop` | `print_loop.py` | 1 MiB printed, exactly 262,144 bytes forwarded, `truncated` |
| `no-mainloop` | `no_mainloop.py` | The `tk_no_mainloop` hint before the end |
| `sandbox` | `sandbox.py` | uid 1000; `/icc/in`, ttyS1, the agent's signals and `/proc` files, `/root` and `setuid` refused; `NoNewPrivs` 1, `su` fails, and no setuid or setgid file where programs are found; `/` read-only; `/tmp` and the work directory writable; in the `run` cgroup, which it cannot leave; `/dev/shm` 8 MiB; a forked child has no status pipe; 2,000 hint lines written to the pipe give at most one HINT |
| `oom` | `oom.py` | Allocating until the kernel steps in ends the run as `oom`, and the kill shows on the console |
| `memory` | `memory.py` | `/dev/shm`, `/tmp` and the home directory are 8 MiB each; filling them and then the heap ends the run as `oom` inside its budget |
| `big-files` | `big_files.py` | 8 MiB of files, the most a run may have: they arrive whole, the run's `memory.max` is the budget less what they take, and allocating until it runs out ends `oom` with no rootfs fetch |
| `window-follows` | `window_follows.py` | Twelve windows mapped 5 to 80 ms apart: each one's WINDOW within 100 ms of its pixels, and the last list at each window's geometry and in the order `wm stackorder` reads from the server |
| `x-grab` | `x_grab.py` | Another client grabs the server through ctypes: a window mapped while the watcher waits on it is listed within 100 ms of the release; through a 6 s grab PONGs keep coming and the run ends normally |
| `big-canvas` | `big_canvas.py` | A 3000 × 3000 Canvas ends the run as `exit` with code 1 and Xlib's `X Error of failed request: BadAlloc` on stderr, which the page matches to say the canvas is too large for the machine; never `unresponsive` |
| `hd-canvas` | `hd_canvas.py` | A 1920 × 1080 Canvas and then a 1600 × 1600 one are drawn, in their colours, with no stderr and exit 0 |
| `near-budget` | `near_budget.py` | A program that fills its budget to within 1.5 MiB draws a 1920 × 1080 Canvas and exits 0, with no rootfs fetch |
| `lingering` | `lingering.py` | Ten forked children still spinning after the program's last line: EXIT within 1.5 s of it |
| `hidden` | `animation.py` | 8 s hidden mid-run: nothing from the run, no `unresponsive`; after it, the animation goes on and the wall clock is right (F2) |
| `fetch-failure` | inline | A rootfs file that 404s ends the run as `fetch`, keeping what it printed first; one that fails with a 503 once is read on the retry; the next run is fine (F3) |
| `agent-stopped` | `label.py` | On the debug bundle: with the agent SIGSTOPped the watchdog ends the run as `unresponsive`; Stop parks without it; the next run is fine |
| `escape` | `escape.py`, `leftovers.py` | On one machine without a restore: a grandchild in a session of its own is gone after its program exits, and after a STOP |
| `cold` | `label.py` | A second RUN on an unrestored machine gets a cold `python3` |
| `park` | inline | 15 minutes parked, then a run: the clock, `after(300)`, no alarm on the console (F6) |
| `park-detectors` | `animation.py` | On the debug bundle, with the lockup and stall detectors switched back on: a run paused 15 minutes mid-animation resumes with no jump in its monotonic clock, the wall clock right after HELLO, and nothing in `dmesg` (F6) |

`park` and `park-detectors` take 15 minutes each and run only when named with
`--only`; they can run in a second process beside the rest. `agent-stopped` and
`park-detectors` need the debug bundle, `just build-vm-state --debug-shell`: a
machine saved with a root shell on ttyS0, which is the only way a check can stop
the agent, and which never ships.

### Results

The table below is Node 26.8 on an M1, v86 0.5.461, image `7668214b5d9fad5e`
(128 MiB, state 20,619,195 B, Alpine 3.22), the page's time zone
`Europe/Amsterdam`. Every image since has run 33 of 33, and the figures that moved
are the memory ones, because the budget moved with the kernel:

| Image | Budget | `near-budget` `memory.max` | `big-files` `memory.max` | `hd-canvas` drawn | `near-budget` drawn | `big-canvas` BadAlloc |
|---|---:|---:|---:|---:|---:|---:|
| `eba47d0db90c25a8` | 25,864 kB | 25,856 kB | 17,664 kB | 1,047 ms | 877 ms | 422 ms |
| `298ac660ab037ae5` (3.22, last) | 26,176 kB | 26,168 kB | 17,976 kB | 1,055 ms | 819 ms | 425 ms |
| `dda79f227497cc75` (shipped) | 40,284 kB | 40,276 kB | 32,084 kB | 914 ms | 1,026 ms | 404 ms |

The shipped image also passed `check-vm-state` 20 of 20 and `check-vm-image` 24 of
24. "Window" is the time from
`run()` to the first WINDOW with the window mapped; "drawn" is the time from `run()` until the
program's own colour is in v86's framebuffer. Both include the resume, HELLO and
writing the files. "Fetches" counts rootfs files loaded from `rootfs/` during the
case; on a page each is a request over the network. "Peak" is the run's cgroup's
`memory.peak`, the most new memory the run held.

| Case | Window (ms) | Drawn (ms) | Rootfs fetches | Peak (kB) | Result |
|---|---:|---:|---:|---:|---|
| label | 284 | 313 | 0 | 256 | pass |
| button | 299 | | 0 | 256 | pass |
| entry | 288 | | 0 | 256 | pass |
| canvas | 304 | 408 | 0 | 256 | pass |
| ttk | 480 | | 0 | 256 | pass |
| messagebox-close | 839 | | 0 | 256 | pass |
| withdraw-dialog | 792 | 864 | 0 | 256 | pass |
| askstring | 249 | | 0 | 256 | pass |
| animation | 167 | | 0 | 256 | pass |
| dice | | | 0 | 256 | pass |
| clock | | | 0 | 256 | pass |
| class-app | 224 | 264 | 0 | 256 | pass |
| grid | 299 | | 0 | 256 | pass |
| photo | 561 | 638 | 0 | 256 | pass |
| traceback | | | 0 | 256 | pass |
| stop | | | 0 | 256 | pass |
| print-loop | | | 0 | 256 | pass |
| no-mainloop | | | 0 | 256 | pass |
| sandbox | | | 1 (`/bin/busybox`, for `su`) | 1,736 | pass |
| oom | | | 0 | 26,000 | pass |
| memory | | | 0 | 26,000 | pass |
| big-files | | | 0 | 17,808 | pass |
| window-follows | | | 0 | 256 | pass |
| x-grab | | | 0 | 256 | pass |
| big-canvas | | | 1 (`XErrorDB`, for the error message) | 256 | pass |
| hd-canvas | | 931 | 0 | 256 | pass |
| near-budget | | 889 | 0 | 24,552 | pass |
| lingering | | | 0 | 6,400 | pass |
| hidden | 159 | | 0 | 256 | pass |
| fetch-failure | | | 1 (the 503's retry) | 256 | pass |
| agent-stopped | | | 1 (`/bin/busybox`, the debug shell's) | 256 | pass |
| escape | | | 20 (the cold `python3` of the programs after the first) | | pass |
| cold | 7,058 | | 76 | | pass |
| park | | | 0 | 256 | pass |
| park-detectors | | | 1 (`/bin/busybox`) | | pass |

What the cases measured besides:

- `stop`: `ended` 0.1 ms after `stop()`, EXIT 5.2 ms after STOP (2.1 to 8.0 ms
  over earlier runs), parked 25 ms after `stop()`.
- `agent-stopped`: the watchdog ended the run 2,927 ms after the SIGSTOP (a PING
  every 2 s and 1 s for its PONG) and parked at 3,033 ms; Stop with the agent
  stopped parked 581 ms after `stop()`, 500 ms of it the grace for an EXIT that
  never came.
- `animation`: 18 steps a second against the 20 an `after(50)` allows, the
  guest's monotonic clock at 94 % of the host's, the wall clock 29 ms off.
- `clock`: 29 ms off the host; `hidden`: 30 ms off after 8 s hidden.
- `print-loop`: 1 MiB printed and 262,144 B forwarded in 4.6 s.
- `cold`: 7.1 s to a window, against 0.28 s warm on the same machine.
- `oom` ends in 0.73 s, 25 MiB allocated, and `memory` in 0.90 s, with no fetch
  (1.06 s and 39 MiB, and 1.27 s, on the shipped image's larger budget):
  the kill comes from the run's cgroup before the kernel reclaims anything the
  rest of the guest maps. Before the cgroup, `oom` took 1.1 to 1.4 s and fetched 5
  to 7 files (9 MB) that Xorg and the agent map, and one run of it ended
  `unresponsive` once the agent's own binary had been evicted.
- `big-files`: 8 MiB of files took 8,200 kB of tmpfs, which left the run a
  `memory.max` of 17,808 kB; it allocated 17 MiB and ended `oom` after 539 ms.
- `window-follows`: every WINDOW reached the host 6 to 63 ms before the case saw
  the window's colour in the framebuffer, which it polls every 2 ms; in earlier
  runs one came up to 11 ms after. With the watcher asking the server for the
  whole list each time, the worst was 137 ms after.
- `x-grab`: a window mapped while the watcher waited on a grabbed server was
  listed 29 ms before the case saw the grab's end on screen; through the 6 s
  grab three PONGs came, 2 s apart as the host pings.
- `big-canvas`: Xlib's `BadAlloc` ended the program with code 1 after 425 ms.
- `hd-canvas`: the 1920 × 1080 Canvas drawn 931 ms after `run()` and the 1600 ×
  1600 one 2,313 ms after; Xorg's VmHWM went from 10,348 kB to 18,540 and 20,624
  kB, its VmData stayed at 7,232 kB, and stderr stayed empty.
- `near-budget`: 24,232 kB of the 26,000 kB `memory.max` filled, then the
  1920 × 1080 Canvas drawn 889 ms after `run()`. Its pixmap came out of free
  memory (MemFree 14,612 to 14,228 kB) while `Mapped` stayed at 15,936 kB, and
  nothing was fetched.
- `lingering`: EXIT 891 ms after the program's last line, with ten children
  still spinning at that line. One run on this step's first 128 MiB build took
  1,624 ms against the case's 1,500 ms, while other builds shared the machine;
  every run since has passed.
- `park`: after 15 minutes parked, the next run's clock was 35 ms off (26 to 44
  ms in earlier runs), its `after(300)` fired at 0.326 s, and the console printed
  no lockup or stall.
- `park-detectors`: with `soft_watchdog=1` and `rcu_cpu_stall_suppress=0`, a run
  paused 15 minutes mid-animation went on as if nothing had happened: the largest
  step of its monotonic clock between two lines was 0.62 s, against 0.5 s when
  running, 27 lines followed in the next 15 s, the wall clock was 32 ms off after
  HELLO, and `dmesg` had no new line at all.

Both park cases ran on image `4d7a3680c90a3f5d`, the 96 MiB build before
`7580ed6dc2732d62`, and were not run again at 128 MiB.

An earlier build, before the prelude loaded the message box's script into the
handed-over root, took 2,174 ms to show `messagebox-close`'s dialog and 1,045 ms
for `withdraw-dialog`'s.

## Measured

Node 26.8 on an M1, v86 0.5.461, one emulator. Other builds shared the machine
for most runs, so times vary by up to 2×.

These are the Alpine 3.22 build with Alpine's own kernel, and they are kept
because they are how the state got to the size it did. What ships today is
smaller and faster on every line: see "What shipped".

| | |
|---|---|
| `new V86()` to `emulator-loaded` | 24–80 ms |
| Boot to a shell | 23.5–25.7 s on a quiet host, 31–47 s while other builds ran (spike image: 35–43 s) |
| Xorg until `xwininfo` answers | 5.2–5.3 s |
| A Tk window from a cold `python3`, as the student | 8.9–15.4 s |
| `python3 -c pass`, warm page cache, host round trip | 0.24–0.56 s |
| `free -m` with X and one Tk program | 57 MB total, 22 used, 27 available |
| Boot to the agent's READY, build-state | 23.1–31.1 s |
| PREPARE, HELLO to PARKED | 16.9–22.8 s: Xorg 2.1–2.4 s, warm-up 14.2–19.6 s |
| The saved state, final build | **20,619,195 B** zstd -19 with its checksum (19.66 MiB); 75.6 MB raw, at 128 MiB. At 96 MiB: 20,318,542 B (19.38 MiB), 75.2 MB raw |
| The saved state, every build of the hardening step | 20,083,710–20,464,236 B (shipped), 20,238,028–20,414,292 B (debug); 19,721,445–20,373,228 B and 20,044,121–20,256,179 B in the step before |
| Read back into the page cache | 22.5 MB in 127 files, 55 of them mapped |
| Memory at the save | MemTotal 91,320 kB, MemAvailable 58,152 kB, 47,872 kB zero-filled; at 96 MiB, 58,728, 26,220 and 15,232 kB |
| `openVm().load()` to `ready`, from disk | 219–295 ms, the state decompressed in place first; 246–311 ms restoring the zstd state |
| Restore to READY `{warm: true}`, fresh host | 118–204 ms |
| `run()` to the program's own colour on screen | 249–830 ms; 249–404 ms for a window without a dialog |
| STOP to EXIT | 2.1–9 ms; the kernel's teardown goes on 70–230 ms after it |
| `stop()` to parked | 23–35 ms from the raw state; 117–119 ms from the zstd one |
| Files a corpus program reads over 9p | 0, except `big-canvas`'s `XErrorDB`, `sandbox`'s `/bin/busybox` for `su`, the fetch-failure case's own and a cold `python3`'s |

The state moved with what it holds: 20,035,727 B with only the mapped files read
back and 4 MiB left unzeroed; 18,942,307 B with the reserve at 2 MiB, the last
steps at 64 KiB, and Tcl's and Tk's scripts added; 19,936,123 B with the DejaVu
faces added, which spared a program using them 1.09 MB of fetches. With the X
watcher's connection, the agent's own binary and the two zone files read back it
was 19,949,976 B. The final build also loads the message box's script and the
named fonts into the handed-over root and has watermark boosting off: 20,373,228
B, which leaves about 0.57 MiB of the 20 MiB target (20,971,520 B); each thing
added to the snapshot takes from it. The build before it had the same prelude
but boosted watermarks, and came out smaller, 19,721,445 B, for the wrong
reason: its zero-fill reclaimed about 8 MB of mapped pages (Mapped 16,012 to
7,928 kB) and zeroed them, and every run would have faulted them back in. The
hardening step, the run's cgroup, the X watcher's thread and the rest of "The
agent", moved it by less than the builds vary: 20,318,542 B for the final one,
about 0.62 MiB under the target. At 128 MiB the builds came out at 20,619,195
to 21,165,655 B, past the 20 MiB target at worst and under the 21 MiB the RAM
was chosen against ("The machine").

**The guest has 100 MiB, not 128.** The BIOS's e820 map reserves the top 16 MiB
of the 128, so Linux sees 112 MiB, and the kernel keeps the rest: 12 MiB with the
kernel this build makes, against 22 with Alpine's. MemTotal on the shipped image
is 102,044 kB, and what the warm machine leaves a program is MemAvailable,
69,324 kB, of which the run's budget is 40,284 kB. With Alpine's kernel it was
MemTotal 91,320, MemAvailable 58,152 and a 26 MiB budget; at 96 MiB the guest had
57 MiB, Linux saw 80 and MemAvailable was 24.

## Measurements

Everything above this section was measured under Node. These are the first
figures from a browser: headless Chrome 153.0.8010.48 on a MacBook Air M1
(8 cores, 16 GB), image `94cb72a4653086ac` (state 20,373,228 B, 74,934,612 B
raw), v86 0.5.461, on a quiet machine (load average 2 to 3). "final" and "The
app in Chrome", at the end, run again on `7580ed6dc2732d62` and then on the
shipped `dda79f227497cc75`.

**Every section below names the image it ran on, and none of them is the one
that ships.** They were taken while the state was still around 20 MB; the
shipped state is 15,301,311 B and a cold load moves 17.4 MB rather than the 20.9
these tables say ("What shipped"). Read them for what they weigh against each
other — 1× against 4×, pieces against one GET — and not for absolute times. "The
app in Chrome" ends with the shipped image.

```bash
just bench-vm                       # all of it, about 30 min
just bench-vm --only matrix         # one section; the names are the headings below
just serve-vm-bench                 # the bench page on :8086, to watch it by hand
```

`vm/tools/bench/bench.js` is a page that opens the bundle through `openVm()` and
`vm_screen.js`, as the app will, from a server that sends the app's COOP and
COEP headers. `run-bench.mjs` drives it over CDP and writes
`vm/build/bench/bench.json`, with a fresh Chrome profile for every cold load.
It measures by wrapping browser APIs, never the host: `restore_state` for the
restores, the Cache API for the bundle's reads, `requestAnimationFrame` for
frame times, and the `longtask` and `long-animation-frame` observers.

**A school Chromebook is stood in for by CDP's CPU throttling at 4× and 6×.** It
slows the page's main thread and nothing else: a zstd decompression in a worker
took 110 to 163 ms at every rate. So work moved off the main thread looks free
here and will not be on a real Chromebook, and GPU, memory bandwidth and heat are
not modelled at all. These numbers decide what to try; a real Chromebook has to
confirm them. Cold loads were also run at 50 and 20 Mbit/s down, 10 up and 20 ms
of latency.

"On the canvas" is the time from `run()` until the program's own colour is in
the page's canvas, watched from Run on at the point where the window lands, since
with no window manager a window with no geometry of its own opens at +0+0. It is
what a student sees. "WINDOW" is `run()` to the first WINDOW frame that lists the
window mapped. Times are the median, with the range in brackets; each "first
window" is one run.

### matrix: loading and the first window

The screen opens and Run is pressed at once, so the first window includes the
load. Each of the three programs went first once per row.

| CPU, cache, line | `load()` to `ready` (ms) | First window on the canvas: label, canvas, ttk (ms) |
|---|---:|---|
| 1×, warm | 205 (202–205) | 540, 670, 724 |
| 1×, cold | 310 (282–367) | 695, 737, 816 |
| 1×, cold, 50 Mbit/s | 3,800 (3,789–3,813) | 4,100, 4,260, 4,321 |
| 1×, cold, 20 Mbit/s | 9,023 (8,995–9,105) | 9,295, 9,482, 9,607 |
| 4×, warm | 790 (788–805) | 1,980, 2,682, 2,774 |
| 4×, cold | 896 (896–901) | 2,071, 2,875, 2,870 |
| 4×, cold, 50 Mbit/s | 4,429 (4,407–4,441) | 5,696, 6,322, 6,373 |
| 4×, cold, 20 Mbit/s | 9,440 (9,421–9,473) | 10,610, 11,347, 11,427 |
| 6×, warm | 1,173 (1,156–1,191) | 3,044, 4,097, 4,170 |
| 6×, cold | 1,306 (1,286–1,322) | 3,068, 4,298, 4,338 |
| 6×, cold, 50 Mbit/s | 4,803 (4,771–4,875) | 6,772, 7,819, 7,929 |
| 6×, cold, 20 Mbit/s | 9,839 (9,835–9,860) | 11,790, 12,798, 12,762 |

A cold load moves 20.9 MB: the state, `v86.wasm` gzipped to 403 KB, `libv86.mjs`
gzipped to 95 KB and the manifest. A warm one moves the manifest's 304 and
nothing else. No run in the whole bench fetched a rootfs file.

Every program then ran again from the parked machine, 12 runs per program and
rate:

| CPU | label on the canvas (ms) | canvas | ttk | WINDOW more than 0.5 s after the pixels |
|---|---:|---:|---:|---:|
| 1× | 311 (272–334) | 446 (436–461) | 498 (457–511) | 0 of 36 |
| 4× | 1,048 (954–1,079) | 1,719 (1,691–1,817) | 1,766 (1,680–1,830) | 8 of 36 |
| 6× | 1,662 (1,594–1,766) | 2,703 (2,635–2,779) | 2,718 (2,562–2,767) | 7 of 36 |

The last column is an agent bug, below. The Node figures in "Measured" hold for
Chrome on the same machine: `ready` 195 ms under Node against 205 in Chrome, label's
WINDOW 237–294 ms against 225–283, and 303,000–315,000 loop iterations a second
of `speed.py` against 297,000.

### download: pieces, one GET, and a connection that goes

`just bench-vm --only download`, image `298ac660ab037ae5` (20,574,491 B of state
and 2,101,621 B of wasm), headless Chrome 153 on the M1, CDP's throttle at 20 and
50 Mbit/s down, 10 up and 20 ms of latency, three runs of each; the median, with
the range in brackets. "Pieces" is the host as it ships, 2 MiB Range requests
three at a time; "one GET" is `download: {ranges: false}`, what it did before.

| Line, how | `load()` to `ready` (ms) | Bundle in (ms) | First speed shown (ms) | Speed at the end | ETA off by, median / p90 (s) | Warm again: to `ready`, bundle read (ms) |
|---|---:|---:|---:|---:|---:|---|
| 20 Mbit/s, pieces | 8,890 (8,880–8,955) | 8,549 | 2,123 | 2.56 MB/s | 0.36 / 1.25 | 372 (363–484), 77 (77–169) |
| 20 Mbit/s, one GET | 8,926 (8,897–8,959) | 8,536 | 2,118 | 2.53 MB/s | 0.36 / 1.23 | 360 (358–364), 67 (66–72) |
| 50 Mbit/s, pieces | 3,869 (3,848–3,874) | 3,462 | 2,081 | 6.61 MB/s | 0.08 / 0.14 | 387 (376–441), 88 (77–135) |
| 50 Mbit/s, one GET | 3,913 (3,825–3,928) | 3,477 | 2,117 | 6.56 MB/s | 0.08 / 0.14 | 354 (353–361), 63 (60–64) |

**On a line that holds, pieces cost nothing.** Both ways take what the line
gives: 22.7 MB in 8.5 s is 2.65 MB/s against the throttle's 2.5, and the page is
ready 0.3 to 0.4 s after the last byte, unpacking and starting. The ten requests
the pieces take hide behind each other. Read back from the Cache API on a second
visit, the ten pieces cost 10 to 25 ms more than one entry did.

**The estimate is good from the moment it shows.** The speed appears at 2.1 s,
the 2 s and 256 KiB the host waits for; at 20 Mbit/s it matched the throttle
within 3 %, and the finishing time it gave was off by 0.36 s at the median and
1.25 s at worst, 0.6 s early at the halfway point. At 50 Mbit/s the whole
download is 3.5 s, so the estimate shows for the last 1.4 s of it.

A connection that goes: the server drops every connection at 40 % (9.1 MB) and
refuses new ones for 3 s (`serve.mjs`'s `cut`), at 20 Mbit/s.

| How | Bundle in (ms) | Fetched over the network | State requests |
|---|---:|---:|---:|
| Pieces | 11,246 (11,214–11,490) | 22.7 MB, all of it once | 13 |
| One GET | 15,117 (15,040–15,229) | 31.4 MB (31.1–31.6) | 2 |

**A dropped connection costs the time it was gone, and no bytes.** The three
pieces under way keep what they had and ask for the rest after the 1 s and 2 s
retries, so the download ends 2.7 s later than one that was never cut; the panel
said "stalled" for the 21 to 25 reports in between. One GET starts over from
nothing and fetches 8.7 MB twice.

A reload: the page goes at 40 % and a fresh one asks again, at 20 Mbit/s.

| How | Second download (ms) | From the cache | Fetched | From the first start (s) |
|---|---:|---:|---:|---:|
| Pieces | 5,825 (5,824–5,833) | 8.4 MB | 14.3 MB | 9.0 |
| One GET | 8,375 (8,366–8,375) | 2.1 MB, the wasm | 20.6 MB | 11.5 |

**A reload keeps what had landed.** Of the 9.1 MB in, the 6.3 MB of whole
pieces and the wasm came back from the Cache API; the three pieces in flight,
0.7 MB of them, went with the page ("Not done"). With one GET only the wasm,
which is its own request, survived.

### micro: Cache Storage and the compile

| CPU | Reading the 20.4 MB state from Cache Storage (ms) | Compiling `v86.wasm` from bytes (ms) | `compileStreaming` (ms) |
|---|---:|---:|---:|
| 1× | 11 (9–15) | 2 (2–2) | 5 (5–6) |
| 4× | 21 (20–24) | 3 (3–4) | 13 (12–14) |
| 6× | 31 (30–35) | 4 (3–5) | 20 (19–21) |

Inside a warm load the state's read took 17–19, 47–48 and 67–74 ms. The design
guessed 50–150 ms for the read and up to 100 ms for the compile. V8 compiles
lazily, so the compile's real cost is spread over the first calls instead.
Writing the state to Cache Storage on a cold load takes 167–200 ms and never
showed as a long task.

### restore: the park

**Every park is one long task, and it grows with the CPU.** The host restores the
zstd state after every run and once during the load, and v86 decompresses it
inside `restore_state`, synchronously:

| CPU | Park restore, zstd (ms) | Stop to parked (ms) | Longest frame around it (ms) | The restore during a warm load (ms) |
|---|---:|---:|---:|---:|
| 1× | 122 (115–150) | 132 (122–177) | 100–133 | 136–137 |
| 4× | 494 (481–536) | 530 (507–565) | 467–517 | 550–576 |
| 6× | 755 (731–797) | 807 (762–851) | 717–783 | 835–851 |

STOP to EXIT took 2, 19 and 31 ms. The long-animation-frame entries put the
whole block in `Worker.onmessage`: v86's tick, in which the CPU stops and the
host's restore follows.

The alternatives, five restores each on one host:

| CPU | zstd, as now | Raw state | zstd decompressed on the main thread | zstd decompressed in v86's worker, then the raw restore | Raw state read back from Cache Storage |
|---|---:|---:|---:|---:|---:|
| 1× | 137 (130–165) | 49 (24–54) | 147 (124–154) | 153 (128–163) off the thread, then 31 (24–38) | 60 (34–69), no long task |
| 4× | 478 (476–560) | 73 (68–97) | 407 (406–432) | 113 (110–126), then 112 (87–126) | 72 (71–82), no long task |
| 6× | 728 (715–845) | 108 (101–170) | 626 (612–656) | 119 (115–138), then 169 (151–187) | 106 (101–113), one 50 ms task |

READY followed a raw restore sooner than a zstd one: 11–39 ms against 40–91.

What each costs in memory, one tab, parked after two runs:

| | v86's wasm memory | JS and wasm heap (`measureUserAgentSpecificMemory`) | Renderer footprint | Renderer RSS |
|---|---:|---:|---:|---:|
| zstd state, as now | 147.1 MiB | 184.1 MiB | 257 MiB | 582 MiB |
| raw state, fetched raw | 112.3 MiB | 201.3 MiB | 276 MiB | 617 MiB |

Keeping 71.5 MiB of raw state costs only 19 MiB of footprint, because restoring
the zstd one grows v86's wasm memory by 35 MiB that the raw one never asks for.
Decompressing through v86 is worse on both counts: five `zstd_decompress` calls
on the main thread left the wasm memory at 212 MiB, and v86's zstd worker held
173 MiB until the page closed. `DecompressionStream` has no `zstd` in Chrome 153.

### park: from the raw state

The host decompresses the state once per page, in a worker of its own that it
ends straight after, and restores the raw state at the load and at every park
("The host"; `just bench-vm --only park`). Two sessions per rate, six parks
each, on images `94cb72a4653086ac` and `8eb7787ca9bd2ac8`; an image build
shared the machine for part of both:

| CPU | Park restore (ms) | Longest task around it (ms) | Stop to parked (ms) | Before, zstd: park restore, stop to parked (ms) |
|---|---:|---:|---:|---|
| 1× | 19–50 | none over 50 | 30–61 | 115–150, 122–177 |
| 4× | 89–132 | 89–133 | 130–177 | 481–536, 507–565 |
| 6× | 155–191 | 156–191 | 198–301 | 731–797, 762–851 |

The load:

| CPU | Decompressing in the worker (ms) | The load's restore (ms) | `load()` to `ready` (ms) | Before, zstd: the load's restore, `ready` (ms) |
|---|---:|---:|---:|---|
| 1× | 153–168 | 41–96 | 251–350 | 136–137, 205 |
| 4× | 157–197 | 142–204 | 453–635 | 550–576, 790 |
| 6× | 193–295 | 291–306 | 778–928 | 835–851, 1,173 |

The worker runs while v86 compiles and starts, so at 4× and 6× the load is
faster than before, and at 1×, where the worker takes longer than the rest, it is
about 50 to 150 ms slower. The first restore of a page is slower than the parks
after it. CDP throttles only the main thread, so the worker took the same time at
every rate here and will not on a Chromebook. v86's wasm memory stays at 112 MiB
after any number of parks, against 147 MiB with the zstd state, and the host
keeps the 71.7 MiB raw state instead of the 19.4 MiB zstd one. In the restore
experiment above, run again on image `9aceb0971e49ab43`, the host's worker took
125–169, 132–144 and 138–151 ms at 1×, 4× and 6× before the same raw restore.

### frames: the page while programs run

With a page that does nothing else, the VM does not cost a frame. At 1×, 4× and
6× the frame times were 16.7 ms at the median, the 95th percentile and the
maximum, with no long task, while Tk sat idle, while the machine was parked,
through six seconds of `while True: pass`, and through `animation.py`'s
`after(50)`, which made 17, 15.4 and 13.3 of its 20 possible steps a second. The
design's target of no frame over 50 ms holds everywhere except the park.

Emulation slows more than the CPU does: `speed.py` counted 297,000, 43,000 and
25,333 iterations a second, so 4× throttling made the guest 6.9 times slower and
6× made it 11.7 times slower.

### frame-load: the page's own work competes

**A page that works on every frame takes the VM's time, out of all proportion.**
The bench page burned a fixed amount of work in each `requestAnimationFrame`,
standing in for Flutter building and painting every frame (`--only frame-load
--frame-work-ms 12`; the default is 6):

| Work each frame, at 1× | CPU | `speed.py` (iterations/s) | Share of an idle page's | `after(50)` steps a second | First window on the canvas (ms) |
|---|---|---:|---:|---:|---:|
| none | 1× | 297,000 | | 17 | 506 |
| 6 ms | 1× | 106,333 | 36 % | 16.1 | 698 |
| 12 ms | 1× | 9,000 | 3 % | 10.1 | 1,285 |
| 20 ms | 1× | 4,333 | 1.5 % | 7.5 | 3,556 |
| none | 4× | 43,000 | | 15.4 | 1,954 |
| 6 ms (24 at 4×) | 4× | 1,333 | 3 % | 5.4 | 6,754 |
| 6 ms (36 at 6×) | 6× | 1,000 | 4 % | 3.8 | 9,854 |

With 6 ms of work at 4×, frames were 50 ms at the median while a program ran.
How v86 hands the thread back between its 1 ms slices matters too. The bench can
swap it (`--page-query yield=…`):

| Yield | 6 ms at 1× | 6 ms at 4× | 12 ms at 1× | Idle page, 1× and 4× |
|---|---:|---:|---:|---:|
| v86's own, a round trip through a blob worker | 106,333 | 1,333 | 9,000 | 297,000 and 43,000 |
| A `MessageChannel` to itself | 110,666 | 4,000 | 45,666 | 299,333 and 43,333 |
| v86's `use-scheduling-api`, `postTask` at its default priority | 110,666 | 1,333 | | |
| `postTask` at `user-blocking` | starved the page: the runner's next CDP call timed out after 15 min | | | |

The `MessageChannel` costs nothing on an idle page and gives three to five
times the throughput under load, with frames no worse (33 ms at the median
instead of 50 at 4×). The app itself costs nothing while it is idle: framed
beside the VM on its first screen, it left `speed.py` at 299,333.

The host yields through a `MessageChannel` of its own ("The host"). Compared
again on image `8eb7787ca9bd2ac8`, the host's channel against v86's worker put
back (`--page-query yield=v86`): one `frame-load` session each, and four
`frames` sessions interleaved, channel first. Image builds and a Flutter build
shared the machine for most of them (load average 4 to 13), so a single figure
can be off by up to 2×:

| | `MessageChannel` | v86's worker |
|---|---:|---:|
| 6 ms a frame at 1×: `speed.py` (iterations/s) | 132,666 | 106,333 |
| 6 ms a frame at 4×: first window on the canvas (ms) | 5,637 | 6,299 |
| 6 ms a frame at 4×: frames while busy, median (ms) | 33 | 50 |
| 6 ms a frame at 6×: first window on the canvas (ms) | 8,607 | 9,634 |
| 6 ms a frame at 6×: `after(50)` steps a second | 5.7 | 4.8 |
| Idle page: frames, median, 95th percentile and maximum (ms) | 16.7 | 16.7 |
| Idle page: `after(50)` steps a second at 1× | 18.0–18.2 | 17.0–17.6 |
| Idle page: `speed.py` at 1× (iterations/s) | 233,333–271,000 | 211,666–292,333 |
| Idle page: STOP to EXIT in a busy loop at 1×, 4×, 6× (ms) | 6.5–9.2, 34–74, 50–107 | 6.6–9.2, 36–45, 49–68 |
| Share of a core at 1×, parked | 0.023 | 0.019–0.039 |
| Share of a core at 1×, Tk idle | 0.08–0.16 | 0.09–0.13 |

Under load the channel gains 10 to 25 %, not three to five times: the figures
above rested on `speed.py`, which counts in steps of 1,000 over 3 s, so 1,333
and 4,000 are 4 and 12 steps. On an idle page the two are the same within the
noise, in frames, STOP latency and CPU. The share of a core at 4× and 6× is left
out, because CDP's throttling shows as most of a core whatever the page does.

### memory: one tab and two

The app is `build/web/` from 19 September, on its first screen, with its Python
worker loaded. Parked means after two runs.

| | Heap: the app, its Python worker, the VM (MiB) | Renderer footprint (MiB) | Renderer RSS (MiB) | All of Chrome, footprint (MiB) |
|---|---|---:|---:|---:|
| The bench page, no VM | 2.7 | 32 | 140 | 224 |
| The VM alone, running `ttk_widgets.py` | 184.2 | 254 | 534 | 438 |
| The VM alone, parked | 184.1 | 242–243 | 512–530 | 425 |
| Two tabs, the VM alone in each | 184.1 + 184.2 | 249–260 + 237 | 530–534 + 356 | 685–695 |
| The app alone | 80, 13.1 | 209 | 424 | 430 |
| The app and the VM, running | 76.4, 13.1, 183.6 | 506 | 652 | 762 |
| The app and the VM, parked | 79.8, 13.1, 183.5 | 496 | 652 | 743 |
| Two tabs, the app and the VM in each | 2 × 280 | 527 + 386 | 748 + 448 | 1,178–1,210 |

v86's wasm memory is 138.8 MiB after the load and 147.1 MiB after the first
park, and does not grow after that. The heap figures are
`measureUserAgentSpecificMemory`, which the page can call because it is
cross-origin isolated; footprint is macOS's `footprint`, RSS is `ps`.

### Checks in the browser

- **input**: a real click and real key events through Chrome, `vm_screen.js` and
  v86's adapters. `entry.py` opens two windows; typing with nothing clicked must
  reach the newest window's Entry (F4), a click in the other window must move the
  keys there, and Return must reach Tk. It passed at 1× and 6×. At 4× the keys
  typed before the click went nowhere, in 7 of 7 tries on the day; with the agent
  woken every 50 ms it passed 3 of 3. See the agent bug below.
- **hidden**: `animation.py` running while another tab was in front for 20 s.
  The page went `hidden`, the host stopped the CPU (`is_running()` false at 2 s
  and at 20 s), the program made no steps while hidden, no watchdog verdict or
  other failure arrived, and back in front it went on at 17.1 steps a second with
  the guest's wall clock 32–34 ms behind the page, output delivery included (F2).
- The screen: every "on the canvas" figure above is v86 drawing into
  `vm_screen.js`'s canvas, read back with `getImageData`.
- Run again on image `9aceb0971e49ab43`, with the host's raw-state parks and
  `MessageChannel` yield: input passed at 1×, 4× and 6×, with and without the
  agent woken, and `window-delay` found no WINDOW later than 1.9 s after STARTED
  in 8 runs at each rate (label's WINDOW 209–266, 818–920 and 1,280–1,618 ms).
  On the final image both hold again ("final" below).

### sweep: where it breaks

The same warm profile, the screen opened and Run pressed on `label.py`, then an
animation, a busy loop and `ttk_widgets.py` from the parked machine. The 1× to 6×
rows are the medians from the sections above; from 8× on each figure is one run.

| CPU | `ready` (ms) | First window on the canvas (ms) | ttk from parked, on the canvas (ms) | `after(50)` steps a second | Longest frame in the animation (ms) | Park restore (ms) |
|---|---:|---:|---:|---:|---:|---:|
| 1× | 205 | 540 | 498 | 17 | 17 | 122 |
| 4× | 790 | 1,980 | 1,766 | 15.4 | 17 | 494 |
| 6× | 1,173 | 3,044 | 2,718 | 13.3 | 17 | 755 |
| 8× | 1,537 | 4,016 | 3,623 | 12 | 50 | 978–1,002 |
| 10× | 1,933 | 5,164 | 4,616 | 10.7 | 50 | 1,248–1,303 |
| 12× | 2,286 | 6,401 | 5,344 | 8.5 | 50 | 1,509–1,589 |
| 16× | 3,053 | 8,282 | 7,643 | 7.1 | 83 | 2,058–2,129 |
| 20× | 3,916 | 11,235 | 9,744 | 6.6 | 100 | 2,562–2,767 |
| 30× | 6,236 | 18,098 | 15,839 | 4.1 | 167 | 3,967–4,389 |
| 40× | 8,155 | 24,344 | 22,156 | 3.2 | 183 | 5,321–5,661 |

Nothing failed up to 30×: no watchdog verdict, no lost run, every window drawn.
At 40× one STOP went unanswered within its 500 ms grace, and the host parked
anyway, as it should. The watchdog counts active time only, so a slow machine
never runs it out.

### final: the final image

`just bench-vm --only park --only frames --only window-delay --only input --only
memory --only app` again, on image `7580ed6dc2732d62` (state 20,318,542 B,
75,242,108 B raw) and the host as it ships, one session per section and rate, at
a load average of 2.5 to 4.3. The last column is the section above that measured
it, at 1×, 4× and 6×.

| | 1× | 4× | 6× | Before |
|---|---:|---:|---:|---|
| `load()` to `ready` (ms) | 218 | 472 | 628 | 251–350, 453–635, 778–928 ("park") |
| Decompressing the state in the worker (ms) | 129 | 156 | 216 | 153–168, 157–197, 193–295 |
| The load's restore (ms) | 39 | 135 | 194 | 41–96, 142–204, 291–306 |
| Park restore, six parks (ms) | 17–25 | 66–80 | 100–125 | 19–50, 89–132, 155–191 |
| Longest task around a park (ms) | none | 66–81 | 101–126 | none over 50, 89–133, 156–191 |
| Stop to parked (ms) | 27–51 | 116–141 | 177–197 | 30–61, 130–177, 198–301 |
| Frames through idle Tk, a park, `while True` and `after(50)` (ms, max) | 16.7 | 16.7 | 16.7 | 16.7 ("frames") |
| `after(50)` steps a second | 17.7 | 15.7 | 14 | 17, 15.4, 13.3 |
| `speed.py` (iterations/s) | 295,333 | 44,333 | 24,666 | 297,000, 43,000, 25,333 |
| STOP to EXIT in a busy loop (ms) | 7 | 31 | 38 | 6.5–9.2, 34–74, 50–107 |
| Share of a core, Tk idle / parked | 0.17 / 0.055 | | | 0.08–0.16 / 0.023 |
| label's WINDOW, 8 runs (ms) | 249–279 | 851–938 | 1,385–1,448 | 209–266, 818–920, 1,280–1,618 |
| label on the canvas, the same runs (ms) | 296–327 | 995–1,090 | 1,629–1,744 | |
| WINDOW over 1.9 s after STARTED, alone / agent woken | 0 / 0 of 8 | 0 / 0 of 8 | 0 / 0 of 8 | 4 and 3 of 8 at 4× and 6× on `94cb72a4653086ac` |
| input: F4 focus, a click, Return; alone and woken | pass, pass | pass, pass | pass, pass | failed 7 of 7 at 4× on `94cb72a4653086ac` |

Nothing got worse beyond the noise. Waking the agent every 50 ms gains nothing
now, and at 4× and 6× makes label about 100 ms slower to the canvas. The share of
a core at 1× is higher than before, parked included; it is one sample each, on a
machine running other work, and was not chased.

**Run again on the shipped image** (`just bench-vm --only park --only frames
--only input --only window-delay --rates 1,4`, `dda79f227497cc75`), to see
whether the new kernel, `init_on_free` and zstd -22 cost anything at run time.
They do not: every line is level with the column above or ahead of it.

| | 1× | 4× | The column above |
|---|---:|---:|---|
| `load()` to `ready` (ms) | 223 | 491 | 218, 472 |
| Decompressing the state in the worker (ms) | 119 | 142 | 129, 156 |
| The load's restore (ms) | 34 | 131 | 39, 135 |
| Park restore, six parks (ms) | 15–20 | 59–78 | 17–25, 66–80 |
| Longest task around a park (ms) | none | 60–80 | none, 66–81 |
| Stop to parked (ms) | 23–30 | 104–122 | 27–51, 116–141 |
| Frames through idle Tk, a park, `while True` and `after(50)` (ms, max) | 16.7 | 16.7 | 16.7 |
| `after(50)` steps a second | 17.9 | 15.8 | 17.7, 15.7 |
| `speed.py` (iterations/s) | 342,666 | 56,666 | 295,333, 44,333 |
| STOP to EXIT in a busy loop (ms) | 4.7 | 23.2 | 7, 31 |
| WINDOW, 8 runs (ms) | 167–230 | 697–751 | 249–279, 851–938 |
| WINDOW over 1.9 s after STARTED, alone / woken | 0 / 0 of 8 | 0 / 0 of 8 | 0 / 0 of 8 |
| input: F4 focus, a click, Return; alone and woken | pass, pass | pass, pass | pass, pass |

The guest is 16 % faster at 1× and 28 % at 4× on `speed.py`, which is the slim
kernel leaving more of the machine to the program. No section reported a failure.

The same four sections ran again at integration, on the same bundle and machine,
and agreed within the noise: `ready` 217 and 510 ms, the worker 117 and 138,
the load's restore 34 and 129, park restores 14–18 and 59–73, stop to parked
25–30 and 105–132, frames 16.7 everywhere, `after(50)` 17.7 and 15.8 steps a
second, `speed.py` 376,666 and 51,333, STOP to EXIT 4.7 and 20.9 ms, WINDOW
176–219 and 702–750 ms with none late, and input passing at both rates, woken
and not. `speed.py` is the one line that moves by more than a few per cent
between sessions, in both directions.

| Memory | Heap (MiB) | Renderer footprint (MiB) | Renderer RSS (MiB) | All of Chrome (MiB) |
|---|---|---:|---:|---:|
| The VM alone, running `label.py` | 200.8 | 257 | 520 | 461 |
| The VM alone, parked after runs | 201.3 | 260–262 | 525–548 | 457–461 |
| Two tabs, the VM alone in each | 201.3 + 201.2 | 266 + 255 | 537 + 539 | 733–746 |
| The app on its first screen | 97 | 209 | 427 | 438 |
| The app framed by the bench, the VM running `ttk_widgets.py` | 297.5 | 512 | 793 | 783 |
| The same, parked | 297.4 | 520 | 794 | 787 |
| Two tabs, the app and the VM in each | 2 × 298 | 452–514 + 398 | 752–820 + 768 | 1,151–1,209 |

The VM alone holds 17 MiB more heap than with the zstd state (184.1 MiB): the
71.7 MiB raw state it keeps, less the 35 MiB of wasm memory the zstd restore used
to add. "memory" above predicted about that.

### The app in Chrome

`just check-vm-app` runs `vm/tools/check-app.mjs`, which serves `build/web/` with
the app's COOP and COEP headers and drives the app itself in headless Chrome, at
1440 × 1000 and, for Flutter drawn over the display, 820 × 700. Flutter draws into
a canvas, so a survey page with semantics on finds where the controls are, and
the checks then click by position on pages without semantics, as most students
have them. The cross that ends a program is found both ways: by what a screen
reader is told, and by the frame's own measurements from the display's box, which
one check holds against each other. The served `vm/vm_host.js` is a wrapper that re-exports the real one and
copies every host event into `window.__vmEvents`, which is how a check reads
output and why a run ended; the Tk window itself is read out of v86's canvas.
`--lesson learn-python/uitvoer/zelf-printen` also runs one lesson step, which
goes through `python.wasm` and not the VM; `--root` and `--base` check another
build, such as one made with the deploy's `--base-href /i-can-code/`.

It holds, and passed 30 of 30 on `build/web/` with images `298ac660ab037ae5` and
`eba47d0db90c25a8` (128 MiB), and 29 of 29 on `7668214b5d9fad5e` before the check that Tab leaves
after a run was added. On `7580ed6dc2732d62` (96 MiB) it passed 30 of 30 with the
lesson step, and 29 of 29 on a `/i-can-code/` build. It passed 41 of 41 on
`dda79f227497cc75` once the program became a dialog over a one-column page:

- the catalog's Extra card opens `#/learn-python/tkinter`; the editor names the
  machine once ready; a screen reader is told the display's state, and the frame
  reads the window's title;
- with semantics on, Run moves the keyboard into the display (the bug under
  "Flutter side") and a click reaches Tk;
- without semantics, cold and at 20 Mbit/s: the loading panel shows the download
  (`loading-panel.png`), the starter program's window is drawn and titled
  "Mijn eerste venster", Run moves DOM focus into the display, a real click on
  its button changes the label twice, and WINDOW follows the window as the label
  grows;
- Stop ends the run as `stopped` and parks; an Entry gets "Hello Sanne", capital
  included, and Return; Escape then Tab leaves, and keys typed then stay out of
  the guest; `while True` runs until Stop; a program without `mainloop()` gets the
  hint; a traceback reaches the output card with the crash notice and starts at
  `main.py`; once it has ended, the dialog is gone and nothing of it keeps the
  keyboard;
- leaving the page destroys the machine and gives its memory back, and a second
  visit reads the bundle from the Cache API without a request for the state;
- the draft brings a program back into the editor; the wheel over the display
  moves nothing, a press on the dim beside the program and a click on the
  settings menu where it lies over the display reach neither the guest nor the
  page, a click on the display does, and the page is where it was left once the
  dialog goes;
- at 4× the starter program runs, takes a click and stops, three times.

Since the display shows only the program's windows it holds seven more, and
passed 37 of 37 on `298ac660ab037ae5`:

- the starter's window is shown alone, 175 × 106 at scale 1 and drawn
  nearest-neighbour, and the crop follows it to 211 wide as its label grows;
  the Entry is clicked back into through its own margin rather than through the
  black root beside it, which is no longer on the page;
- a small window (87 × 53) is shown cropped at 1×, a click on its button opens a
  messagebox that widens the crop to 340 × 94, and a click on the messagebox's OK,
  found in the canvas, answers `ok` and shrinks the crop back to 87 × 53
  (`crop-small-window.png`, `crop-messagebox.png`, `crop-after-ok.png`);
- at 1100 × 760 a 1920 × 1080 canvas is cropped to the 800 × 600 screen and shown
  at 0.97 in the dialog, 776 × 582 CSS pixels and resampled rather than
  nearest-neighbour, and clicks aimed at guest (400, 300), (780, 580) and
  (15, 20) landed at (400, 300), (779, 579) and (14, 19) (`crop-big-canvas.png`).
  It was 0.63 in 504 × 378 while the screen shared the page with the editor.

Since the state comes down in Range pieces its server answers a single Range
with a 206, as GitHub Pages does, and it holds two more, which passed 39 of 39 on
`298ac660ab037ae5` and again on the shipped `dda79f227497cc75`:

- the cold download at 20 Mbit/s shows its speed and the time left while it
  runs: 2.33 MB/s on the 2.5 MB/s line and 7.7 s left at 4.7 of 22.7 MB
  (`loading-panel-speed.png`); on the shipped image, 2.32 MB/s and 5.5 s left at
  4.7 of 17.4 MB;
- the state came down in 10 pieces, 8 on the smaller shipped state, each kept in
  the Cache API as `state.bin.zst?bytes=START-END`, and the load reported its
  phases in order: download, unpack, start. The second visit still asked for no
  piece of it.

| | `7580ed6dc2732d62`, 96 MiB | `7668214b5d9fad5e`, 128 MiB | `dda79f227497cc75`, shipped |
|---|---|---|---|
| The Extra card to `ready`, cold, 20 Mbit/s for the first 2.5 s | 2.9 s | 2.9 s | 2.9 s |
| The Extra card to `ready` again, from the Cache API | 354–442 ms, no request for the state | 377 ms, no request for the state | 445 ms, no request for the state |
| Run to the starter window on the canvas, 1× | 301–334 ms | 318 ms | 274 ms |
| A click on its button to the new label, 1× | 128–176 ms | 133–148 ms | 178 ms |
| Stop to `ended`, to parked, 1× | 2–3 ms, 50–73 ms | 3 ms, 80 ms | 2 ms, 48 ms |
| `while True`: EXIT after STOP, parked after the click | 11–16 ms, 50–64 ms | 15 ms, 47 ms | 13 ms, 48 ms |
| 4×: Run to the window, a click to the label, Stop to parked | 950–1,169 ms, 350–426 ms, 141–226 ms | 954–1,203 ms, 345–424 ms, 164–219 ms | 811–1,035 ms, 326–393 ms, 147–159 ms |
| Heap: catalog, the Tkinter page parked, after the runs, back on the catalog | 100.6, 298.6, 304.5, 111 MiB | 100.6, 331.3, 337, 111 MiB | 100.7, 333.9, 340.2, 117 MiB |
| Renderer footprint, the same four | 224, 400, 428, 244 MiB | 220, 433, 466, 240 MiB | 221, 448, 486, 272 MiB |
| All of Chrome, the same four | 522, 705, 767, 598 MiB | 505, 731, 786, 569 MiB | 499, 733, 808, 597 MiB |

**The heap did not shrink with the state.** The shipped image is 5 MB smaller to
download and its raw state 18 MB smaller, and the parked page is 2.6 MiB heavier
than at 128 MiB all the same: what the page holds is the guest's RAM, which is
still 128 MiB, and v86's wasm memory with it. The state's size is a download, not
a footprint.

On `eba47d0db90c25a8` every figure came out within the noise of the 128 MiB
column: the Extra card to `ready` in 2.9 s cold and 366 ms from the Cache API, Run
to the window in 325 ms, a click to the label in 129–169 ms, Stop to parked in 87
ms, and a heap of 331.5, 337.3 and 111.1 MiB parked, after the runs and back on
the catalog. On `298ac660ab037ae5` as well: 2.96 s cold and 368 ms from the Cache
API, Run to the window in 313 ms, a click to the label in 131–160 ms, Stop to
parked in 64 ms, and a heap of 331.3, 337.2 and 111.1 MiB.

The app itself with a parked VM is a 400–430 MiB renderer at 96 MiB and 433–466
MiB at 128 MiB, less than the bench's framed page, which holds two documents. The
32 MiB of guest RAM came out as 33 MiB more heap on the parked page, as "The
machine" expected. Leaving the page gives back about 190 MiB of heap and 185 MiB
of footprint at 96 MiB, and 226 MiB of each at 128 MiB.

**Five scenarios in a Dutch Chrome**, run at integration on the shipped bundle
and passing all 21 of their checks. A second one-off beside the gate, separate
from the hardening probe below, for the parts `check-app.mjs` has no case for. It
serves `build/web/` the same way, with single-Range answers, and runs Chrome with
`--lang=nl-NL` and `Accept-Language: nl-NL`:

- **The cold download at 20 Mbit/s, in Dutch.** Mid-download the panel read "De
  machine wordt gedownload", the steps "Downloaden › Uitpakken › Starten", "4,7
  van 17,4 MB" and "2,3 MB/s · nog ongeveer 10 seconden", against 2.33 MB/s and
  5.5 s from the event behind it. The state came down in 8 pieces, all kept.
- **A download interrupted by a reload.** Cut at 6.1 of 17.4 MB, the reloaded page
  showed "Het downloaden gaat verder waar het de vorige keer stopte" and was
  ready 8.9 s after the first byte; the server sent 17,393,727 B of state in all
  against a 15,301,311 B state, so 2.09 MB came twice.
- **A second visit with no network for the state.** With the server answering 503
  to every request for `state.bin.zst`, the page was ready in 1.0 s and asked for
  none. Then with the browser wholly offline: leaving the page destroyed the
  machine, and opening it again built a new one from the Cache API.
- **The crop.** The starter window shown at 175 × 106 and scale 1; a small window
  at 87 × 53, its messagebox widening the crop to 340 × 94 and OK shrinking it
  back; a 1920 × 1080 canvas at 800 × 600 and scale 0.63, with clicks aimed at
  (400, 300), (780, 580) and (15, 20) landing at (400, 300), (779, 579) and
  (14, 19).
- **Keyboard only.** The editor states "Esc, dan Tab: verlaten" while it has the
  keyboard, a plain Tab stays in it, and Escape then Tab moves on to the display.
  One more Tab reaches "Uitvoeren" and Enter starts the run. With the program
  running the display holds the keyboard, typing reaches the Entry, and Escape
  then Tab moves to "Stoppen", after which nothing typed reaches the guest;
  Shift+Tab goes back.

**The hardening step's fixes, in Chrome.** A probe run beside `check-vm-app`, on
the same build with Chrome set to Dutch (`--lang=nl-NL` and `Accept-Language`,
which the app follows as the device locale), passed 21 of 21. It is a one-off and
not in the repository:

- **The layout switch.** With an Entry program running and holding the keyboard,
  the window went 1100 → 1000 → 1100 → 1023 → 1024 px wide, across `lg` each
  time. The display moved between the two columns and the stacked layout as the
  same `.icc-vm-view`, the only one, and kept DOM focus and the leave hint; keys
  typed after every switch reached the Entry with no click, 5 of 5.
- **A full-HD Canvas.** A 1920 × 1080 Canvas was drawn 503–506 ms after Run, in
  its colours, and the program ran on with no stderr and no notice. A 3000 × 3000
  one ended with code 1 and `BadAlloc`, and the page showed the too-large notice
  rather than the crash notice.
- **Retry after a failure.** The server held the state's download for 4 s and
  then answered 404, and Run was pressed meanwhile: the waiting run ended
  `broken`, the page showed the download failure card and no run notice, and
  Retry, with the server answering again, came back `ready` with no notice.
- **A 404 at once.** With the state answering 404 at once, while the wasm was
  still arriving, the page stayed on its loading panel for good ("2,1 van 22,7
  MB", no Retry): the host sent `progress` after `failed`. Once the other
  download was aborted and the view model took no byte count while failed, the
  host's events after navigation were `failed` alone, the download failure card
  stayed, and Retry came back `ready`.
- **The editor by keyboard.** In Dutch, with semantics on and the state failing:
  the page opened with the keyboard outside the editor, the first Tab reached it
  and the hint, a Tab alone indented the draft by two spaces, Escape then Tab
  went on to Retry and then "Technische details", and Enter on Retry loaded the
  machine. Escape then Shift+Tab left backwards, to the bar. Without semantics,
  typing after that first Tab landed in the draft. A lesson step still opened
  with the keyboard in its editor.
- **A replaced machine.** A second `openVm()` from the page's console gave the
  page `failed` (`replaced`) and the broken card, the only one it had for that
  then. Measured again once `VmFailure.replaced` had a card of its own, the page
  showed it ("Een andere Tkinter-pagina heeft de machine overgenomen") with the
  host's message folded. Retry opened a new machine, which ran the starter
  program.
- **A double click on the Extra card**, then a third tap, opened one page and
  called `openVm()` once. A control build without the catalog's guard opened two
  pages from the same clicks, the second taking the first one's machine.
- **A build without `ICC_VM_IMAGE`**, with `vm/image/` removed from its output as
  on a deploy with no pin: the catalog's Extra section has no Tkinter card,
  `#/learn-python/tkinter` says "Tkinter zit niet in deze versie van de app", and
  nothing under `vm/` is requested.

Two traps in driving it. A click at 4× from Flutter UI straight onto the display,
the pointer moved and pressed in one go, reaches Tk: traced, the capture-phase
`pointermove` still sees v86's mouse off, the route has turned it on by the
bubble phase, and v86's `mousemove` and `mousedown` come after that. And
re_editor pairs brackets and quotes typed one key at a time, so the check puts a
program in the editor a line at a time through `insertText`, as an IME does.

### Found on the way

**The agent sends WINDOW late and gives focus late.** x11rb reads events while
it waits for a reply, into its own queue. The event loop drains that queue at
the top of every wake (see "Traps"), but `Supervisor::on_tick` then sends the
window list, and `Watcher::windows()` waits for replies. Events that arrive
meanwhile, a MapNotify among them, wait in the queue while `poll(2)` sleeps on a
socket that has nothing new. The next PING, 2 s of active time later, wakes it.
At 1× the timing never lines up; at 4× and 6× it does:

| CPU | WINDOW, agent left alone (ms) | WINDOW, agent woken every 50 ms (ms) | Late by a PING, alone / woken |
|---|---:|---:|---:|
| 1× | 270 (210–275) | 271 (228–286) | 0 of 8 / 0 of 8 |
| 4× | 1,564 (858–2,245) | 970 (917–1,029) | 4 of 8 / 0 of 8 |
| 6× | 1,395 (1,366–2,316) | 1,547 (1,465–1,614) | 3 of 8 / 0 of 8 |

In the late runs the window was on the canvas about a second before its WINDOW,
so the app's title bar would lag the window's content. The focus given on that
MapNotify is late the same way, which is the input failure above. The fix is in
`vm/agent`: drain the X connection's queue after anything that waited for a reply,
before `poll(2)`. Waking the agent with empty frames, as the bench does, only
proves the cause; it costs guest CPU (label took 1,059–1,171 ms to the canvas
woken at 4×, against 936–1,031 left alone).

Fixed in the agent since: the X watcher has a thread of its own, handles every
queued event after each reply wait, and keeps the list from the events ("The X
watcher"). Under Node the corpus's `window-follows` and `x-grab` hold it. In
Chrome, on the final image, every WINDOW of 48 runs reached the page before the
window's pixels, by 38–58 ms at 1×, 100–230 ms at 4× and 165–320 ms at 6×, and
waking the agent now only slows it ("final" below).

A trap in the bench itself: Puppeteer's `keyboard.type('S')` presses no Shift,
and v86 sends the physical key, so the guest gets `s`. The input check presses
Shift itself.

### What to do

**Park from a raw state, made once per page in a worker.** The zstd restore was
the only long task the VM caused, it came after every run, and on a 4× machine
it froze the page for half a second, 0.8 s at 6×. The host downloads and caches
the zstd state as before, decompresses it once in a worker of its own, which it
ends at once rather than keep v86's worker and its 173 MiB, and restores the raw
`ArrayBuffer` at the load and at every park: 89–132 ms at 4×, 155–191 ms at 6×,
and at 1× under 50 ms, no long task at all ("park" above). A worker per park
would be no better: it adds 110–160 ms before the same raw restore on the main
thread. Never decompress on the main thread, which blocks nearly as long as the
zstd restore does and grows the wasm memory. If 71.7 MiB of raw state turns out
to be too much, keep it in Cache Storage instead: 72–106 ms to read back at 4×
and 6×, off the thread, and nothing kept in memory.

**Memory is over the design's 400 MB, and acceptable for one tab.** The app with a
parked VM is a 496–506 MiB renderer and 743–762 MiB of Chrome, framed by the
bench; the app itself measured 400–430 MiB and 705–767 MiB at 96 MiB, and
433–466 MiB and 731–786 MiB at 128 MiB, and leaving the Tkinter page gives
185–226 MiB of that back ("The app in Chrome"). The VM's share,
about 290 MiB of footprint, is mostly v86's 147 MiB of wasm memory, which
holds all 96 MiB of guest RAM (128 MiB now, which adds 32 MiB to that: "The app
in Chrome"). Two such tabs are 1.2 GB of Chrome, a large share
of a 4 GB Chromebook, where ChromeOS discards tabs under memory pressure. So the
VM must exist only while its screen is open, and be destroyed when the student
leaves it, because parking does not give memory back. Raw-state parking is roughly
neutral here. A real Chromebook has to show where ChromeOS starts discarding.

**It breaks by degrees, and the page breaks it sooner than the CPU does.** With
an idle page, 4× is usable (a window 1.0–1.8 s after Run, animations at 15 of 20
steps), 6× is slow (1.7–2.7 s, 13 steps), and from 8× a ttk window takes over
3.5 s and a park a full second. Nothing failed outright even at 40×, where one
STOP outlasted its grace. But a page that
spends 6 ms on every frame leaves v86 3 % of its speed at 4×, with windows taking
6.8 s. The Dart side must therefore keep the Tkinter screen still while a program
runs: no spinner, no animated progress, nothing that repaints every frame. The
host replaces v86's yield with a `MessageChannel`, which costs nothing on an idle
page and helps under load, by 10 to 25 % rather than the three to five times
first measured ("frame-load"); it softens the rule, and does not lift it. If the
screen ever has to animate during a run, the answer is v86 in a worker, which
also takes the restore off the main thread; that is a redesign of the host and
`vm_screen.js` and is not measured.

**Fix the agent's X queue before the Dart work.** Flutter draws each window's
frame from WINDOW, and typing into a dialog without clicking depends on the
focus that comes with it. Done (see "Found on the way").

## Traps

Found while building this, each the reason for something above.

- **GitHub Pages answers a Range with a range of what it would send.** For a
  client that accepts gzip, a Range on a file Pages compresses (the wasm, the JS)
  comes back as a 206 of the gzip, `Content-Range: bytes 0-99/1268316` for a
  4,303,440-byte file (probed with `curl` against the deployed site). A browser
  asks for `identity` with a Range, per the Fetch standard, so this should not
  happen to a page; the host holds every 206's total to the manifest's size all
  the same, and asks once more without a Range when it differs.
- **`flutter run`'s dev server ignores Range, and answers a missing file with
  `index.html`.** A 200 for every Range, which the host reads as the whole file
  in one request, and a 200 of HTML where a 404 was meant, which the size check
  refuses.
- **Chrome's offline mode does not drop a response under way.** CDP's
  `setOfflineMode` holds it, and it goes on once the page is online again, so a
  bench that went offline for 3 s part way through lost nothing either way and
  measured nothing. `serve.mjs`'s `cut(ms)` destroys the connections instead, as a
  Wi-Fi that goes away does.
- **Puppeteer's `page.reload()` drops the fragment.** The app routes on the
  hash, so a reload meant to interrupt a download on `#/learn-python/tkinter`
  came back at the language picker, and nothing resumed because nothing asked
  for the machine. A check that reloads has to call `location.reload()` in the
  page and wait for the navigation.
- **`flutter test` draws every glyph as a square a whole em wide.** A layout
  that fits in the app's fonts overflows under it, so the loading panel's fit
  is tested with the real fonts loaded, in a file of its own
  (`vm_load_panel_fit_test.dart`).

- **`/tmp` in the guest is a tmpfs over the 9p root.** A file the host writes to
  `/tmp` with `create_file` lands in the 9p tree under the mount, where the guest
  cannot see it. `/icc/in` is on the root itself, read-only to the guest but not
  to the host.
- **A run through `openVm()` always ends in a park.** A park restores everything,
  the debug shell included, so a shell command still running when the program
  ends is lost with its output. Checks that need the guest to stay put drive the
  machine directly, as `park-detectors` and `cold` do.
- **With the debug shell, the unasked READY comes before anyone listens.**
  `bootImage()` waits for the shell, and the agent is up by then, so
  `build-state.mjs --debug-shell` greets it with HELLO instead of waiting.
- **PREPARE has to fit in 4,096 bytes.** A resident pattern that matched every
  zone under `Europe/` made the payload 5,025 bytes.
- **The zero-fill's safety depended on watermarks that move.** After a
  fragmentation event the kernel boosts its watermarks for a while; two builds
  had a Normal zone minimum of 4.7 MiB rather than 0.65, and the fill, which
  stops 2 MiB above zero free, reclaimed mapped pages. Boosting is off now.
- **The agent's own binary is a mapped file too.** Left off the read-back, it was
  the one rootfs fetch after a restore.
- **x11rb reads events while it waits for replies**, into its own queue rather
  than the socket, so an event read that way waits for whatever next makes the
  socket readable. The watcher handles every queued event after each reply wait
  and before it polls; it used to do so only at the top of each wakeup, and a
  MapNotify read while it waited sat there until the next PING.
- **Tk does not always stack windows in the order it opens them.** Of twelve
  Toplevels opened 5 to 80 ms apart, the first two came out the other way round
  in one of three runs of a probe that asked the server (`wm stackorder`); the
  agent's list matched the server every time. The corpus holds the list to what
  the server says, not to the order the program opened the windows in.
- **Nothing the agent asks of X may be on the thread that answers PING.** Another
  client can grab the server, and a large drawing keeps it busy for seconds;
  either left the agent waiting for a reply while the host's watchdog ran out.
- **Anything the prelude can do, the program can do.** They share a process, so
  its status pipe is the program's too: 2,000 hint lines from a program reached
  the host as 2,000 HINT frames, past `output_cap`. The agent believes each line
  once per run.
- **A process leaves its process group with `setsid()`, but not its cgroup.** A
  grandchild in a session of its own outlived both a stop and a program's exit
  under `killpg`; `cgroup.kill` ends it.
- **Moving a process into a cgroup does not move its memory.** Only what it
  allocates afterwards is charged there, which is what lets the warm interpreter
  join the run's group at the handover and bring none of its warm-up with it.
- **The kernel charges a cgroup 64 pages at a time.** `memory.peak` reads 256 kB
  for a run that allocated almost nothing.
- **Xorg's memory is not the program's.** A pixmap a program asks for is Xorg's
  allocation, charged to Xorg's cgroup, and no OOM kill of the program frees what
  the request is still waiting for. `RLIMIT_DATA` fails the request instead.
- **A fork of the warm interpreter warns.** Tcl's notifier thread is running
  from the warm-up, so `os.fork()` prints the `DeprecationWarning: This process
  ... is multi-threaded` that CPython has raised since 3.12 to the program's
  stderr. Tcl starts that
  thread the first time it handles events, not when it creates an interpreter
  (checked with the image's `python3`: `Tcl()` left one thread, `update` made
  two), so a cold program that forks before its window is up sees no warning.
- **Tk's `.` is a child of the X root until its first map.** Only then does Tk
  wrap it, so the top-level the agent reports is found as `.`'s parent, and a
  window counts only once it has been mapped.
- **The kernel tears a python3 with Tk down slowly.** 70 to 230 ms after SIGKILL
  in v86, which is why EXIT for a stop does not wait for the reap.
- **A run that ends the moment a fetch fails loses its last output.** The agent
  batches output for up to 16 ms; the host now waits 50 ms before it ends the
  run as `fetch`.
- **A message box is slow the first time in each interpreter.** The handed-over
  root is a new interpreter, so the warm-up's `msgbox.tcl` was gone; the prelude
  loads it into the handed-over root now.
- **Linux-only agent code is invisible to clippy on a Mac.** `just test-vm-agent`
  also lints for `i686-unknown-linux-musl`, which caught a deprecated `time_t`.
  Clippy holds the code to the crate's `rust-version`, not to the Rust that
  builds the image: at 1.87 it refused a let chain that Alpine 3.24's 1.96
  builds. So `rust-version` moves with the Alpine pin.
- **Node's mocked `Date` jumps to the end of a `tick()` before intervals run.**
  The watchdog adds at most 100 ms per sample, so a long mocked tick looks like a
  stalled thread; the tests step time 100 ms at a time.
- **The shipped kernel runs with its lockup and stall detectors off.** A park
  that prints nothing proves little on its own, which is what `park-detectors` is
  for.
- **v86's `zstd_decompress_worker` needs `wasm_source`**, which v86 sets only
  when it fetches its wasm itself. The host hands it a `wasm_fn` instead, so that
  worker would start from `undefined`; the host runs the same decoder in a worker
  of its own.
- **A raw restore copies the state, a zstd one decompresses it.** v86's raw path
  takes every buffer out of the state with `slice`, so nothing the guest does
  afterwards writes into the raw state the host keeps, and restoring it again and
  again is safe. The zstd path decompresses into fresh buffers, and grew v86's
  wasm memory by 35 MiB doing it.
- **A zstd frame without a content checksum decompresses garbage quietly.** A
  corrupted download that still had the right size decompressed rather than
  failing, and only the restore, or the HELLO after it, found out. `build-state.mjs`
  sets zstd's checksum flag and fails the build without it; v86's decoder then
  refuses a corrupt state, as a wasm trap rather than a named error.

- **With semantics on, Flutter web puts DOM focus on the focused semantics node.**
  The display's `Focus` added one, which took DOM focus from the platform view the
  moment Run gave the display Flutter focus, and the view's `focusout` switched
  the guest's keyboard off. The `Focus` in `VmDisplay` adds no semantics now.
- **A 200 is not the file.** A captive portal answers any URL with a page of its
  own, and a proxy can cut a body short. Cached as it came, either one failed
  every later load with "wrong size", Retry included, until the student cleared
  the site's data. The host checks size and sha256 before it caches now.
- **v86 has nothing to free until `wasm_fn` resolves.** It sets `v86`, the
  instance with the ~150 MiB memory, only then, so a host destroyed while it
  loaded skipped the free, and the emulator that finished loading afterwards
  stayed for the life of the page. `destroy()` waits for the load now.

## Not done

- Only headless Chrome on an M1 has run any of this in a browser, with CPU
  throttling standing in for a Chromebook ("Measurements"). No real Chromebook,
  Firefox or Safari has: not the Cache API loading, the Range pieces, the image
  locks, the state's decompression worker, the `MessageChannel` yield or
  `vm_screen.js`. Whether Firefox and Safari send `Accept-Encoding: identity` with
  a Range, as the Fetch standard says, is untested; the `Content-Range` check
  catches a compressed range either way, at the cost of one request.
- **Nothing starts a download before the page opens.** `prefetchBundle()` and the
  one-download-per-image it joins are built and tested, but what calls it (a
  click on a lesson or card that needs the machine) and the catalog card that
  shows its progress are a design of their own. Until then the Tkinter page's
  own `load()` is the only caller.
- **Offline, the VM's own files are served and the app's are not.** The
  manifest, `libv86.mjs`, `v86.wasm`, the state and the rootfs files a program
  fetched before all come from the Cache API without a network, so a page that
  is already open keeps working when the Wi-Fi goes. A reload without a network
  needs `main.dart.js` and the rest of the app, which only the browser's HTTP
  cache holds; that is the app's service worker question, not the VM's.
- **A reload loses the pieces that were under way.** The page is gone before a
  piece cut short can be kept, so a reload at 40 % keeps what had landed and
  fetches the two or three pieces in flight again (up to 6 MiB; "download"). On
  the shipped image, cut at 6.1 of 17.4 MB in Chrome at 20 Mbit/s, the server
  sent 17,393,727 B of state against a 15,301,311 B state: 2.09 MB came twice.
  A dropped connection loses nothing: the page is still there to keep them.
- **v86.wasm does not resume.** It is one request with no Range, so a connection
  that drops 1.9 of its 2.1 MB in starts again at zero, four times before the
  load fails ("The host"). Routing it through the piece reader would fix it and
  cost the state's bookkeeping on a file an eighth its size; the state was worth
  it and this is not, yet.
- The decompression worker runs only in a browser. Under Node, where the tests
  run, the same decoder runs in place; the worker's own message path is covered by
  the bench alone.
- The Dart side has run in headless Chrome with a mouse and a keyboard (`just
  check-vm-app`). Touch, an on-screen keyboard, IME and a real screen reader have
  not; with semantics turned on by hand, the keyboard reaches the guest and the
  frame's title is read.
- STDIN (`input()` gets EOF) and files the program writes, both **later** in the
  protocol.
- **A menu, combobox list or tooltip that reaches past the program's windows is
  cut off.** The page crops the display to the region around the windows WINDOW
  lists, and WINDOW leaves override-redirect windows out (README 6.7), so a
  dropdown that hangs below a small window is clipped where the window ends.
  Needs the agent: a `popups` field on WINDOW, `{x, y, w, h}` per mapped
  override-redirect child of the root, which a v1 receiver ignores, passed on by
  `vm_run.js` and added to `windowRegion`.
- **The screen between windows is black.** Inside the region, what no window
  covers (beside a dialog wider or taller than the window it belongs to) is the X
  root's own background, which Xorg paints black. The frame around it is the
  code surface, `codeBackground`: #171717 in the neutral preset, a shade from
  black, and THUAS's greys, which are further. The page cannot change it: a run
  starts from the warm snapshot, so anything a run sets is gone with it, and only
  the image can. The agent could set the root's `background_pixel` and clear it
  once Xorg answers, before the snapshot is taken; one colour baked into the
  image cannot follow the preset, so #171717 is the one to take.
- **The first turtle drawing of a run is a second slower than the rest** ("Turtle").
  The warm-up draws every widget once but nothing with turtle.
- **A cold interpreter skips the page's setup.** It is `python3 main.py`, with no
  prelude to run `icc_setup.py`, which then sits in the work directory beside the
  program. A cold run only happens after a park failed.
- The PR and deploy workflows run `just test-vm` and the steps of `just
  test-vm-agent`, and fetch and check the pinned image when there is one, but
  build none and boot none. `vm-image.yml` builds one and runs the corpus on it,
  and has not run on GitHub yet. Nothing in CI runs `just check-vm-app`.
- No image is published: `vm/image.lock` does not exist, so every deploy leaves
  the Tkinter page out until "Publishing the image" has been done once. Neither
  workflow's new steps have run on GitHub; the fetch was tried against a local
  file and a local server that redirects, as a release download does.
- Every run shares the warm interpreter's hash seed, so the iteration order of a
  set of strings is the same on every run. This one is a limit rather than work
  left: "The warm interpreter" says why a warm interpreter cannot change it.
- The run's memory budget, about 39 MiB of new memory, is what the guest's 128 MiB
  leaves once Xorg has room for a full-HD Canvas, and a run's files come out of
  it. A 1920 x 1080 PhotoImage shown on a Canvas of its size needs two full-HD
  pixmaps at once and is still a BadAlloc: 4 MiB more for Xorg would cost the
  budget as much, or the page as much wasm memory.
