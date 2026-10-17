# The Tkinter VM: runbook

How to build, update, check and publish the guest image the Tkinter page runs
in. The reasons behind every step, and everything measured, are in
[docs/vm-build.md](../docs/vm-build.md); "Regenerating the image" there covers
this page.

## The pieces

| Where | What |
|---|---|
| `vm/image/Dockerfile` | The guest: Alpine Linux for i386, its Python with Tk, Xorg. `ARG ALPINE_VERSION` is the one place the Alpine release is named. |
| `vm/image/files/` | What the guest gets on top of Alpine: config, the warm interpreter's `prelude.py`. |
| `vm/image/kernel/configure.sh` | Cuts Alpine's `linux-virt` config down to what v86 offers. The Dockerfile's `kernel` stage builds that config from kernel.org source. |
| `vm/image/packages.lock` | Every apk package in the image, with version, licence, origin and aports commit. Written by the build; commit it with the image. |
| `vm/agent/` | `icc-agent`, the guest process the page talks to (Rust). |
| `vm/tools/` | The build, the checks, packaging and fetching. |
| `vm/image.lock` | The pin: which released image a deploy ships. Not created yet. |
| `vm/build/`, `web/vm/image/` | Build output and the bundle the page loads. Both gitignored. |
| `.github/workflows/vm-image.yml` | The same build on a GitHub runner, monthly and by hand. |

The bundle carries a `NOTICES.txt`: the licences of everything in it, and where
the source of each package is.

## Prerequisites

- Docker with `linux/386`. On Apple silicon that is QEMU, which Docker Desktop
  brings; on an x86_64 Linux host it runs natively.
- Node 22.15 or newer, Python 3.14 (or any Python 3 with `zstandard`), and `just`.
- Network: Alpine's mirrors, and GitHub for the BIOS images.
- 5.5 GB free disk. The build stops with `DISK_LOW` below that.

## Build

```bash
just build-vm-image
```

Builds the pinned Alpine release into `vm/build/` and the bundle into
`web/vm/image/`, and rewrites `vm/image/packages.lock` from the image. Docker's
cache is used, so the packages are the ones the cached layers hold. About
5.5 min on an M1 when the agent changed, well under a minute when only
`vm/image/files/` did.

## The kernel

The guest does not boot Alpine's `linux-virt` binary. The Dockerfile's `kernel`
stage downloads the same version from kernel.org, checks it against the
`sha256sums.asc` beside it, applies `vm/image/kernel/configure.sh` to Alpine's
own config, and builds it. No kernel binary is committed: `just build-vm-image`
reproduces it, and the source tarball is kept in a Docker cache mount so the
tree never becomes a layer.

`configure.sh` cuts the config down to the one machine it has to run on. v86
offers one CPU and no ACPI, the root is 9p so there is no block layer, and with
the module loader off everything the guest used to load is built in, which is
why the image needs neither `mkinitfs` nor `/lib/modules`. Its `NEEDED` list is
what the guest cannot boot without, and the script exits 1 when `olddefconfig`
has dropped one of them. That is the check that catches a kernel moving an
option: **which helpers `bochs-drm` selects already changed between 6.12 and
6.18.**

It costs about 4.5 min cold on an M1 (`-j8`, clang cross-compiling for i386)
and nothing at all afterwards, since only a new Alpine release changes the
stage's inputs. What it buys is in docs/vm-build.md, "The kernel": on Alpine
3.24.2, 4.4 MB off the state, 11.5 MB more run budget, and faster first windows.

**When the Alpine pin moves, read the kernel diff.** `vm/build/kernel.txt`
names the version, the source URL and its checksum; `vm/build/kernel.config` is
the config that was built. A new kernel can rename or re-parent an option, and
`configure.sh` only catches that for the options in `NEEDED`.

## Update to the newest Alpine

```bash
just update-vm-image
```

1. Asks Alpine for its newest stable release for x86 and writes it into
   `ARG ALPINE_VERSION` in `vm/image/Dockerfile`.
2. Rebuilds with `--pull` and without Docker's cache for the image's layers, so
   every package is what Alpine publishes today.
3. Saves the warm machine and the bundle, then runs `check-vm-image`,
   `check-vm-state` and the corpus.
4. Prints what moved against the committed `packages.lock`, kept in
   `vm/build/packages.diff`, and which corpus cases fetch more than they did on
   the image the app had, kept in `vm/build/corpus-fetches.txt`.

