#!/usr/bin/env python3
"""Bakes pytest into the stdlib zip, for lessons with `run: pytest`.

tool/build_python_wasm.sh runs this after packing the stdlib. Run it alone to
bake into the committed zip without the fifteen-minute CPython build:

    python3.15 tool/bake_pytest.py [output-dir]

The host interpreter MUST be the same minor version as the zip's: the packages
go in as bytecode, and a .pyc of another version does not import. Running it
twice gives the same zip. See docs/python-wasm-build.md.
"""

import hashlib
import importlib.util
import os
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import zipfile
from pathlib import Path

# Pinned with their hashes, so a build never bakes in something nobody chose.
# tests need the same versions on the host python (test/support/host_python.dart).
PACKAGES = [
    ("pytest", "9.1.1", "37a86b45efb9a47a61a36449063e8e18d0cab3161329fc099eb21783169c4f0c"),
    ("pluggy", "1.7.0", "7dd7b0d8832ba3cb632c306926ded123429211b83641b35dc5c41ad2d34f9bec"),
    ("iniconfig", "2.3.1", "9121e2c1fdb355232495be3194c8dfe87ccc2d5dee45947b78e68f499790d7a7"),
    ("packaging", "26.3", "d7193f7c8e4e93f444fde0262bf90af30e16fa0ad0ad44cb553c87339b23cd1c"),
    ("pygments", "2.21.0", "2363c69b61c4a97c838da3b130dcd6468f4848992b21a82f2a63ec34377137d9"),
]

# Licence files in each wheel's dist-info/licenses/, and the name each gets in
# assets/python/licenses/. lib/services/licenses/bundled_licenses.dart lists them.
LICENSES = {
    "pytest": {"LICENSE": "pytest.txt"},
    "pluggy": {"LICENSE": "pluggy.txt"},
    "iniconfig": {"LICENSE": "iniconfig.txt"},
    "packaging": {
        "LICENSE": "packaging.txt",
        "LICENSE.APACHE": "packaging-apache.txt",
        "LICENSE.BSD": "packaging-bsd.txt",
    },
    "pygments": {"LICENSE": "pygments.txt", "AUTHORS": "pygments-authors.txt"},
}

# Removed from the zip on every bake. ensurepip is a 1.8 MB pip wheel, and pip
# cannot install anything in the sandbox.
DROPPED_PREFIXES = ("ensurepip/",)

# pytest imports these pygments modules at startup but never uses most of the
# package. Tracing what it loads keeps 21 of 343 modules; see trace_pygments.
TRACE = r"""
import io, sys
sys.path[:0] = [sys.argv[1]]
import pytest
from _pytest._io.terminalwriter import TerminalWriter
writer = TerminalWriter(io.StringIO())
writer.hasmarkup = True
writer._highlight("x = 1\n", lexer="python")
writer._highlight("-a\n+b\n", lexer="diff")
for name, module in sorted(sys.modules.items()):
    if name.split(".")[0] == "pygments" and getattr(module, "__file__", None):
        print(module.__file__)
"""

FIXED_DATE = (1980, 1, 1, 0, 0, 0)


def fail(message):
    sys.exit(f"ERROR: {message}")


def download(work, name, version, sha256):
    filename = f"{name}-{version}-py3-none-any.whl"
    wheel = work / filename
    if not wheel.exists():
        url = f"https://files.pythonhosted.org/packages/py3/{name[0]}/{name}/{filename}"
        print(f"==> downloading {filename}")
        with urllib.request.urlopen(url) as response:
            wheel.write_bytes(response.read())
    digest = hashlib.sha256(wheel.read_bytes()).hexdigest()
    if digest != sha256:
        wheel.unlink()
        fail(f"{filename} has sha256 {digest}, expected {sha256}")
    return wheel


def check_magic(stdlib_zip):
    with zipfile.ZipFile(stdlib_zip) as z:
        header = z.read("os.pyc")[:4]
    if header != importlib.util.MAGIC_NUMBER:
        fail(f"{sys.executable} writes bytecode that {stdlib_zip.name} cannot load; "
             "run this with the CPython release the zip was built from.")


def trace_pygments(stage):
    env = {k: v for k, v in os.environ.items() if k not in ("NO_COLOR", "PYTEST_THEME", "PYTEST_THEME_MODE")}
    out = subprocess.run([sys.executable, "-I", "-S", "-c", TRACE, str(stage)],
                         env=env, check=True, capture_output=True, text=True).stdout
    used = {Path(line).resolve().relative_to(stage.resolve()) for line in out.split()}
    if Path("pygments/lexers/python.py") not in used:
        fail("the pygments trace did not load pygments.lexers.python; update TRACE for this pytest.")
    return used


