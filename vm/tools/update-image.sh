#!/usr/bin/env bash
# Moves the guest image to the newest stable Alpine release, rebuilds it from the packages Alpine
# publishes today, checks it the way a release is checked, and says which packages moved.
# See vm/README.md.
#
# Usage: vm/tools/update-image.sh [--alpine X.Y] [--keep-pin] [--skip-corpus] [--tag TAG]
#
# --alpine takes that release instead of asking Alpine for its newest. --keep-pin builds without
# writing the release into vm/image/Dockerfile: a trial, which with ICC_VM_BUILD_DIR set leaves
# vm/build/, web/vm/image/ and vm/image/packages.lock as they were. --skip-corpus leaves out the
# five minutes of student programs. --tag names the Docker image, as build-image.sh's --tag does.
#
# Exits 1 when a check failed. The package diff is printed as soon as the image is built, and
# kept in <build>/packages.diff. The corpus cases that fetch more than on vm/build/'s image are
# printed at the end, and kept in <build>/corpus-fetches.txt; they fail nothing.
#
# A run that fails puts the two committed files it rewrites, vm/image/Dockerfile and
# vm/image/packages.lock, back as it found them, and says what it could not put back.
set -euo pipefail

repo=$(cd "$(dirname "$0")/../.." && pwd)
tools="$repo/vm/tools"
dockerfile="$repo/vm/image/Dockerfile"
alpine=""
keep_pin=0
corpus=1
tag=icc-vm-image

while [ $# -gt 0 ]; do
  case "$1" in
    --alpine) alpine=${2:?--alpine needs a release such as 3.24}; shift 2 ;;
    --keep-pin) keep_pin=1; shift ;;
    --skip-corpus) corpus=0; shift ;;
    --tag) tag=${2:?--tag needs a name}; shift 2 ;;
    *) echo "Usage: $0 [--alpine X.Y] [--keep-pin] [--skip-corpus] [--tag TAG]" >&2; exit 2 ;;
  esac
done

build="${ICC_VM_BUILD_DIR:-$repo/vm/build}"
mkdir -p "$build"
build=$(cd "$build" && pwd)
export ICC_VM_BUILD_DIR="$build"
# As lib/dirs.mjs places the bundle.
if [ "$build" = "$repo/vm/build" ]; then image_dir="$repo/web/vm/image"; else image_dir="$build/image"; fi

# The release index Alpine's own download page reads. Its first entry is the mini root
# filesystem, whose branch names the release the alpine:X.Y Docker tag follows.
index=https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/x86/latest-releases.yaml
if [ -z "$alpine" ]; then
  releases=$(curl -fsSL --retry 3 "$index")
  alpine=$(awk '/^ *branch: v[0-9]+\.[0-9]+$/ { sub(/^ *branch: v/, ""); print; exit }' <<< "$releases")
  latest=$(awk '/^ *version: [0-9]/ { sub(/^ *version: /, ""); print; exit }' <<< "$releases")
  if [ -z "$alpine" ]; then
    echo "ERROR: no branch in $index." >&2
    exit 1
  fi
  echo "Newest stable Alpine for x86: $latest (branch v$alpine)."
fi
if ! [[ "$alpine" =~ ^[0-9]+\.[0-9]+$ ]]; then
  echo "ERROR: $alpine is not a release such as 3.24." >&2
  exit 1
fi

pinned=$(sed -n 's/^ARG ALPINE_VERSION=//p' "$dockerfile")
echo "Pinned: Alpine $pinned. Building: Alpine $alpine."

# The lock to compare against: the committed one, as it was before this build rewrote it.
committed_lock="$repo/vm/image/packages.lock"
previous="$build/packages.previous.lock"
if [ -f "$committed_lock" ]; then
  cp "$committed_lock" "$previous"
else
  rm -f "$previous"
fi
# And the Dockerfile as it was, for the same reason: both are committed files, and a run that
# fails must not leave the tree saying the app ships an image nothing has checked.
before_dockerfile="$build/Dockerfile.previous"
cp "$dockerfile" "$before_dockerfile"

image_dir_changed=0
succeeded=0

