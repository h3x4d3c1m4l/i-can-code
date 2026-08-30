#!/usr/bin/env bash
#
# Builds CPython for wasm32-wasi — the Python that the Python Lab widget runs on
# every platform. See docs/python-wasm-build.md for the why and the gotchas.
#
# Usage:  ./tool/build_python_wasm.sh [output-dir]
#
set -euo pipefail

# Pinned deliberately. WASI is a Tier-2 CPython platform, and each CPython release
# is tested against one specific WASI SDK — Tools/wasm warns loudly on any other.
# Bump these together, and only after checking what upstream tests against.
PYTHON_VERSION="${PYTHON_VERSION:-3.14.7}"
WASI_SDK_VERSION="${WASI_SDK_VERSION:-24}"

WORK_DIR="${WORK_DIR:-.python-wasm-build}"
OUT_DIR="${1:-assets/python}"

# ---------------------------------------------------------------- host python
#
# This only runs the build script; CPython cross-compiles by first building a
# *host* interpreter from the same source. But Tools/wasm uses contextlib.chdir,
# which is 3.11+, and macOS still ships 3.9 — so a modern python must be found
# rather than assumed.
find_host_python() {
  for candidate in python3.14 python3.13 python3.12 python3.11 python3; do
    if command -v "$candidate" >/dev/null 2>&1; then
      if "$candidate" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)' 2>/dev/null; then
        echo "$candidate"
        return 0
      fi
    fi
  done
  echo "ERROR: need Python 3.11+ to run CPython's WASI build script." >&2
  echo "       macOS ships 3.9, which lacks contextlib.chdir. Try: brew install python@3.14" >&2
  return 1
}

HOST_PYTHON="$(find_host_python)"
echo "==> host python: $HOST_PYTHON ($($HOST_PYTHON --version))"

# ------------------------------------------------------------------ wasi-sdk
case "$(uname -s)" in
  Darwin) SDK_OS="macos" ;;
  Linux)  SDK_OS="linux" ;;
  *) echo "ERROR: unsupported host OS $(uname -s)" >&2; exit 1 ;;
esac
case "$(uname -m)" in
  arm64|aarch64) SDK_ARCH="arm64" ;;
  x86_64)        SDK_ARCH="x86_64" ;;
  *) echo "ERROR: unsupported host arch $(uname -m)" >&2; exit 1 ;;
esac

SDK_NAME="wasi-sdk-${WASI_SDK_VERSION}.0-${SDK_ARCH}-${SDK_OS}"
mkdir -p "$WORK_DIR"
export WASI_SDK_PATH="$(cd "$WORK_DIR" && pwd)/${SDK_NAME}"

if [ ! -d "$WASI_SDK_PATH" ]; then
  echo "==> downloading ${SDK_NAME}"
  curl -fsSL -o "$WORK_DIR/${SDK_NAME}.tar.gz" \
    "https://github.com/WebAssembly/wasi-sdk/releases/download/wasi-sdk-${WASI_SDK_VERSION}/${SDK_NAME}.tar.gz"
  tar xzf "$WORK_DIR/${SDK_NAME}.tar.gz" -C "$WORK_DIR"
fi
echo "==> wasi-sdk: $WASI_SDK_PATH"

# ------------------------------------------------------------------- cpython
SRC_DIR="$WORK_DIR/Python-${PYTHON_VERSION}"
if [ ! -d "$SRC_DIR" ]; then
  echo "==> downloading CPython ${PYTHON_VERSION}"
  curl -fsSL -o "$WORK_DIR/Python-${PYTHON_VERSION}.tgz" \
    "https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tgz"
  tar xzf "$WORK_DIR/Python-${PYTHON_VERSION}.tgz" -C "$WORK_DIR"
fi

# --------------------------------------------------------------------- build
# Builds a host interpreter first, then cross-compiles for WASI with it.
echo "==> building (two CPython compiles, several minutes)"
( cd "$SRC_DIR" && "$HOST_PYTHON" Tools/wasm/wasi build )

# -------------------------------------------------------------------- collect
HOST_BUILD="$(find "$SRC_DIR/cross-build" -maxdepth 1 -type d -name 'wasm32-wasi*' | head -1)"
if [ -z "$HOST_BUILD" ]; then
  echo "ERROR: no wasm32-wasi* directory under $SRC_DIR/cross-build" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

