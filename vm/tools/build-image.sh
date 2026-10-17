#!/usr/bin/env bash
# Builds the guest image into vm/build/: bzImage for v86 to boot, with kernel.config and
# kernel.txt beside it, the root filesystem as fs.json plus rootfs-flat/, the content-addressed
# zstd files v86 fetches on demand, and packages.lock, every apk package in it. See vm/README.md
# and docs/vm-build.md.
#
# Usage: vm/tools/build-image.sh [--alpine X.Y] [--fresh] [--tag TAG]
#
# --alpine builds another Alpine release than the one vm/image/Dockerfile pins, without writing
# it there. --fresh pulls the base image again and reinstalls every package of the image stage,
# and linux-virt for the kernel's config, rather than taking Docker's cached layers, so the image
# gets what Alpine publishes today.
# --tag names the Docker image (icc-vm-image). ICC_VM_BUILD_DIR builds into another directory.
#
# The lock is also written to vm/image/packages.lock, the committed one, when the build is the
# pinned release into vm/build/. A build anywhere else is a trial and leaves it alone.
set -euo pipefail

repo=$(cd "$(dirname "$0")/../.." && pwd)
tools="$repo/vm/tools"
build="${ICC_VM_BUILD_DIR:-$repo/vm/build}"
image=icc-vm-image
alpine=""
fresh=0

while [ $# -gt 0 ]; do
  case "$1" in
    --alpine) alpine=${2:?--alpine needs a release such as 3.24}; shift 2 ;;
    --fresh) fresh=1; shift ;;
    --tag) image=${2:?--tag needs a name}; shift 2 ;;
    *) echo "Usage: $0 [--alpine X.Y] [--fresh] [--tag TAG]" >&2; exit 2 ;;
  esac
done

pinned=$(sed -n 's/^ARG ALPINE_VERSION=//p' "$repo/vm/image/Dockerfile")
if [ -z "$pinned" ]; then
  echo "ERROR: vm/image/Dockerfile has no ARG ALPINE_VERSION= line." >&2
  exit 1
fi
alpine=${alpine:-$pinned}

mkdir -p "$build/logs"
build=$(cd "$build" && pwd)
export ICC_VM_BUILD_DIR="$build"

# A build needs about 1 GB beside Docker's own layers. Stopping here is cheaper than a disk that
# fills halfway through an export.
min_free_kb=5767168

check_disk() {
  local free
  free=$(df -Pk "$build" | awk 'NR == 2 { print $4 }')
  echo "disk: $((free / 1024)) MiB free $1"
  if [ "$free" -lt "$min_free_kb" ]; then
    echo "ERROR: DISK_LOW: under $((min_free_kb / 1024)) MiB free, stopping." >&2
    exit 1
  fi
}

container=""
context="$build/context"
cleanup() {
  if [ -n "$container" ]; then docker rm -f "$container" >/dev/null || true; fi
  rm -f "$build/export.tar" "$build/rootfs.tar"
  rm -rf "$context" "$build/agent-licences"
}
trap cleanup EXIT

if ! python3 -c 'import compression.zstd' 2>/dev/null && ! python3 -c 'import zstandard' 2>/dev/null; then
  echo "ERROR: copy-to-sha256.py --zstd needs Python 3.14, or the zstandard module." >&2
  exit 1
fi

check_disk "before docker build"
# Exactly the files sourceHash hashes: a git-ignored one under vm/image would reach the image
# without changing it.
node "$tools/stage-context.mjs" "$context"
build_args=(--platform linux/386 --build-context agent-src="$context/vm/agent" --build-arg ALPINE_VERSION="$alpine")
# The image stage and the kernel's config only: the agent's Rust toolchain does not ship, and
# rebuilding it costs three minutes under QEMU. A new base image rebuilds it anyway, and the
# kernel stage rebuilds whenever the config or version it is handed moved.
fresh_args=()
if [ "$fresh" = 1 ]; then fresh_args=(--pull --no-cache-filter image --no-cache-filter kernel-config); fi
echo "Building Alpine $alpine into $build as $image."
docker build "${build_args[@]}" ${fresh_args[@]+"${fresh_args[@]}"} -t "$image" "$context/vm/image"
# From the same cache: the crates icc-agent is linked from, for the bundle's NOTICES.txt.
docker build "${build_args[@]}" --target agent-licences --output "type=local,dest=$build/agent-licences" \
  "$context/vm/image" 2>"$build/logs/agent-licences.log" || { tail -20 "$build/logs/agent-licences.log" >&2; exit 1; }
