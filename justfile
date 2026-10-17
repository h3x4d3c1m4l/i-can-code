default: install-flutter get-deps gen-code gen-l10n

set windows-shell := ["pwsh.exe", "-NoProfile", "-c"]

##
# Basic commands
##

install-flutter:
  fvm install -s --skip-pub-get

get-deps:
  fvm flutter pub get

gen-code:
  fvm dart run build_runner clean
  fvm dart run build_runner build

gen-l10n:
  fvm flutter gen-l10n

##
# Watching
##

watch-code:
  fvm dart run build_runner watch

##
# Building
##

# `--no-web-resources-cdn` bundles CanvasKit, which the build otherwise points
# at www.gstatic.com. The second step takes an unused font out of the build and
# gives the page the sizes its progress ring measures against.
# The Tkinter page is left out unless web/vm/image/ holds a bundle: `just build-vm-image` or
# `just fetch-vm-image`. Flags go to `flutter build web`.
# Builds the web app, with the Tkinter page when there is a VM image to ship.
build *flags:
  #!/usr/bin/env bash
  set -euo pipefail
  define=""
  if [ -f web/vm/image/manifest.json ]; then
    define="--dart-define=ICC_VM_IMAGE=true"
  else
    echo "No web/vm/image/manifest.json: building without the Tkinter page."
  fi
  fvm flutter build web --no-web-resources-cdn $define {{flags}}
  fvm dart run tool/finish_web_build.dart build/web

# Serves build/web on http://localhost:8080, with the two cross-origin isolation
# headers `flutter run` is given in .vscode/launch.json. A plain static server
# leaves isolation to the service worker in web/, which a hard reload skips.
serve-build:
  fvm dart run tool/serve_web_build.dart build/web

test:
  fvm flutter test

##
# Other commands
##

lint:
  fvm flutter analyze

show-outdated:
  fvm flutter pub outdated

upgrade-deps:
  fvm flutter pub upgrade

##
# Rust core
##

# Regenerates lib/src/rust/ and rust/src/frb_generated.rs from the Rust API.
gen-rust:
  flutter_rust_bridge_codegen generate

# Builds web/pkg/. See docs/rust-core-build.md.
build-rust-core: gen-rust
  #!/usr/bin/env bash
  set -euo pipefail

  # The wasm-bindgen on the PATH MUST be the version Cargo.lock resolves the
  # crate to. On any other, wasm-pack compiles its own under the wasm RUSTFLAGS
  # below, and the host linker rejects those. See docs/rust-core-build.md.
  bindgen=$(awk '/^name = "wasm-bindgen"$/{f=1;next} f&&/^version/{gsub(/"/,"",$3); print $3; exit}' rust/Cargo.lock)
  installed=$(wasm-bindgen --version 2>/dev/null | awk '{print $2}' || true)
  if [ "$installed" != "$bindgen" ]; then
    echo "ERROR: wasm-bindgen-cli is ${installed:-not installed}, and rust/Cargo.lock needs ${bindgen}." >&2
    echo "       Run \`cargo install wasm-bindgen-cli --version ${bindgen} --locked\`." >&2
    exit 1
  fi

  # --wasm-pack-rustflags replaces flutter_rust_bridge's defaults rather than
  # adding to them, so they are read back out of its own source and held against
  # the copy below. See docs/rust-core-build.md.
  EXPECTED="-C target-feature=+atomics,+bulk-memory,+mutable-globals -C link-args=--shared-memory -C link-args=--max-memory=1073741824 -C link-args=--import-memory -C link-args=--export=__heap_base -C link-args=--export=__wasm_init_tls -C link-args=--export=__tls_size -C link-args=--export=__tls_align -C link-args=--export=__tls_base"

  version=$(awk '/^  flutter_rust_bridge:/{f=1} f&&/^    version:/{gsub(/"/,"",$2); print $2; exit}' pubspec.lock)
  executor="${PUB_CACHE:-$HOME/.pub-cache}/hosted/pub.dev/flutter_rust_bridge-${version}/lib/src/cli/build_web/executor.dart"
  if [ ! -f "$executor" ]; then
    echo "ERROR: cannot read flutter_rust_bridge ${version} from the pub cache." >&2
    echo "       Looked for $executor. Run \`just get-deps\` first." >&2
    exit 1
  fi

  actual=$(awk '/^const buildWebDefaultWasmPackRustflagSegments = \[/{f=1;next} f&&/^\];/{exit} f' "$executor" \
    | sed -e "s/^ *'//" -e "s/',$//" | tr '\n' ' ' | sed 's/ *$//')

  if [ "$actual" != "$EXPECTED" ]; then
    echo "ERROR: flutter_rust_bridge ${version} changed its default wasm-pack rustflags." >&2
    echo "  expected: $EXPECTED" >&2
    echo "  actual:   $actual" >&2
    echo "Read the change, then update EXPECTED in this recipe." >&2
    exit 1
  fi

  # build-web sets RUSTUP_TOOLCHAIN to the rolling `nightly`, which overrides
  # rust-toolchain.toml. Without this the pin does nothing and the wasm is not
  # reproducible.
  toolchain=$(awk -F'"' '/^channel/{print $2}' rust/rust-toolchain.toml)

  flutter_rust_bridge_codegen build-web --release \
    --wasm-pack-rustup-toolchain "$toolchain" \
    --wasm-pack-rustflags "$actual --cfg=web_sys_unstable_apis"

  # wasm-pack leaves an npm package behind. Everything under web/ is copied into
  # the deployed site, so neither file may stay.
  rm -f web/pkg/.gitignore web/pkg/package.json

  # The about screen reads this. Written here rather than baked into the wasm,
  # so showing it does not load the core.
  rustc +"$toolchain" -V > web/pkg/rustc-version.txt