# Strip first. CPython's WASI build compiles with -g, and the debug info is ~75%
# of the binary: 29 MB before, 7.3 MB after. Nothing at runtime needs it.
echo "==> stripping debug info"
"$WASI_SDK_PATH/bin/llvm-strip" "$HOST_BUILD/python.wasm" -o "$OUT_DIR/python.wasm"

# ------------------------------------------------------- precompiled stdlib
#
# The stdlib ships as *bytecode*, not source. Compiling a .py is dramatically
# more expensive than loading a .pyc when the compiler is itself running inside a
# wasm interpreter, and it is paid on every run because each run is a fresh
# process. Measured under wasmi on the shipped artifacts:
#
#                     normal run   run that raises
#   source stdlib         327 ms          5667 ms
#   bytecode stdlib       225 ms           566 ms
#
# The failing case is so much worse because CPython only imports traceback,
# linecache, tokenize and re when it actually has a traceback to print — about
# seventy extra modules to compile, at the exact moment a pupil is waiting to be
# told what they got wrong.
#
# Compiled with the *native* interpreter this build already produced, not the
# host python that ran this script: bytecode carries a version-specific magic
# number, and cross-build/build/python is by construction the same version as the
# python.wasm it sits beside.
BUILD_PYTHON="$(find "$SRC_DIR/cross-build/build" -maxdepth 1 -name 'python*' -type f -perm -u+x 2>/dev/null | head -1)"
if [ -z "$BUILD_PYTHON" ]; then
  echo "ERROR: no native interpreter under $SRC_DIR/cross-build/build." >&2
  echo "       It is needed to compile the stdlib to bytecode of the matching version." >&2
  exit 1
fi
echo "==> compiling stdlib to bytecode with $("$BUILD_PYTHON" --version)"

# -b writes foo.pyc beside foo.py rather than into __pycache__/, which is the
# layout zipimport looks for. unchecked-hash matters because the virtual
# filesystem both hosts provide reports every mtime as 0 — under the default
# timestamp invalidation CPython would distrust every single file and recompile
# it, giving back all of the time this is meant to save.
"$BUILD_PYTHON" -m compileall -q -b --invalidation-mode unchecked-hash "$SRC_DIR/Lib"
find "$SRC_DIR/Lib" -name '*.py' -delete
find "$SRC_DIR/Lib" -name '__pycache__' -type d -prune -exec rm -rf {} +

# One zip rather than thousands of loose files: Flutter would otherwise need
# every one listed in pubspec.yaml, and CPython reads a zip on sys.path natively
# through zipimport.
#
# -0 (stored, no compression) is load-bearing, not an optimisation. This build has
# no zlib — it is not among the 79 built-in modules — so zipimport cannot inflate
# a deflated entry and fails with "can't decompress data; zlib not available".
# Stored entries need no zlib, and cost almost nothing over the wire because the
# transport gzips them anyway.
STDLIB_ZIP_ABS="$(cd "$OUT_DIR" && pwd)/python${PYTHON_VERSION%.*}.zip"
rm -f "$STDLIB_ZIP_ABS"
echo "==> packing stdlib (bytecode, stored)"
( cd "$SRC_DIR/Lib" && zip -q -r -X -0 "$STDLIB_ZIP_ABS" . \
    -x 'test/*' 'idlelib/*' 'tkinter/*' 'turtledemo/*' 'lib2to3/*' )

if find "$SRC_DIR/Lib" -name '*.py' | grep -q .; then
  echo "WARNING: .py files survived in the stdlib; the zip is larger and slower than it should be." >&2
fi

echo
echo "==> done"
ls -lh "$OUT_DIR/python.wasm" "$STDLIB_ZIP_ABS"
cat <<EOF

Verify:
  wasmtime run --wasm max-wasm-stack=16777216 \\
    --dir ${OUT_DIR}::/py \\
    --env PYTHONPATH=/py/$(basename "$STDLIB_ZIP_ABS") --env PYTHONHOME=/py \\
    ${OUT_DIR}/python.wasm -c "print(1+1)"

Note: max-wasm-stack=16777216 is required — CPython overflows the default stack
during interpreter startup. Both hosts (browser and Rust) must configure it too.
EOF
