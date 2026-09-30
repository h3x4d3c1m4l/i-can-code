# Building CPython for WebAssembly

A student's Python runs in the browser, on CPython compiled for `wasm32-wasi`.
The app is its own WASI host: `web/python/wasi.js` implements the system calls,
and a Web Worker runs the interpreter on it. The lesson screen and the console
load the same two files, `python.wasm` and the stdlib zip beside it.

This document is how those files are produced. Run `./tool/build_python_wasm.sh`
to do it; read on for why each step is the way it is.

## Why not Pyodide

Pyodide is the obvious candidate, and in a browser it would work. What rules it
out is where the app may go next: iOS and Android are possible future Flutter
platforms for it, and Pyodide cannot run there. It is CPython built with
**Emscripten**, so its `.wasm` imports a *JavaScript* runtime rather than WASI:
a JS-implemented virtual filesystem, `invoke_*` trampolines for setjmp/longjmp,
and `emscripten_asm_const`, which evaluates JavaScript strings embedded in the
binary. Standalone runtimes — wasmtime, wasmer, wasmi — provide WASI, not that.
Hosting Pyodide outside a browser would mean reimplementing Emscripten's runtime
*and* shipping a JS engine.
[The Pyodide maintainers say the same](https://github.com/pyodide/pyodide/discussions/5145):
it "can only run in a browser or Node.js", and WASI support is not planned.

A `wasm32-wasi` build has no such problem: on a platform without a browser, a
standalone runtime can host the same two files. Since CPython 3.13, WASI is also
a **Tier-2 platform** with upstream CI, so this is a supported configuration
rather than a hack.

## Why we build it rather than download one

[VMware's Wasm Language Runtimes](https://github.com/vmware-labs/webassembly-language-runtimes)
publishes prebuilt `python.wasm` files and they work fine — but the project is
dormant: last commit June 2024, last Python release **December 2023 (3.12.0)**.
Building it ourselves gets a current, patchable Python, and it is about fifteen
minutes of compute.

## Prerequisites

| | |
|---|---|
| **wasi-sdk 24** | Downloaded automatically by the script. **Not the latest.** Each CPython release is tested against one specific SDK; 3.14.8 wants 24, and `Tools/wasm` prints `⚠️ Found WASI SDK 33, but WASI SDK 24 is the supported version` for anything else. |
| **Python 3.11+** on the host | Only to *run* the build script — CPython cross-compiles by first building a host interpreter from the same source. But `Tools/wasm` uses `contextlib.chdir`, which is 3.11+, and **macOS still ships 3.9**. `brew install python@3.14`. |
| **pkg-config**, Xcode CLT / build-essential | `brew install pkg-config` |
| **wasmtime** (optional) | For verifying the result locally. `brew install wasmtime` |

## What the build does

```bash
./tool/build_python_wasm.sh            # writes into assets/python/
```

1. Downloads wasi-sdk 24 and the CPython source into `.python-wasm-build/`.
2. Runs `python3.14 Tools/wasm/wasi build`, which compiles CPython **twice** —
   once for the host (needed to cross-compile) and once for `wasm32-wasip1`.
3. Strips the result, compiles a copy of the standard library to bytecode, and
   packs it. The copy is what keeps the source tree whole, so the script can be
   run again over the same `.python-wasm-build/`.

Output, both committed as Flutter assets:

| file | size | gzipped |
|---|---|---|
| `assets/python/python.wasm` | 7.3 MB | 2.2 MB |
| `assets/python/python314.zip` | 13 MB | 5.9 MB |

## The four things that are easy to get wrong

**Strip the binary.** CPython's WASI build compiles with `-g` and the debug info
is roughly three quarters of the output — **29 MB before stripping, 7.3 MB
after**. Nothing at runtime reads it.

**The stdlib zip must be *stored*, not deflated.** This build has no zlib; it is
not among the 79 built-in modules, because zlib would have to be cross-compiled
for WASI separately. So `zipimport` cannot inflate a compressed entry and fails
with `can't decompress data; zlib not available`. `zip -0` sidesteps it entirely,
and costs little in practice because the transport compresses it anyway.

**The stdlib must be shipped as bytecode, not source.** Compiling a `.py` is
expensive when the compiler is itself running as WebAssembly, and it is paid on
*every* run, because every run is a fresh process. Measured under wasmi, a wasm
interpreter, on an earlier build:

| stdlib | normal run | run that raises |
|---|---|---|
| source | 327 ms | 5667 ms |
| bytecode | 225 ms | 566 ms |

The failing case is ten times worse because CPython imports `traceback`,
`linecache`, `tokenize` and `re` only when it actually has a traceback to print
— about seventy extra modules to compile, at the exact moment a student is waiting
to be told what they did wrong.

The script passes two flags:

- `-b` writes `foo.pyc` beside `foo.py` instead of into `__pycache__/`, which is
  the layout `zipimport` looks for.
- `--invalidation-mode unchecked-hash`, so no `.pyc` is ever checked against a
  source. With every `.py` deleted there is nothing to check against, and the
  flag changes nothing. It is what keeps a `.py` left in the zip by mistake from
  costing a compile: under wasmtime, a timestamp `.pyc` beside its `.py` in the
  zip is judged stale on every import.

The bytecode is compiled with `cross-build/<build triple>/python` (`python.exe`
on macOS) — the native interpreter this build already produced — and not with
whatever host Python ran the script. Bytecode carries a version-specific magic
number, and only that one is the same version as the `python.wasm` it ships
beside. It is run from inside the stdlib copy with `.` as its argument, because
every `.pyc` records the path it was compiled from: a stdlib frame in a
traceback then reads `./json/__init__.py`, not a directory on the machine that
built it.

The program a student writes is unaffected: it is written to `/main.py` as source,
so a traceback still quotes the offending line. What is lost is source for
*stdlib* frames, and `inspect.getsource()` on stdlib functions.

**wasmtime needs `max-wasm-stack` raised to 16 MB.** CPython overflows
wasmtime's default stack during interpreter startup. The wrapper CPython
generates (`cross-build/wasm32-wasip1/python.sh`) sets
`--wasm max-wasm-stack=16777216`, and so does the line under *Running it*.
Symptom if missed: a stack-exhaustion trap before any Python code runs. A browser
has no such setting and needs none; the workers instantiate the module as it is.

## Running it

```bash
wasmtime run --wasm max-wasm-stack=16777216 \
  --dir assets/python::/py \
  --env PYTHONPATH=/py/python314.zip --env PYTHONHOME=/py \
  assets/python/python.wasm -c "print(1 + 1)"
```

Note there is **no `--` before the Python arguments**; wasmtime passes everything
after the module straight through, and `--` makes Python read `-c` as a filename.

## What this Python can and cannot do

Verified present: `math`, `json`, `re`, `random`, `datetime`, `itertools`,
`collections`, `_socket`, and the rest of the pure-Python standard library.
Tracebacks are full quality, including the 3.11+ caret markers:

```
  File "<string>", line 1, in <module>
    1/0
    ~^~
ZeroDivisionError: division by zero
```

`input()` reads stdin: a section's `stdin` block on the lesson screen, the
keyboard in the console.

Absent: **zlib** and **_ssl**, so `gzip`, `zipfile`-on-compressed-archives and
anything TLS will not work. Neither matters for teaching, and both could be added
later by cross-compiling the C libraries for WASI and reconfiguring.

The build is also a genuine sandbox, and that is worth preserving: a WASM module
can only reach what its imports allow. A student's code has no network and no way out,
and the filesystem it does have is **entirely inside `web/python/wasi.js`** — a
tree of nodes in memory, seeded with the stdlib zip and the program being run.
There is no host directory behind it and nothing is preopened from disk, so a
program can write, list and delete all it likes without touching anything real.
Nothing it writes outlives the wasm instance.

Two properties that hold that up, and which a change to the shim must keep:

- **The stdlib is sealed.** Both workers pass `readOnlyPaths: ['/python314.zip']`.
  A program that truncates the archive it is importing from breaks every later
  import with an `EOFError` naming nothing the student did.
- **Growth is capped.** `FS_QUOTA_BYTES` bounds what a program may add, measured
  against what was installed, so `while True: f.write("x")` ends in a clean
  `ENOSPC` rather than in a dead tab.

## Upgrading Python

Bump `PYTHON_VERSION` in `tool/build_python_wasm.sh` — and check which wasi-sdk
that release tests against, bumping `WASI_SDK_VERSION` with it. The two are a
matched pair; the release states its own in `Tools/wasm/wasi/__main__.py`. Then
rebuild and run the two checks below.

A new minor version also renames the stdlib zip, `python314.zip` to
`python315.zip`. That name is written in `pubspec.yaml`,
`lib/services/python/python_assets_web.dart` and both workers in `web/python/`.

The script compiles the stdlib to bytecode itself, so an upgrade gets that
treatment automatically — and with the interpreter the build just produced, so
the magic number always matches. Two things to check afterwards, because both
fail quietly rather than loudly:

- `unzip -l assets/python/python*.zip | grep -c '\.py$'` should be **0**. Any
  surviving source means something out-compiled or out-deleted the wrong tree,
  and the only symptom is that runs get slow again. The script warns, but a
  warning in fifteen minutes of build output is easy to miss.
- The wasmtime line under *Running it*, with an import in it:
  `-c "import json, re; print(json.__file__)"`. Bytecode carries a
  version-specific magic number, so an interpreter and a stdlib zip that have
  drifted apart fail on the first import rather than at build time. Nothing in
  `flutter test` covers this — those tests run against the machine's own
  `python3`, not against the two artifacts that ship.