# Downloads the MicroPython firmware the flasher builds on.
#
# Not committed: it is an upstream release artifact, and the checksum is what
# makes a re-download the same file rather than whatever that tag points at now.
fetch-microbit-firmware:
  #!/usr/bin/env bash
  set -euo pipefail

  version="2.1.1"
  sha256="5bd5d4584a5caae740a66d38f93651968569dd4b52f4bc132ebf3c6fdf3847ac"
  file="assets/microbit/micropython-microbit-v${version}.hex"

  if [ -f "$file" ] && shasum -a 256 -c <<< "$sha256  $file" >/dev/null 2>&1; then
    echo "$file is already here and matches."
    exit 0
  fi

  mkdir -p assets/microbit
  curl -fsSL -o "$file" \
    "https://github.com/microbit-foundation/micropython-microbit-v2/releases/download/v${version}/micropython-microbit-v${version}.hex"

  if ! shasum -a 256 -c <<< "$sha256  $file" >/dev/null 2>&1; then
    echo "ERROR: $file does not match its pinned checksum." >&2
    echo "  expected $sha256" >&2
    echo "  got      $(shasum -a 256 "$file" | cut -d' ' -f1)" >&2
    rm -f "$file"
    exit 1
  fi

  echo "$file fetched and verified."

# Runs the Rust core's tests on stable, not the nightly the wasm build pins.
test-rust:
  cd rust && cargo +stable test

##
# Licences
##

# The cargo-about release `gen-rust-licenses` runs on. CI installs this one.
cargo_about_version := "0.9.2"

