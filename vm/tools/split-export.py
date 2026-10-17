#!/usr/bin/env python3
"""Splits a `docker export` of the guest image into what v86 is given separately.

Writes bzImage, which v86 loads itself rather than reading it from the root filesystem; beside
it kernel.config and kernel.txt, the config it was built with and where its source came from;
and rootfs.tar, the tree fs2json.py and copy-to-sha256.py turn into the 9p root.
"""

import argparse
import sys
import tarfile
from pathlib import Path

# Where the Dockerfile's kernel stage puts them, and what they are called in the build directory.
KERNEL = {"boot/vmlinuz": "bzImage", "boot/config": "kernel.config", "boot/kernel.txt": "kernel.txt"}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("export", type=Path, help="tar written by docker export")
    parser.add_argument("out", type=Path, help="directory for bzImage, the kernel's notes and rootfs.tar")
    args = parser.parse_args()

    dropped = []
    found = set()
    with tarfile.open(args.export) as src, tarfile.open(args.out / "rootfs.tar", "w") as dst:
        for member in src:
            name = member.name.removeprefix("./")
            if name in KERNEL:
                (args.out / KERNEL[name]).write_bytes(src.extractfile(member).read())
                found.add(name)
                continue
            # /boot is only read by the build: v86 is handed the kernel directly. Docker's own
            # marker file and the device nodes in its /dev do not belong in a root that devtmpfs
            # mounts over anyway, and fs2json.py cannot describe the nodes.
            if name.startswith("boot/") or name == ".dockerenv":
                dropped.append(name)
                continue
            if not (member.isfile() or member.isdir() or member.issym() or member.islnk()):
                dropped.append(name)
                continue
            if member.islnk() and member.linkname.removeprefix("./").startswith("boot/"):
                sys.exit(f"{name} is a hard link into /boot, which is not kept")
            dst.addfile(member, src.extractfile(member) if member.isfile() else None)

    missing = set(KERNEL) - found
    if missing:
        sys.exit(f"not in the export: {', '.join(sorted(missing))}")
    print(f"split-export: dropped {len(dropped)} entries: {' '.join(dropped)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
