# Licences

The app is under the Mozilla Public License 2.0, the `LICENSE` at the repository
root. It ships a good deal that is not its own: Dart packages and the Flutter
engine, a CPython build with pytest baked in, the Rust core's crates, four fonts, a firmware image
and one vendored script, and in a build with the Tkinter page a Linux image. The licence screen (`/licenses`, under *Licenties* in
the cog) shows the licence of the app and of every one of those.

This document says where each text comes from, what rewrites it, and what was
checked about the licences going together. The lessons are not covered here or
on the screen: they are content, with a licence of their own.

## How a text reaches the screen

Everything goes through Flutter's own `LicenseRegistry`, which needs no
Material. Two things feed it:

- **Flutter's NOTICES.** The build collects the `LICENSE` of every package in
  `.dart_tool/package_config.json`, the engine's among them (Skia, HarfBuzz,
  ICU and the rest). The app is a package in that file too, so **the `LICENSE`
  at the repository root is in NOTICES under the name `i_can_code`** without
  anything being done for it. `kAppPackage` is that name, and the screen shows
  it first, under the app's title.
- **`kBundledLicenses`** (`lib/services/licenses/bundled_licenses.dart`), for
  what Flutter cannot know about. Each entry is a text file shipped as an
  asset, the origin the screen groups it under, and the names it covers.
  `registerBundledLicenses()` hands them to the registry from `setupServices()`.
  It registers a callback and reads nothing, so the files are only fetched when
  the screen is opened.
- **The VM image's `NOTICES.txt`**, in a build that ships the image. It is not
  an asset: `web/vm/image/` is served beside the build, so
  `registerBundledLicenses()` adds it as a fetch of the file the image's
  `manifest.json` names, held to the size the manifest gives. See *The Tkinter
  VM* below.

`LicenseCatalog` then turns "a text and the packages it covers", which is what
the registry holds, into "a package and the texts that cover it", which is what
a reader looks for.

The NOTICES lists packages that only the build uses, `build_runner` and the
analyzer among them. Flutter does not tell them apart and neither does the
screen. Naming too many is harmless.

Rust has nothing like `LicenseRegistry`. A crate states its licence in
`Cargo.toml` and that is all cargo knows, so a tool has to collect the texts at
build time; see *Rust* below.

## Where each text comes from

| Shown under | Files | Source | Rewritten by |
|---|---|---|---|
| The app | `LICENSE` | MPL 2.0, verbatim from mozilla.org | by hand |
| Python | `assets/python/licenses/` | CPython, wasi-libc and LLVM, at the versions the build used; pytest and its dependencies, from their wheels | `tool/fetch_python_licenses.sh`, then `tool/bake_pytest.py` |
| Rust | `assets/licenses/rust-*.txt` | the crates in `rust/Cargo.lock`, and the standard library of the pinned toolchain | `just gen-rust-licenses` |
| micro:bit | `assets/microbit/licenses/` | the parts of the MicroPython firmware | by hand, see below |
| Fonts | `assets/fonts/OFL-*.txt` | each family's own OFL text | by hand, with the font |
| Other | `assets/licenses/coi-serviceworker.txt` | the `LICENSE` of gzuidhof/coi-serviceworker | by hand |
| Tkinter | `web/vm/image/<imageId>/NOTICES.txt` | the VM image's own notices, with every licence text it needs | `build-state.mjs`, or `vm/tools/write-notices.mjs` |
| Dart & Flutter | none | Flutter's NOTICES | every build |

Two tests in `test/services/bundled_licenses_test.dart` hold the list to the
files. A licence file in one of those directories that `kBundledLicenses` does
not name fails one, because nobody would be shown it. A file the list names
that is not in the built bundle fails the other, which is what an asset left
out of `pubspec.yaml` looks like.

## Rust