# Rewrites the Rust core's licence texts under assets/licenses/. They are
# committed, unlike the rest of what the core generates; see docs/licenses.md.
gen-rust-licenses:
  #!/usr/bin/env bash
  set -euo pipefail

  installed=$(cargo about --version 2>/dev/null | awk '{print $2}' || true)
  if [ "$installed" != "{{cargo_about_version}}" ]; then
    echo "ERROR: cargo-about is ${installed:-not installed}, and this recipe needs {{cargo_about_version}}." >&2
    echo "       Run \`cargo install cargo-about --version {{cargo_about_version}} --locked --features cli\`." >&2
    exit 1
  fi

  out="$PWD/assets/licenses"
  cd rust

  # `-Z build-std` compiles the standard library into the wasm, so its crates
  # ship as well. Their manifest is in the pinned toolchain's rust-src.
  std="$(rustc --print sysroot)/lib/rustlib/src/rust/library/std/Cargo.toml"

  # Collected first and written once both runs are through, so a failed run
  # cannot leave half a file to commit.
  crates=$(mktemp)
  trap 'rm -f "$crates"' EXIT
  cargo about generate --locked about.hbs > "$crates"
  cargo about generate --locked --manifest-path "$std" --config about-std.toml about.hbs >> "$crates"
  cat "$crates" > "$out/rust-crates.txt"

  # The standard library's own code has no licence file in rust-src. These are
  # the Rust repository's, at the commit the pinned nightly was built from.
  commit=$(rustc -vV | sed -n 's/^commit-hash: //p')
  for file in COPYRIGHT LICENSE-MIT LICENSE-APACHE; do
    curl -fsSL --retry 3 -o "$out/rust-$file.txt" "https://raw.githubusercontent.com/rust-lang/rust/$commit/$file"
  done

# Fails when the committed Rust licence texts are not what `gen-rust-licenses`
# writes, which is what a changed Cargo.lock or toolchain pin leaves behind.
check-rust-licenses: gen-rust-licenses
  #!/usr/bin/env bash
  set -euo pipefail

  if [ -n "$(git status --porcelain -- 'assets/licenses/rust-*')" ]; then
    echo "ERROR: the Rust licence texts under assets/licenses/ are stale." >&2
    echo "       Run \`just gen-rust-licenses\` and commit what it changes." >&2
    git --no-pager diff --stat -- 'assets/licenses/rust-*' >&2
    exit 1
  fi

##
# VM
##

