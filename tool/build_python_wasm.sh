#!/usr/bin/env bash
#
# Builds CPython for wasm32-wasi: the Python a student's code runs on, in the
# browser. See docs/python-wasm-build.md for the why and the gotchas.
#
# Usage:  ./tool/build_python_wasm.sh [output-dir]
#
set -euo pipefail

# Pinned deliberately. WASI is a Tier-2 CPython platform, and each CPython release
# is tested against one specific WASI SDK — Tools/wasm warns loudly on any other.
# Bump these together, and only after checking what upstream tests against.
PYTHON_VERSION="${PYTHON_VERSION:-3.14.8}"
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
WORK_DIR="$(cd "$WORK_DIR" && pwd)"
export WASI_SDK_PATH="$WORK_DIR/${SDK_NAME}"

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
# seventy extra modules to compile, at the exact moment a student is waiting to be
# told what they got wrong.
#
# Compiled with the *native* interpreter this build already produced, not the
# host python that ran this script: bytecode carries a version-specific magic
# number, and the native interpreter is by construction the same version as the
# python.wasm it sits beside.
#
# Located the way Tools/wasm/wasi locates it: cross-build/<BUILD_GNU_TYPE of the
# python running it>, holding python, or python.exe on macOS.
BUILD_DIR="$SRC_DIR/cross-build/$("$HOST_PYTHON" -c 'import sysconfig; print(sysconfig.get_config_var("BUILD_GNU_TYPE"))')"
BUILD_PYTHON=""
for candidate in "$BUILD_DIR/python" "$BUILD_DIR/python.exe"; do
  if [ -f "$candidate" ]; then
    BUILD_PYTHON="$candidate"
    break
  fi
done
if [ -z "$BUILD_PYTHON" ]; then
  echo "ERROR: no native interpreter in $BUILD_DIR." >&2
  echo "       It is needed to compile the stdlib to bytecode of the matching version." >&2
  exit 1
fi
echo "==> compiling stdlib to bytecode with $("$BUILD_PYTHON" --version)"

# Compiled and pruned in a copy. Doing it in Lib itself deleted the source, so a
# second run over the same WORK_DIR had nothing left to compile.
STAGE_DIR="$WORK_DIR/stdlib-${PYTHON_VERSION}"
rm -rf "$STAGE_DIR"
cp -R "$SRC_DIR/Lib" "$STAGE_DIR"

# Not shipped. Lib/test also holds files that are invalid Python on purpose,
# and compileall exits non-zero on them.
for dir in test idlelib tkinter turtledemo lib2to3; do
  rm -rf "${STAGE_DIR:?}/$dir"
done

# -b writes foo.pyc beside foo.py rather than into __pycache__/, which is the
# layout zipimport looks for. unchecked-hash means no .pyc is checked against a
# source. With every .py deleted there is none, but a .py left in the zip would
# make its timestamp .pyc stale under wasm, and recompiled on every run.
#
# Run from inside the copy, so a .pyc names its source ./json/__init__.py. Given
# a full path, compileall writes the build machine's directories into every
# stdlib line of a student's traceback.
( cd "$STAGE_DIR" && "$BUILD_PYTHON" -m compileall -q -b --invalidation-mode unchecked-hash . )
find "$STAGE_DIR" -name '*.py' -delete
find "$STAGE_DIR" -name '__pycache__' -type d -prune -exec rm -rf {} +

# One zip rather than thousands of loose files: Flutter would otherwise need
# every one listed in pubspec.yaml, and CPython reads a zip on sys.path natively
# through zipimport.
#
# -0 (stored, no compression) is load-bearing, not an optimisation. This build has
# no zlib — it is not among the 79 built-in modules — so zipimport cannot inflate
# a deflated entry and fails with "can't decompress data; zlib not available".
# Stored entries need no zlib, and cost almost nothing over the wire because the
# transport gzips them anyway.
# python314.zip, not python3.14.zip: the name CPython looks for on sys.path, and
# the one pubspec.yaml and both workers expect.
MAJOR_MINOR="${PYTHON_VERSION%.*}"
STDLIB_ZIP_ABS="$(cd "$OUT_DIR" && pwd)/python${MAJOR_MINOR/./}.zip"
rm -f "$STDLIB_ZIP_ABS"
echo "==> packing stdlib (bytecode, stored)"
( cd "$STAGE_DIR" && zip -q -r -X -0 "$STDLIB_ZIP_ABS" . )

# Not grep -q: it exits on the first match, unzip dies of SIGPIPE, and pipefail
# turns the match into a failure.
if unzip -Z1 "$STDLIB_ZIP_ABS" | grep '\.py$' >/dev/null; then
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

Note: max-wasm-stack=16777216 is required: CPython overflows wasmtime's default
stack during interpreter startup. A browser has no such setting and needs none.
EOF