# Puts the two committed files back, and says what was left as the failed run made it.
# web/vm/image/ cannot be put back: build-state.mjs removes the bundle it replaces.
on_exit() {
  local status=$1
  [ "$succeeded" = 1 ] && return
  local restored=()
  if ! cmp -s "$before_dockerfile" "$dockerfile"; then
    # In place, so the file keeps its mode, which sourceHash counts.
    cat "$before_dockerfile" > "$dockerfile"
    restored+=("vm/image/Dockerfile (Alpine $pinned again)")
  fi
  if [ -f "$previous" ]; then
    if ! cmp -s "$previous" "$committed_lock"; then
      cat "$previous" > "$committed_lock"
      restored+=("vm/image/packages.lock")
    fi
  elif [ -f "$committed_lock" ]; then
    rm -f "$committed_lock"
    restored+=("vm/image/packages.lock (removed: there was none)")
  fi
  echo >&2
  if [ ${#restored[@]} -gt 0 ]; then
    echo "Put back:" >&2
    for file in "${restored[@]}"; do echo "  $file" >&2; done
  else
    echo "Nothing committed was changed." >&2
  fi
  if [ "$image_dir_changed" = 1 ]; then
    echo "NOT put back: $image_dir now holds the bundle this run built, which did not pass. The one" >&2
    echo "the app had is gone. Build the pinned image again with \`just build-vm-image\`, or take a" >&2
    echo "released one with \`just fetch-vm-image\`." >&2
  else
    echo "$image_dir was not touched." >&2
  fi
  echo "vm/build/ holds this run's output and logs; nothing there is committed." >&2
  exit "$status"
}
trap 'on_exit $?' EXIT

# The corpus of the image the app has now, which an update in place is about to overwrite.
previous_corpus="$build/corpus.previous.json"
if [ -f "$repo/vm/build/corpus.json" ]; then
  cp "$repo/vm/build/corpus.json" "$previous_corpus"
else
  rm -f "$previous_corpus"
fi

build_args=(--fresh --tag "$tag")
if [ "$keep_pin" = 1 ]; then
  build_args+=(--alpine "$alpine")
elif [ "$alpine" != "$pinned" ]; then
  # In place, so the file keeps its mode, which sourceHash counts.
  sed "s/^ARG ALPINE_VERSION=.*/ARG ALPINE_VERSION=$alpine/" "$dockerfile" > "$build/Dockerfile.pinned"
  cat "$build/Dockerfile.pinned" > "$dockerfile"
  rm -f "$build/Dockerfile.pinned"
  echo "vm/image/Dockerfile now pins Alpine $alpine."
fi

# npm ci and not npm install: the lock decides what is installed, and a lock that disagrees with
# package.json fails here instead of being rewritten under a build. CI installs before this and
# leaves node_modules behind, so there is nothing to do then.
if [ ! -d "$tools/node_modules" ]; then
  npm ci --prefix "$tools" --no-audit --no-fund --silent
fi

"$tools/build-image.sh" "${build_args[@]}"

echo
echo "== packages"
node "$tools/image-packages.mjs" diff "$previous" "$build/packages.lock" | tee "$build/packages.diff"

failed=()
run() {
  local name=$1
  shift
  echo
  echo "== $name"
  if ! "$@" 2>&1 | tee "$build/logs/update-$name.log"; then
    failed+=("$name")
  fi
}

# Without a state there is nothing for the rest to check. The debug bundle is for the corpus.
# This is the step that replaces the bundle the app has, and the one thing a failure cannot undo.
image_dir_changed=1
node "$tools/build-state.mjs"
node "$tools/build-state.mjs" --debug-shell
manifest=$(node -e 'const m = require(process.argv[1]); console.log(`${m.imageId}: ${m.interpreter.python}, Tk ${m.interpreter.tk}`)' \
  "$image_dir/manifest.json")

run check-image node "$tools/check-image.mjs"
run check-state node "$tools/check-state.mjs"
if [ "$corpus" = 1 ]; then run corpus node "$tools/corpus.mjs"; fi

echo
echo "Packages: $(tail -1 "$build/packages.diff")"
if [ "$corpus" = 1 ] && [ -f "$build/corpus.json" ]; then
  node "$tools/corpus-fetches.mjs" "$previous_corpus" "$build/corpus.json" | tee "$build/corpus-fetches.txt"
fi
echo "Image $manifest, from Alpine $(sed -n 's/^# Alpine \([^ ]*\) .*/\1/p' "$build/packages.lock")."
if [ ${#failed[@]} -gt 0 ]; then
  echo "FAILED: ${failed[*]}. The logs are in $build/logs/update-*.log." >&2
  exit 1
fi
succeeded=1
echo "Every check passed. To ship it: just package-vm-image, then vm/README.md, \"Package and publish\"."