mv "$build/agent-licences/agent-crates.txt" "$build/agent-crates.txt"
check_disk "after docker build"

container=$(docker create --platform linux/386 "$image" /bin/true)
docker export -o "$build/export.tar" "$container"
docker rm -f "$container" >/dev/null
container=""
check_disk "after docker export"

python3 "$tools/split-export.py" "$build/export.tar" "$build"
rm -f "$build/export.tar"

python3 "$tools/fs2json.py" --zstd --out "$build/fs.json" "$build/rootfs.tar" 2>"$build/logs/fs2json.log"

# copy-to-sha256.py skips blobs that already exist, so a rebuild only compresses what changed.
# Blobs the new fs.json no longer names are removed afterwards.
mkdir -p "$build/rootfs-flat"
if ! python3 "$tools/copy-to-sha256.py" --zstd "$build/rootfs.tar" "$build/rootfs-flat" \
    2>"$build/logs/copy-to-sha256.log"; then
  tail -20 "$build/logs/copy-to-sha256.log" >&2
  exit 1
fi
rm -f "$build/rootfs.tar"
check_disk "after the rootfs store"

python3 - "$build" <<'EOF'
import json
import os
import sys

build = sys.argv[1]
with open(os.path.join(build, "fs.json")) as f:
    fs = json.load(f)

stats = {"files": 0, "directories": 0, "symlinks": 0, "rawBytes": 0}
blobs = set()

def walk(nodes):
    for node in nodes:
        kind = node[3] & 0xF000
        if kind == 0x4000:
            stats["directories"] += 1
            walk(node[6])
        elif kind == 0xA000:
            stats["symlinks"] += 1
        else:
            stats["files"] += 1
            stats["rawBytes"] += node[1]
            blobs.add(node[6])

walk(fs["fsroot"])

flat = os.path.join(build, "rootfs-flat")
removed = 0
for name in os.listdir(flat):
    if name not in blobs:
        os.remove(os.path.join(flat, name))
        removed += 1
missing = [b for b in blobs if not os.path.exists(os.path.join(flat, b))]
if missing:
    sys.exit(f"rootfs-flat is missing {len(missing)} blobs, e.g. {missing[0]}")

stats["blobs"] = len(blobs)
stats["blobBytes"] = sum(os.path.getsize(os.path.join(flat, b)) for b in blobs)
stats["fsJsonBytes"] = os.path.getsize(os.path.join(build, "fs.json"))
with open(os.path.join(build, "rootfs-stats.json"), "w") as f:
    json.dump(stats, f, indent=1)
print(f"rootfs: {stats['files']} files, {stats['rawBytes'] / 2**20:.1f} MiB raw; "
      f"{stats['blobs']} blobs, {stats['blobBytes'] / 2**20:.1f} MiB zstd; "
      f"fs.json {stats['fsJsonBytes'] / 1024:.0f} KiB; {removed} stale blobs removed")
EOF

# The lock comes from the image's own apk database rather than from `apk info`, which leaves out
# the licence and the aports commit.
docker run --rm --platform linux/386 --entrypoint /bin/cat "$image" /lib/apk/db/installed > "$build/apk-installed"
release=$(docker run --rm --platform linux/386 --entrypoint /bin/cat "$image" /etc/alpine-release)
node "$tools/image-packages.mjs" lock "$build/apk-installed" "$release" "$build/packages.lock" "$build/kernel.txt"
rm -f "$build/apk-installed" "$build/packages.txt"
case "$release" in
  "$alpine" | "$alpine".*) ;;
  *) echo "ERROR: asked for Alpine $alpine, and the image says $release." >&2; exit 1 ;;
esac
if [ "$build" = "$repo/vm/build" ] && [ "$alpine" = "$pinned" ]; then
  cp "$build/packages.lock" "$repo/vm/image/packages.lock"
  echo "vm/image/packages.lock updated; \`git diff vm/image/packages.lock\` shows what moved."
fi

"$tools/fetch-bios.sh"
echo "Image built into $build."
