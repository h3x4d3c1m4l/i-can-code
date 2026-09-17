# Building the Rust core

The Rust core is the app's non-Dart half: the crate in `rust/`, compiled to
WebAssembly and reached from Dart through
[flutter_rust_bridge](https://cjycode.com/flutter_rust_bridge/).

Everything in it today is about a BBC micro:bit on the other end of a USB cable
— the transport, the ARM debug stack, the flash logic — but the name is about
what it *is* rather than what it currently holds. A second subject moves those
modules under a `microbit::` of their own and changes nothing outside the crate.

This document is how that artifact is produced. Run `just build-rust-core`
to do it; read on for why each step is the way it is.

## Why Rust, and why not Dart

The app is web-only today, but Android and desktop are a real goal.
[`nusb`](https://docs.rs/nusb) has backends for WebUSB, usbfs/Android, WinUSB and
IOKit behind one API, so a second platform is a transport arm rather than a
rewrite. Writing the same 2200 lines of ARM debug protocol twice — once in Dart
for the browser, once in something else for Android — is the alternative.

iOS is permanently out of scope, and not for want of a library: Apple gives App
Store apps no USB host API at all.

## Prerequisites

| | |
|---|---|
| **Rust nightly**, exactly as `rust/rust-toolchain.toml` pins it | Installed automatically by rustup the first time cargo runs inside `rust/`. |
| **wasm-pack** | `cargo install wasm-pack --locked` |
| **wasm-bindgen-cli 0.2.128** | `cargo install wasm-bindgen-cli --version 0.2.128 --locked` |
| **flutter_rust_bridge_codegen 2.13.0** | `cargo install flutter_rust_bridge_codegen --version 2.13.0 --locked` |
| **cargo-expand** | `cargo install cargo-expand --locked`. What the codegen shells out to when it has to expand a macro to see a type. |

CI installs the same set with `cargo binstall`, which fetches prebuilt binaries
instead of compiling them.

Install them **with no `RUSTFLAGS` in the environment**. They are host
binaries, and the wasm flags this build needs are not flags a host build accepts:
a leftover `RUSTFLAGS` fails the install with `'+atomics' is not a recognized
feature for this target`. That is also why `wasm-bindgen-cli` is installed by
hand rather than left to wasm-pack, which installs it on demand and would inherit
whatever environment it was called in.

The codegen version, the `flutter_rust_bridge` entry in `pubspec.yaml` and the
`flutter_rust_bridge` dependency in `rust/Cargo.toml` **must all be the same
version**. flutter_rust_bridge checks this at startup and refuses to run
otherwise. Bump the three together.

## What the build does

```bash
just build-rust-core
```

1. `flutter_rust_bridge_codegen generate` — reads `rust/src/api/`, writes
   `rust/src/frb_generated.rs` and `lib/src/rust/`.
2. Reads flutter_rust_bridge's own default rustflags back out of the pub cache
   and checks them against the copy in the recipe (see below).
3. `flutter_rust_bridge_codegen build-web --release` — runs `wasm-pack` on the
   pinned nightly with `-Z build-std=std,panic_abort`, writing `web/pkg/`.
4. Deletes the `.gitignore` and `package.json` wasm-pack leaves behind.

Output, both committed:

| file | size | gzipped |
|---|---|---|
| `web/pkg/rust_core_bg.wasm` | 94 KB | 38 KB |
| `web/pkg/rust_core.js` | 44 KB | 7.8 KB |

About 30 seconds cold on an M-series Mac.

## Nothing generated is committed

`lib/src/rust/`, `rust/src/frb_generated.rs` and `web/pkg/` are all gitignored.
CI builds them, on every pull request and on every deploy, from the crate source
and the pinned toolchain.

flutter_rust_bridge is
[neutral](https://cjycode.com/flutter_rust_bridge/guides/how-to/gitignore) about
committing its output. The reason not to, here, is that all three change on every
edit to `rust/`, and a committed artifact that must be rebuilt by hand is one
somebody eventually forgets. `RustLib.init()` checks a content hash, so a forgotten
rebuild is a broken app rather than a stale one.

A cold build of the wasm measures **65 seconds** on an M-series Mac, with an empty
`rust/target`. That is what `-Z build-std` costs, since it compiles the standard
library for `wasm32-unknown-unknown` from source. A GitHub runner is slower and
`Swatinem/rust-cache` keeps `rust/target` between runs, so only a cache miss pays
full price.

`assets/python/python.wasm` stays committed, and that is not inconsistent: it is
a fifteen-minute CPython cross-compile against a pinned wasi-sdk, not a minute of
cargo.

`lib/src/rust/README` exists because the codegen crashes when its output
directory is missing.

### The toolchain pin only works if it is passed

`build-web` sets `RUSTUP_TOOLCHAIN` to the rolling `nightly`, which **overrides
`rust/rust-toolchain.toml`**. The pin does nothing unless
`--wasm-pack-rustup-toolchain` is passed as well, which the `just` recipe does,
reading the channel out of the toolchain file so the two cannot drift.

Without it the wasm is built by whatever nightly is current that day, which is
the opposite of what pinning it is for.

### What CI runs

One workflow checks and builds the whole thing. `flutter pub get` first, because
the codegen reads the package name from it, then `just build-rust-core`, then
`cargo +stable fmt --check`, `clippy` and `test`.

The Rust checks come **after** the build, not before: `lib.rs` declares
`mod frb_generated`, so the crate does not compile until the codegen has written
it.

They run on stable rather than the pinned nightly. Only the wasm build needs
nightly, and the crate's own source has to stay stable-clean.

The codegen version comes out of `pubspec.lock`. The codegen, the pub package and
the crate MUST be the same version, and hardcoding it in the workflow would make
that a fourth place to keep in step.

## The four things that are easy to get wrong

**`--wasm-pack-rustflags` replaces the list; it does not add to it.**
flutter_rust_bridge sets nine rustflag segments for threaded wasm — shared
memory, `+atomics`, and seven `--export=__tls_*`-style link arguments. Overriding
the flag drops all nine unless they are repeated verbatim. Dropping one does not
fail the build: it fails at *worker startup*, in a browser, with
`WebAssembly.Memory could not be cloned`.

That is why the recipe reads the nine segments back out of
`flutter_rust_bridge/lib/src/cli/build_web/executor.dart` in the pub cache
(`buildWebDefaultWasmPackRustflagSegments`) and holds them against a copy of its
own. A version bump that changes the list stops the build rather than quietly
changing what gets compiled. flutter_rust_bridge itself only prints a warning
here, which is easy to lose in build output.

**`--cfg=web_sys_unstable_apis` is not optional, and cannot live in
`.cargo/config.toml`.** web-sys keeps its WebUSB bindings behind that cfg, and
without it `nusb` fails to compile with 23 errors, the first being that
`web_sys::UsbRequestType` does not exist (measured against web-sys 0.3.105).
It has to travel through `--wasm-pack-rustflags` because `build-web` sets
`RUSTFLAGS` as an *environment variable*, and cargo ignores `[target.*] rustflags`
from a config file whenever that variable is set.

This cfg is the only reason the override exists at all. If web-sys ever
stabilises its WebUSB bindings, the override goes away and flutter_rust_bridge is
back to owning its own flags.

**The nightly is pinned, and `Cargo.lock` is pinned with it.** `-Z build-std` is
nightly-only and `-C target-feature=+atomics` is unstable on top of it — it warns
today and [rust#162235](https://github.com/rust-lang/rust/issues/162235) says it
will become a hard error. There is no urgency, because that error waits
explicitly on `-Z build-std` stabilising, which is what this build depends on
anyway. A pinned date is what keeps it from arriving unannounced.

The crate's own source is a different matter: it must stay stable-clean, and
`rust-ci.yml` runs `cargo +stable` to hold that. Note the explicit `+stable` —
a bare `cargo` inside `rust/` picks up the pin and installs an entire nightly
toolchain to prove nothing.

**wasm-pack writes an npm package, not a build directory.** It leaves a
`.gitignore` containing `*` and a `package.json` in its output, because it
assumes that output is something to publish. Here the opposite is true: the
directory is committed, and everything in `web/` is served. The recipe deletes
both. Without that, `web/pkg/` silently never gets added to the repo — `git
status` simply does not mention it.

## Adding to the Rust API

Public functions under `rust/src/api/` become Dart functions in `lib/src/rust/`.
Re-run `just build-rust-core` after touching them — codegen alone updates the
Dart bindings but leaves the wasm stale, and the mismatch surfaces as a content
hash error at `RustLib.init()`.

Three rules constrain what may be written there, all three from the environment
rather than from taste:

- **No `#[frb(sync)]` function, ever.** A sync call runs on the Dart main thread.
  `std::sync::Mutex` compiles to `memory.atomic.wait32` under `+atomics`, and
  browsers throw on `Atomics.wait` from the main thread.
- **A device may not be held between calls.** flutter_rust_bridge hands each call
  to an arbitrary worker from a pool, and the `JsValue` inside nusb's `Device` is
  not transferable between workers. Anything that holds a device open therefore
  lives on one long-running session function's own stack, fed by a queue.
- **`requestDevice()` exists only in `Window` scope.** `getDevices()` does exist
  in a worker. So Dart asks for permission on the main thread and Rust picks the
  device up with `list_devices()`.

## Hot restart does not reload the core

A Flutter hot restart starts the Dart side over and leaves the wasm where it is:
the module, its statics and whatever session was running all survive in the
worker. Two things follow, and neither is a bug to fix in the app.

`RustLib.init()` refuses a second call, so the first thing the screen asks for
after a hot restart fails. It now says so, as a failure with the core's own words
under it, instead of leaving the screen waiting.

The session from before the restart also runs on until it notices it has been
replaced, which takes one poll, and it holds the board until then. `session::open`
retries a board that is busy for about half a second for exactly this reason.
Another tab holding it still comes back as busy, because waiting does not fix
that.

**Restart the dev server rather than hot restarting when working on `rust/`.** A
rebuilt `web/pkg/` needs that anyway: `flutter run` copies `web/` once, when it
starts.
