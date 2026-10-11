#!/usr/bin/env bash
#
# Fetches the licence texts of everything inside assets/python/python.wasm and
# the stdlib zip beside it: CPython, and the two parts of wasi-sdk that are
# linked into the interpreter. The licence screen shows them; see
# docs/licenses.md.
#
# tool/build_python_wasm.sh runs this with the versions it built. Run it alone
# to refresh the texts without the fifteen-minute build.
#
# Usage:  ./tool/fetch_python_licenses.sh <python-version> <wasi-sdk-version> [output-dir]
#
set -euo pipefail

if [ $# -lt 2 ]; then
  echo "Usage: $0 <python-version> <wasi-sdk-version> [output-dir]" >&2
  exit 1
fi

PYTHON_VERSION="$1"
WASI_SDK_VERSION="$2"
OUT_DIR="${3:-assets/python/licenses}"

RAW="https://raw.githubusercontent.com"

fetch() {
  curl -fsSL --retry 3 -o "$2" "$1" || { echo "ERROR: could not fetch $1" >&2; exit 1; }
}

# wasi-sdk pins wasi-libc and LLVM as submodules, so the commit each one is at
# belongs to the SDK release and is read from it rather than written down here.
submodule_commit() {
  curl -fsSL --retry 3 \
    "https://api.github.com/repos/WebAssembly/wasi-sdk/contents/src/$1?ref=wasi-sdk-${WASI_SDK_VERSION}" \
    | sed -n 's/^ *"sha": *"\([0-9a-f]\{40\}\)".*/\1/p' | head -1
}

mkdir -p "$OUT_DIR"
rm -f "$OUT_DIR"/*.txt

# ------------------------------------------------------------------- cpython
CPYTHON="$RAW/python/cpython/v${PYTHON_VERSION}"
echo "==> CPython ${PYTHON_VERSION}"
fetch "$CPYTHON/LICENSE" "$OUT_DIR/cpython.txt"

# The LICENSE file covers CPython's own code. What it has taken from elsewhere
# (the Mersenne Twister, expat, libmpdec and so on) is listed in the
# documentation instead, under this heading and to the end of the page.
HEADING="Licenses and Acknowledgements for Incorporated Software"
RST="$(mktemp)"
trap 'rm -f "$RST"' EXIT
fetch "$CPYTHON/Doc/license.rst" "$RST"
if ! grep -qx "$HEADING" "$RST"; then
  echo "ERROR: Doc/license.rst of CPython ${PYTHON_VERSION} has no \"$HEADING\" heading." >&2
  echo "       Read the page and update HEADING in $0." >&2
  exit 1
fi
sed -n "/^${HEADING}\$/,\$p" "$RST" > "$OUT_DIR/cpython-incorporated.txt"

# ----------------------------------------------------------------- wasi-libc
WASI_LIBC_COMMIT="$(submodule_commit wasi-libc)"
LLVM_COMMIT="$(submodule_commit llvm-project)"
if [ -z "$WASI_LIBC_COMMIT" ] || [ -z "$LLVM_COMMIT" ]; then
  echo "ERROR: could not read the submodule commits of wasi-sdk ${WASI_SDK_VERSION}." >&2
  exit 1
fi

# The C library python.wasm is linked against. Its LICENSE names the other
# five files, so all six are kept.
WASI_LIBC="$RAW/WebAssembly/wasi-libc/${WASI_LIBC_COMMIT}"
echo "==> wasi-libc ${WASI_LIBC_COMMIT}"
fetch "$WASI_LIBC/LICENSE" "$OUT_DIR/wasi-libc.txt"
fetch "$WASI_LIBC/LICENSE-APACHE-LLVM" "$OUT_DIR/wasi-libc-apache-llvm.txt"
fetch "$WASI_LIBC/LICENSE-APACHE" "$OUT_DIR/wasi-libc-apache.txt"
fetch "$WASI_LIBC/LICENSE-MIT" "$OUT_DIR/wasi-libc-mit.txt"
fetch "$WASI_LIBC/libc-top-half/musl/COPYRIGHT" "$OUT_DIR/wasi-libc-musl.txt"
fetch "$WASI_LIBC/libc-bottom-half/cloudlibc/LICENSE" "$OUT_DIR/wasi-libc-cloudlibc.txt"

# -------------------------------------------------------------- compiler-rt
# libclang_rt.builtins, the compiler's own runtime routines, is linked in too.
echo "==> compiler-rt ${LLVM_COMMIT}"
fetch "$RAW/llvm/llvm-project/${LLVM_COMMIT}/compiler-rt/LICENSE.TXT" "$OUT_DIR/compiler-rt.txt"

echo
echo "==> done"
ls -l "$OUT_DIR"