# The codec against vm/protocol/fixtures/, and the host, the run layer, the bundle loader and the
# screen against a fake v86, agent and DOM. Needs no image; CI runs the same.
# Tests everything in web/vm.
test-vm:
  npm install --prefix vm/tools --no-audit --no-fund --silent
  node --test vm/tools/test/*.test.mjs

# Rewrites vm/protocol/fixtures/ from the generator. See vm/protocol/README.md.
gen-vm-fixtures:
  python3 vm/protocol/gen_fixtures.py

# The same as test-vm.
test-vm-host: test-vm

# Needs Docker, Node 22 or newer, and Python 3.14 or the zstandard module. See docs/vm-build.md.
# Builds the guest image into vm/build/, then the bundle a page loads from it.
build-vm-image: && build-vm-state
  vm/tools/build-image.sh

# Needs what build-vm-image needs, and network. About 17 min on an M1, half of it the build.
# --alpine X.Y takes that release; --keep-pin builds it without writing it into the Dockerfile,
# which with ICC_VM_BUILD_DIR=DIR is a trial that touches nothing else; --skip-corpus. See vm/README.md.
# Moves the image to the newest stable Alpine and today's packages, checks it, and diffs the lock.
update-vm-image *flags:
  vm/tools/update-image.sh {{flags}}

# Boots vm/build/ once, so `just build-vm-image` must have run. About 1 min. With
# --debug-shell it writes a machine with a root shell to vm/build/debug-image/ instead.
# Saves the warm machine and writes the bundle a page loads to web/vm/image/<imageId>/.
build-vm-state *flags:
  npm install --prefix vm/tools --no-audit --no-fund --silent
  node vm/tools/build-state.mjs {{flags}}

# About 1 min.
# Restores the bundle through web/vm/vm_host.js and checks the warm machine in it.
check-vm-state *flags:
  npm install --prefix vm/tools --no-audit --no-fund --silent
  node vm/tools/check-state.mjs {{flags}}

# About 5 min; the debug bundle (`just build-vm-state --debug-shell`) is needed for one case.
# The park cases take 15 min each and run only when named: --only park --only park-detectors.
# Runs the corpus of student programs on the bundle, the way the page runs them.
check-vm-corpus *flags:
  npm install --prefix vm/tools --no-audit --no-fund --silent
  node vm/tools/corpus.mjs {{flags}}

# Flags such as --vga-mib 8 go to vm/tools/check-image.mjs. Takes about 2 min.
# Boots vm/build/ in v86 and checks X, input to Tk, and fetch-free imports.
check-vm-image *flags:
  npm install --prefix vm/tools --no-audit --no-fund --silent
  node vm/tools/check-image.mjs {{flags}}

# Needs Google Chrome, and `just build` run after `just build-vm-image`. About 2 min. With --lesson
# ADDRESS it also runs one lesson step; --root and --base check another build, such as a deploy's.
# Drives the app from build/web/ in headless Chrome: the Tkinter page end to end.
check-vm-app *flags:
  npm install --prefix vm/tools --no-audit --no-fund --silent
  node vm/tools/check-app.mjs {{flags}}

# On stable: the crate's `rust-version` (1.87) makes clippy flag anything newer. The second clippy
# lints for the guest's own target, the only one that compiles the Linux-only modules.
# Lints the guest agent and holds it to the protocol fixtures.
test-vm-agent:
  cd vm/agent && cargo +stable fmt --check
  cd vm/agent && cargo +stable clippy --all-targets --locked -- -D warnings
  rustup +stable target add i686-unknown-linux-musl
  cd vm/agent && cargo +stable clippy --all-targets --locked --target i686-unknown-linux-musl -- -D warnings
  cd vm/agent && cargo +stable test --locked

# Needs Docker. About 3.5 min on Apple silicon, where the i386 build is emulated.
# Builds icc-agent for the guest into vm/build/agent/, and tags it icc-vm-agent.
build-vm-agent:
  #!/usr/bin/env bash
  set -euo pipefail
  alpine=$(sed -n 's/^ARG ALPINE_VERSION=//p' vm/image/Dockerfile)
  docker build --platform linux/386 --build-arg ALPINE_VERSION="$alpine" --tag icc-vm-agent vm/agent
  mkdir -p vm/build/agent
  container=$(docker create --platform linux/386 icc-vm-agent /icc-agent)
  trap 'docker rm "$container" >/dev/null' EXIT
  docker cp "$container:/icc-agent" vm/build/agent/icc-agent
  ls -l vm/build/agent/icc-agent

# Needs Google Chrome and a bundle in web/vm/image/; the app section also needs a build in
# build/web/. About 30 min; --only picks sections, such as --only matrix. Writes
# vm/build/bench/bench.json. See docs/vm-build.md, "Measurements".
# Measures the VM in headless Chrome, throttled to stand in for a school Chromebook.
bench-vm *flags:
  npm install --prefix vm/tools --no-audit --no-fund --silent
  node vm/tools/bench/run-bench.mjs {{flags}}

# Serves the bench page on port 8086 with the app's isolation headers, to open in a browser.
serve-vm-bench:
  npm install --prefix vm/tools --no-audit --no-fund --silent
  node vm/tools/bench/serve.mjs

# Writes vm/build/vm-image-<imageId>.tar.zst, its .sha256, and vm/build/vm-image-<imageId>.lock,
# the pin to commit as vm/image.lock once the asset is uploaded. Uploads nothing. See
# docs/vm-build.md, "Publishing the image".
# Packs the bundle in web/vm/image/ into the release asset a deploy fetches.
package-vm-image *flags:
  node vm/tools/package-image.mjs {{flags}}

# Keeps an image already in place that the pin names and whose every file checks out, and removes
# whatever lies beside it; --force replaces one the pin does not name, such as a local build.
# Downloads the image vm/image.lock pins into web/vm/image/, refusing one that does not match it.
fetch-vm-image *flags:
  node vm/tools/fetch-image.mjs {{flags}}

# Whether the image vm/image.lock pins was built from the sources in this tree.
check-vm-image-pin:
  node vm/tools/check-image-pin.mjs