17 min on an M1 for the move to 3.24, whose new base image also rebuilt the agent
under QEMU. Flags:

| | |
|---|---|
| `--alpine 3.24` | That release rather than the newest. With the pinned one, it is a rebuild with today's packages. |
| `--keep-pin` | Build without writing the Dockerfile. |
| `--skip-corpus` | Leave out the five minutes of student programs. |
| `--tag NAME` | The Docker image's name (`icc-vm-image`). |

**A trial that touches nothing**: `ICC_VM_BUILD_DIR=vm/build/next just
update-vm-image --keep-pin --tag icc-vm-next`. Everything, the bundle
included, goes to that directory; `vm/build/`, `web/vm/image/` and the
committed lock stay as they were.

**A run that fails puts the committed files back.** The new release is written
into the Dockerfile before the build and the new `packages.lock` lands on the
committed one as soon as the image builds, so a failing check would otherwise
leave the tree pinning a release nothing checked. The failure says which files
were put back. The one it cannot undo is `web/vm/image/`, which by then holds
the bundle that failed: `just build-vm-image` at the restored pin, or `just
fetch-vm-image`, brings a checked one back, and the failure says so too.

After an update, before committing:

- Read the package diff. A new Python minor version is the one to take slowly:
  the prelude and the corpus are held to what `python3 main.py` does, and that
  changes between minor versions.
- Read the `Fetches:` line at the end, kept in `corpus-fetches.txt`: the corpus
  cases that fetch more than on the image the app had. A case the earlier report
  does not name is listed as `new case`, since a case added in the same round as
  the image is the likeliest to reach for something nothing warms. A new fetch is
  usually a module the prelude should import in its warm-up. That is how the move to 3.14
  went: the first traceback of a run fetched eight, and `prelude.py` importing
  `traceback` took it back to none (docs/vm-build.md, "The move to Alpine 3.24").
  No check fails on it, because a fetch is slow rather than wrong.
- `git diff vm/image` shows the pin and the lock. Commit both, and publish the
  image built from them (below), or the deploy keeps shipping the old one.

## Check

```bash
just check-vm-image      # the image booted: X, input to Tk, imports without fetches
just check-vm-state      # the bundle restored the way a page restores it
just check-vm-corpus     # student programs through the page's host (needs the debug bundle:
                         # just build-vm-state --debug-shell)
just test-vm             # the host and the protocol against fakes; no image needed
just test-vm-agent       # the agent's fmt, clippy and tests
just build && just check-vm-app   # the app in headless Chrome
```

`update-vm-image` runs the first three. Only `check-vm-app` needs a browser.

## Package and publish

```bash
just package-vm-image
```

Writes `vm/build/vm-image-<imageId>.tar.zst`, its `.sha256`, and the pin for
it, `vm/build/vm-image-<imageId>.lock`. It refuses a bundle that is not what the
tree builds, a debug bundle, one without `NOTICES.txt`, and one whose
`NOTICES.txt` names a copyleft licence it carries no text for. Then build the
source archive (below), and by hand:

```bash
gh release create vm-image-<imageId> vm/build/vm-image-<imageId>.tar.zst \
  vm/build/source/vm-image-<imageId>-source.tar.zst \
  web/vm/image/<imageId>/NOTICES.txt --latest=false --title "VM image <imageId>"
cp vm/build/vm-image-<imageId>.lock vm/image.lock
just fetch-vm-image --force       # downloads it back and checks it, as a deploy will
git add vm/image.lock vm/image/packages.lock vm/image/Dockerfile
```

Nothing is published until that release exists and `vm/image.lock` is
committed. The pin must match the tree it is committed with: `just
check-vm-image-pin` says whether it does.

**On GitHub instead**: run the *VM image* workflow. By hand it rebuilds the
pinned release, or the newest with *latest* ticked; on the first of each month
it updates to the newest on its own. Its artifact holds the archive, the pin,
`NOTICES.txt`, the lock and its diff, the reports, and `pin.patch`, the
Dockerfile and lock changes it was built with. Apply `pin.patch`, commit it
with the pin, and the tree matches the image. The *publish* input creates the
release too; it is off unless ticked, and committing `vm/image.lock` stays
yours either way.

## The source archive

