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

build:
  fvm flutter build web

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

# Builds the committed web/pkg/. See docs/rust-core-build.md.
build-rust-core: gen-rust
  #!/usr/bin/env bash
  set -euo pipefail

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

  # wasm-pack assumes its output is published, not committed. The .gitignore it
  # leaves holds `*`, and everything under web/ is copied into the deployed site.
  rm -f web/pkg/.gitignore web/pkg/package.json

# Runs the Rust core's tests on stable, not the nightly the wasm build pins.
test-rust:
  cd rust && cargo +stable test
