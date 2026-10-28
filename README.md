# I Can Code

I Can Code is a web app that teaches programming. It is written in Flutter and runs (for now) only in the browser.

Lessons are plain Markdown files under `assets/lessons/`, and a student's code runs in the page: Python on a CPython build for WebAssembly, programs with Tk windows on a Linux machine that v86 emulates, and MicroPython on a BBC micro:bit over WebUSB.

There is no backend and no login.

[CLAUDE.md](CLAUDE.md) describes how the app is put together and the conventions the code follows. This README covers getting it to run.

## Tools to install

You need these to build and run the app at all:

| Tool | What it is for | Install on macOS |
| --- | --- | --- |
| Git LFS | `assets/python/python.wasm` and the stdlib zip beside it are LFS files | `brew install git-lfs`, then `git lfs install` |
| FVM | Pins Flutter to the version in `.fvmrc` | `brew tap leoafarias/fvm && brew install fvm` |
| just | Runs the recipes in the `justfile` | `brew install just` |
| Rust, through rustup | Builds the Rust core | [rustup.rs](https://rustup.rs) |
| The wasm tools | Build the Rust core for the browser | See below |
| Google Chrome | `flutter run` opens the app in it | |

On Linux, get them from your package manager or from each tool's own site.

The wasm tools are four cargo installs:

```bash
cargo install wasm-pack --locked
cargo install wasm-bindgen-cli --version 0.2.129 --locked
cargo install flutter_rust_bridge_codegen --version 2.13.0 --locked
cargo install cargo-expand --locked
```

Run them in a shell where `RUSTFLAGS` is not set. A leftover value from a wasm build makes the install fail with `'+atomics' is not a recognized feature for this target`.

The versions come from the repository. `wasm-bindgen-cli` must match the `wasm-bindgen` entry in `rust/Cargo.lock`, and the codegen must match `flutter_rust_bridge` in `pubspec.yaml`. When `wasm-bindgen-cli` is the wrong version, `just build-rust-core` stops and prints the install command for the right one. [cargo-binstall](https://github.com/cargo-bins/cargo-binstall) installs the same tools as prebuilt binaries in seconds instead of minutes, which is what CI does.

You don't install a Rust nightly by hand. `rust/rust-toolchain.toml` pins one, and rustup fetches it the first time cargo runs inside `rust/`.

These are only needed for part of the work:

| Tool | Needed for |
| --- | --- |
| Node 22.15 or newer | Downloading or building the VM image for the Tkinter page, and `just test-vm` |
| Python 3.14 with pytest | The tests that run the Python harness on your own `python3`, and `tool/try_lesson.dart` |
| Docker | Building the VM image yourself |
| cargo-about 0.9.2 | Rewriting the Rust licence texts after `rust/Cargo.lock` changes |

Install pytest at the versions the app bakes into its own Python:

```bash
pip install pytest==9.1.1 pluggy==1.7.0 iniconfig==2.3.1 packaging==26.3 pygments==2.21.0
```

Without it, the tests that need pytest are skipped. cargo-about installs with `cargo install cargo-about --version 0.9.2 --locked --features cli`.

## First time on a new machine

Run these from the root of the checkout, in this order. Each step needs the one before it.

1. Run `git lfs install`, then clone the repository. To check that LFS fetched the real files, run `head -c 4 assets/python/python.wasm | xxd -p`. It should print `0061736d`. Anything else means you have a pointer file, and `git lfs pull` fetches the real one.
2. `just install-flutter get-deps` installs the Flutter version in `.fvmrc` and fetches the Dart packages.
3. `just build-rust-core` generates the Dart bindings in `lib/src/rust/` and builds the wasm into `web/pkg/`. None of that is committed, and the web build does not compile without it. A cold build takes about a minute.
4. `just gen-code gen-l10n` runs the code generators (MobX, freezed, auto_route and theme_tailor) and generates the localizations.
5. `just fetch-microbit-firmware` downloads the MicroPython firmware and checks it against a pinned checksum. Without it the app still runs, but it cannot write a program to a micro:bit, and the tests that need the firmware are skipped.
6. `just fetch-vm-image` downloads the VM image that `vm/image.lock` pins, about 45 MB, into `web/vm/image/`. You need it only for the Tkinter page and for projects that run on its machine. It needs Node.

Running `just` with no arguments does steps 2 and 4 but skips step 3, so on a fresh clone it leaves you with code that does not compile.

## Running the app

In VS Code, start the "I Can Code (web, debug)" configuration from `.vscode/launch.json`. From a terminal, the same thing is:

```bash
fvm flutter run -d chrome --web-port=8080 \
  --web-header=Cross-Origin-Opener-Policy=same-origin \
  --web-header=Cross-Origin-Embedder-Policy=require-corp \
  --dart-define=ICC_VM_IMAGE=true
```

The two headers make the page cross-origin isolated, which the interactive console needs for `SharedArrayBuffer`. The "no isolation" configuration leaves them out, for when you want to rule them out as the cause of something failing to load.

`ICC_VM_IMAGE=true` offers the Tkinter page. Without an image in `web/vm/image/` that page shows a download failure, and the rest of the app works as usual. The page also sits behind the `tkinter` feature toggle, which is off by default. Press Alt+B (Option+B on a Mac) to open the debug menu and switch it on under "Feature toggles".

To try the build that ships:

```bash
just build        # release build in build/web/
just serve-build  # serves it on http://localhost:8080
```

`just build` includes the Tkinter page only when `web/vm/image/` holds an image.

## Tests and checks

```bash
just lint        # fvm flutter analyze
just test        # fvm flutter test
just test-rust   # the Rust core's tests
just test-vm     # the VM host code, against a fake machine
```

After bumping a package, run `just test` and `just build` as well. A code generator can emit code that the analyzer accepts and the compiler rejects, so a clean lint proves nothing there.

## When to run what

After the first setup, day-to-day work needs only `flutter run`. This table lists what does need a command, and when. It applies to changes you make yourself and to changes you pull in.

| What changed | Run | If you skip it |
| --- | --- | --- |
| `.fvmrc` | `just install-flutter` | FVM has no SDK for the new version |
| `pubspec.yaml` or `pubspec.lock` | `just get-deps` | Packages are missing or out of date |
| Code with `@observable`, `@readonly`, `@action`, `@freezed`, `@RoutePage()` or `@TailorMixin` | `just gen-code`, or keep `just watch-code` running | The generated `*.g.dart`, `*.freezed.dart`, `*.gr.dart` and `*.tailor.dart` files are stale, and the build fails |
| The ARB files in `lib/l10n/` | `just gen-l10n` | `flutter run` regenerates them by itself, but `just lint` and `just test` see the old strings |
| Anything under `rust/`, or the `flutter_rust_bridge` version | `just build-rust-core`, then stop and start `flutter run` | The app fails at `RustLib.init()` with a content hash error. A hot restart keeps the old wasm |
| The `wasm-bindgen` version in `rust/Cargo.lock` | `cargo install wasm-bindgen-cli --version <new version> --locked` | `just build-rust-core` stops and names the version it needs |
| `rust/Cargo.lock` or `rust/rust-toolchain.toml` | `just gen-rust-licenses`, and commit what it changes | CI fails on stale licence texts |
| The firmware version in the `justfile` | `just fetch-microbit-firmware` | The app looks for a firmware file that is not there |
| `vm/image.lock` | `just fetch-vm-image` | You keep running the previous image |
| The VM sources under `vm/` | `just build-vm-image`, see [vm/README.md](vm/README.md) | `web/vm/image/` holds an image built from older sources |

### Lessons and icons need nothing

`assets/course.json` and `assets/icons.bin` are committed placeholders. Every `flutter run`, `flutter build` and `flutter test` swaps them for the real files in its own output: `bin/bundle_lessons.dart` bundles every lesson under `assets/lessons/` into one file, and `bin/bundle_icons.dart` compiles the SVGs under `assets/icons/`. Flutter runs them again when a lesson, a file a lesson includes or an icon changes. You never run them by hand, and you never edit the placeholders.

## Working on lessons

`assets/lessons/` holds a few sample lessons. The course students see lives in a repository of its own. [docs/lesson-format.md](docs/lesson-format.md) describes the format.

To run one step of a lesson without the app, use `tool/try_lesson.dart`. With only a file it lists the steps, and with a step number and code it runs that step and prints the verdict:

```bash
fvm dart run tool/try_lesson.dart <lesson.md>
fvm dart run tool/try_lesson.dart <lesson.md> <n> --code 'print(1)'
```

It runs on your own `python3`, while the app ships CPython 3.15, so check `python3 --version` before you trust a result that depends on the language version.

To check a course checkout against the rules every lesson must keep, point the content tests at it:

```bash
LESSONS_DIR=<path to the course> fvm flutter test test/content/
```

To see another course in the app, copy its subject directory over `assets/lessons/<subject>/`, the way the course repository's deploy does. Don't commit the result.

## Further reading

- [CLAUDE.md](CLAUDE.md): the architecture, the conventions and the reasons behind them
- [docs/rust-core-build.md](docs/rust-core-build.md): the Rust core build and its traps
- [docs/vm-build.md](docs/vm-build.md) and [vm/README.md](vm/README.md): the Tkinter VM, and how to build, check and publish its image
- [docs/python-wasm-build.md](docs/python-wasm-build.md): rebuilding `python.wasm`, a committed file that takes about fifteen minutes to cross-compile
- [docs/microbit-usb.md](docs/microbit-usb.md): the micro:bit and the USB protocol the app speaks to it
- [docs/licenses.md](docs/licenses.md): where each licence text comes from

## Licence

MPL 2.0. See [LICENSE](LICENSE).