`just gen-rust-licenses` runs [cargo-about](https://github.com/EmbarkStudios/cargo-about)
twice and writes `assets/licenses/rust-crates.txt`:

1. Over `rust/Cargo.toml`, with `rust/about.toml`.
2. Over the standard library's own manifest in the pinned toolchain's
   `rust-src`, with `rust/about-std.toml`. `-Z build-std` compiles the standard
   library into the wasm, so its crates (hashbrown, dlmalloc and a few more)
   ship like any other.

Both use `rust/about.hbs`, which writes the format of Flutter's NOTICES, so the
app reads the result with `parseNotices` and no format of its own.

The standard library's own code has no licence file in `rust-src`, and
cargo-about would print the SPDX template for it, placeholders and all. The
template leaves those crates out, and the recipe fetches `COPYRIGHT`,
`LICENSE-MIT` and `LICENSE-APACHE` from rust-lang/rust instead, at the commit
`rustc -vV` reports for the pinned nightly.

Things that are easy to get wrong:

- **`accepted` is the gate.** A crate under a licence the list does not name
  fails the run. That is what keeps a copyleft crate from arriving in a
  `cargo update` unnoticed. Read the licence before adding it to the list.
- **`accepted` is also a priority list.** `MIT OR Apache-2.0` is taken as MIT
  because MIT is named first.
- **Three crates are published without their licence file.** `about.toml`
  clarifies them, which makes cargo-about read the file from the crate's
  repository at the commit it was published from. That needs the network. A
  crate that needs the same shows up as `<year>` in the output, and a test
  fails on it.
- **Only `wasm32-unknown-unknown` is collected.** A native target brings other
  crates, so add it to `targets` in both files when it arrives.

### Why these files are committed

Nothing else the Rust core generates is committed. These are, for two reasons.
They change only when `Cargo.lock` or the toolchain pin does, not on every edit
to `rust/`. And `flutter test` has to pass on a checkout that never built the
core, which is how the course repository runs the content tests against this
app.

`just check-rust-licenses` regenerates them and fails on a difference. CI runs
it on every pull request and every deploy, so a dependency that changed without
them cannot be merged. After a `cargo update` or a toolchain bump, run
`just gen-rust-licenses` and commit what it changes.

The cargo-about version is `cargo_about_version` in the `justfile`. The recipe
refuses any other, and CI installs that one.

## Python

`tool/fetch_python_licenses.sh <python> <wasi-sdk>` writes
`assets/python/licenses/`. `tool/build_python_wasm.sh` runs it with the versions
it just built, so a Python upgrade replaces the texts. Run it alone to refresh
them without the build.

- `cpython.txt` is CPython's `LICENSE`.
- `cpython-incorporated.txt` is the *Licenses and Acknowledgements for
  Incorporated Software* section of `Doc/license.rst`. CPython's `LICENSE` does
  not name what the interpreter took from elsewhere, the Mersenne Twister,
  expat and libmpdec among them, and this section does. It is kept whole,
  including the parts this build leaves out (OpenSSL, zlib).
- `wasi-libc*.txt` are the six licence files of the C library `python.wasm` is
  linked against. Its `LICENSE` names the other five.
- `compiler-rt.txt` covers the compiler's runtime routines, linked in as well.

wasi-sdk pins wasi-libc and LLVM as submodules. The script reads their commits
from the SDK release, so neither is written down anywhere.

`fetch_python_licenses.sh` empties the directory before it writes, so
`tool/bake_pytest.py` runs after it and adds the texts of what it bakes into the
stdlib zip. They come from each wheel's own `dist-info/licenses/`, at the pinned
versions:

- `pytest.txt`, `pluggy.txt` and `iniconfig.txt` are MIT.
- `packaging.txt` says packaging is under either of the other two,
  `packaging-apache.txt` (Apache-2.0) and `packaging-bsd.txt` (BSD-2-Clause).
- `pygments.txt` is BSD-2-Clause, and `pygments-authors.txt` is the list of
  authors that licence refers to.

## The micro:bit firmware

`assets/microbit/` holds the MicroPython hex a program is written to a board on
top of. It is a release artifact, fetched by checksum. Its licence texts are
committed and were collected by hand from what that release is built from:

| File | Covers | From |
|---|---|---|
| `micropython-microbit-v2.txt` | the port | microbit-foundation/micropython-microbit-v2 at `v2.1.1`, `LICENSE` |
| `micropython.txt` | MicroPython | micropython/micropython at `da4b38e`, `LICENSE` |
| `codal.txt` | codal-core, codal-microbit-v2, codal-nrf52 | lancaster-university/codal-microbit-v2 at `v0.2.43`, `LICENSE` (the three are identical) |
| `codal-microbit-nrf5sdk.txt` | Nordic's nRF5 SDK and SEGGER RTT | microbit-foundation/codal-microbit-nrf5sdk at `ef4662e`, `LICENCE.txt` |

The commits come from the release itself: the `lib/micropython` submodule,
`src/codal_app/codal.json`, and the `target-locked.json` of the CODAL version
that names. **A new firmware version in `just fetch-microbit-firmware` means
walking that chain again.**

One part has no licence to show. The firmware's speech synthesiser, `lib/sam`,
is a reverse-engineered copy of a 1982 program and its upstream states none.

## The Tkinter VM

The image behind the Tkinter page is a saved v86 machine running Alpine Linux:
the emulator, SeaBIOS, a Linux kernel, a hundred Alpine packages and the
project's own agent. Its notices are written with the image rather than kept
here, because they are about one build of it: every package with its version,
its SPDX licence and the aports commit it was built at, then the text of every
licence any of them declares. `docs/vm-build.md`, *Licences*, says how they are
written and what checks them.

The screen lists the whole file as one component, `v86 & Alpine Linux`, under
*Tkinter*. It is shown in every build that ships the image, whether or not the
`tkinter` feature toggle shows the page: the image is distributed with the
build either way.

## Do the licences go together

Checked on 2026-10-11, against MPL 2.0 for the app. This is a developer's
reading and not legal advice.

**Nothing the app itself ships is copyleft.** The VM image is the exception,
below. The Dart packages are BSD-3-Clause, MIT
and Apache-2.0. The engine's own notices name no GPL, LGPL or MPL component.
The crates are MIT, Apache-2.0, Zlib, Unlicense and Unicode-3.0. CPython is
PSF-2.0, wasi-libc is Apache-2.0 with the LLVM exception, MIT and BSD-2-Clause.
pytest, pluggy and iniconfig are MIT, packaging is Apache-2.0 or BSD-2-Clause,
and Pygments is BSD-2-Clause.
MPL 2.0 lets its code be combined with code under other terms (section 3.3, a
"Larger Work"), and every one of these allows it from its side.

Three are not ordinary permissive licences:

- **The fonts are OFL 1.1.** Bundling them is allowed. They stay under the OFL,
  their licence has to travel with them, and they may not be sold by themselves.
- **Nordic's SDK licence**, on part of the firmware. It allows redistribution
  with its notice, which the screen carries. It also says the software is only
  for Nordic chips and may not be reverse engineered. The micro:bit V2 is a
  Nordic chip. The firmware is a file the app hands to a board, not code the
  app is built from, so its terms do not reach the app's own.
- **`unicode-ident` carries Unicode-3.0** for its data tables, beside MIT.

What MPL 2.0 asks of whoever distributes the app:

- **Say where the source is** (section 3.2). The licence screen links to
  `kSourceUrl`. A fork that is deployed has to point that at its own source.
- **A changed file stays under MPL.** The rest of a larger work need not.

Two things would change the answer:

- **GPL-2.0-only for the app** would not go with the Apache-2.0 dependencies.
- **The Tkinter VM image.** Its kernel and much of its userland are GPL or
  LGPL. It is a separate program the page downloads and runs in an emulator,
  not code the app is linked with, so its terms do not reach the app's own. The
  GPL still asks for its notices and its source: `NOTICES.txt` carries the
  first and the licence screen shows it, and the source archive has to go on
  the same release as the image (`docs/vm-build.md`, *Licences*). No image is
  published yet.

Only the crates are held to this by a tool. The Dart side was checked by
reading, and a new pub package under a licence that is not on the list above
would not fail anything.

## Adding something the app ships

1. A pub package or a crate needs nothing. The next build, or the next
   `just gen-rust-licenses`, picks it up.
2. Anything else needs its licence text as a file beside it, exactly as
   upstream publishes it. Declare the file or its directory in `pubspec.yaml`.
3. Add it to `kBundledLicenses` with the origin it belongs to. A new kind of
   thing is a new case of `LicenseOrigin` and a label in
   `lib/views/licenses_screen/license_labels.dart`.
4. Check the licence against the section above.