def stage_packages(wheels, stage, licenses_dir):
    for wheel in wheels:
        with zipfile.ZipFile(wheel) as z:
            z.extractall(stage)
    for info in stage.glob("*.dist-info"):
        name = info.name.split("-")[0]
        for source, target in LICENSES[name].items():
            shutil.copyfile(info / "licenses" / source, licenses_dir / target)
        shutil.rmtree(info / "licenses")
        (info / "RECORD").unlink()

    used = trace_pygments(stage)
    for path in sorted((stage / "pygments").rglob("*"), reverse=True):
        rel = path.relative_to(stage)
        if path.is_file() and rel not in used:
            path.unlink()
        elif path.is_dir() and not any(path.iterdir()):
            path.rmdir()
    print(f"==> kept {len(used)} pygments modules")

    # -d makes a frame read /lib/python315.zip/_pytest/..., which is where
    # _pytest.__file__ points at runtime (web/python/stdlib_layout.js). pytest
    # hides its own frames from a failing test's traceback by that prefix; the
    # stdlib's ./x.py would not match.
    zip_name = f"/lib/python{sys.version_info.major}{sys.version_info.minor}.zip"
    subprocess.run([sys.executable, "-m", "compileall", "-q", "-b", "--invalidation-mode", "unchecked-hash",
                    "-d", zip_name, "."], cwd=stage, check=True)
    for path in stage.rglob("*.py"):
        path.unlink()
    for path in stage.rglob("__pycache__"):
        shutil.rmtree(path)


def top_levels(stage):
    return {path.name + ("/" if path.is_dir() else "") for path in stage.iterdir()}


def rewrite_zip(stdlib_zip, stage):
    baked = top_levels(stage)
    skip = tuple(baked) + DROPPED_PREFIXES
    tmp = stdlib_zip.with_suffix(".zip.tmp")
    with zipfile.ZipFile(stdlib_zip) as old, zipfile.ZipFile(tmp, "w", zipfile.ZIP_STORED) as new:
        for info in old.infolist():
            # A wheel of another version leaves dist-info names this bake does not.
            if info.filename.startswith(skip) or info.filename.split("/")[0].endswith(".dist-info"):
                continue
            new.writestr(info, old.read(info), compress_type=zipfile.ZIP_STORED)
        for path in sorted(stage.rglob("*")):
            rel = path.relative_to(stage).as_posix()
            info = zipfile.ZipInfo(rel + "/" if path.is_dir() else rel, FIXED_DATE)
            info.compress_type = zipfile.ZIP_STORED
            if path.is_dir():
                info.external_attr = (0o40755 << 16) | 0x10
                new.writestr(info, b"")
            else:
                info.external_attr = 0o644 << 16
                new.writestr(info, path.read_bytes())
    os.replace(tmp, stdlib_zip)


def verify(stdlib_zip, out_dir):
    check = f"import sys; sys.path[:0] = [{str(stdlib_zip)!r}]; import pytest, _pytest.terminal; " \
            f"assert pytest.__file__.startswith({str(stdlib_zip)!r}), pytest.__file__; print(pytest.__version__)"
    version = subprocess.run([sys.executable, "-I", "-S", "-c", check],
                             check=True, capture_output=True, text=True).stdout.strip()
    print(f"==> pytest {version} imports from {stdlib_zip.name}")

    node = shutil.which("node")
    if node is None:
        print("WARNING: no node on PATH; skipped the smoke test on python.wasm.", file=sys.stderr)
        return
    smoke = Path(__file__).with_name("smoke_pytest.mjs")
    subprocess.run([node, str(smoke), str(out_dir)], check=True)


def main():
    out_dir = Path(sys.argv[1] if len(sys.argv) > 1 else "assets/python").resolve()
    stdlib_zip = out_dir / f"python{sys.version_info.major}{sys.version_info.minor}.zip"
    if not stdlib_zip.exists():
        fail(f"no {stdlib_zip}. Run this with the Python version the zip was built for.")
    check_magic(stdlib_zip)

    work = Path(os.environ.get("WORK_DIR", ".python-wasm-build")).resolve() / "pytest"
    work.mkdir(parents=True, exist_ok=True)
    wheels = [download(work, name, version, sha) for name, version, sha in PACKAGES]

    licenses_dir = out_dir / "licenses"
    licenses_dir.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        stage = Path(tmp)
        stage_packages(wheels, stage, licenses_dir)
        rewrite_zip(stdlib_zip, stage)

    print(f"==> baked into {stdlib_zip} ({stdlib_zip.stat().st_size / 1e6:.1f} MB)")
    verify(stdlib_zip, out_dir)


if __name__ == "__main__":
    main()