Every release that carries an image carries
`vm-image-<imageId>-source.tar.zst` beside it: the source of the GPL and LGPL
parts, from the same place the binaries come from. `NOTICES.txt` in the bundle
promises that asset by name, so a release without it leaves the notices wrong as
well as the licence unmet. Why it is an asset and not a link is in
[docs/vm-build.md](../docs/vm-build.md), "Licences".

No tool builds it. What must be in it:

| Part | What | From |
|---|---|---|
| Alpine packages | `main/<origin>/` or `community/<origin>/`, at the commit that package was built at. One directory per distinct origin and commit in `vm/image/packages.lock`, which is where both come from. | <https://gitlab.alpinelinux.org/alpine/aports> |
| Their upstream archives | Every remote file those APKBUILDs name in `source=`, held to the APKBUILD's own `sha512sums`. A patch in `source=` is a file in the aports directory already. | `https://distfiles.alpinelinux.org/distfiles/v<major>.<minor>/<name>`, and the URL in the APKBUILD for anything it does not keep |
| The kernel | The tarball the `Linux` section of `NOTICES.txt` names, checked against the sha256 it names there. The config and the Dockerfile that build it are this project's own sources. | <https://cdn.kernel.org> |
| SeaBIOS | The `bios/` directory of the v86 commit `NOTICES.txt` names, and the SeaBIOS source its `fetch-and-build-seabios.sh` names. | <https://github.com/copy/v86> |
| This project | The whole repository at the commit the image was built from, which is the manifest's `sourceHash`. | here |

A start, which needs a person's eye and has never been run end to end:

```bash
id=$(sed -n 's/.*"imageId": "\([^"]*\)".*/\1/p' web/vm/image/manifest.json)
branch=v$(sed -n 's/^# Alpine \([0-9]*\.[0-9]*\).*/\1/p' vm/image/packages.lock)
out=vm/build/source/$id
mkdir -p "$out/aports" "$out/distfiles"

# Every origin with the commit it was built at: columns 4 and 5 of the lock.
git clone --filter=blob:none https://gitlab.alpinelinux.org/alpine/aports.git vm/build/aports
awk -F'\t' '!/^#/ && NF >= 5 && $5 != "" { print $4 "\t" $5 }' vm/image/packages.lock | sort -u |
  while IFS=$'\t' read -r origin commit; do
    for repo in main community; do
      git -C vm/build/aports archive --prefix="aports-$commit/" "$commit" -- "$repo/$origin" 2>/dev/null |
        tar -x -C "$out/aports" && break
    done
  done

# What each of those names in source=. abuild reads an APKBUILD as a shell script,
# and `newname::url` renames the file it keeps.
for build in "$out"/aports/*/*/*/APKBUILD; do
  ( . "$build"
    for item in $source; do
      case "$item" in *://*) ;; *) continue ;; esac
      name=${item%%::*}; [ "$name" = "$item" ] && name=${item##*/}
      curl -fsSL -o "$out/distfiles/$name" "https://distfiles.alpinelinux.org/distfiles/$branch/$name" ||
        curl -fsSL -o "$out/distfiles/$name" "${item#*::}"
    done )
done

git archive --prefix="i-can-code/" HEAD | zstd -o "$out/i-can-code.tar.zst"
tar -C "$out" -cf - . | zstd -19 -o "vm/build/source/vm-image-$id-source.tar.zst"
```

Before uploading it, check that every origin and commit pair in the lock has a
directory, that every APKBUILD's `source=` has its file, and that a few of those
files match the APKBUILD's `sha512sums`. Expect a few hundred MB, which is
under GitHub's 2 GB per asset. Keep it for as long as the image it belongs to.

Where there is no archive, `NOTICES.txt` carries a written offer instead, good
for three years and made to any third party. Taking that route means being able
to answer it for three years. The archive is the plan.

## Licences

`NOTICES.txt` lists v86's BSD-2-Clause licence, the SeaBIOS the saved machine
holds (LGPL-3.0), every Alpine package with its SPDX licence and aports commit,
and the agent's crates, and it ends with the text of every licence any of them
declares. The texts are in [`vm/licences/`](licences/), whose `README.md` says
where each came from and how to add one; `just package-vm-image` refuses a
bundle that names a copyleft licence and carries no text for it. To correct a
text or a wording afterwards, edit it and run `node vm/tools/write-notices.mjs`,
which writes `NOTICES.txt` into the bundle again and needs no rebuild. The whole
picture, the source archive included, is in
[docs/vm-build.md](../docs/vm-build.md), "Licences".
