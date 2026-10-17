#!/usr/bin/env bash
# Downloads the BIOS images v86 needs to boot the guest into vm/build/bios/.
#
# Only a boot needs them, and only the build boots: a browser restores a saved state and is
# never given a BIOS. The npm package does not ship them, so they come from the v86 commit the
# pinned npm version was built from, and the checksums make that the same file every time.
set -euo pipefail

commit="589487c7758a2775f606ec631bd78609497f6e05"
out="${ICC_VM_BUILD_DIR:-$(cd "$(dirname "$0")/../.." && pwd)/vm/build}/bios"
mkdir -p "$out"

fetch() {
  local name=$1 sha256=$2 file="$out/$1"
  if [ -f "$file" ] && shasum -a 256 -c <<< "$sha256  $file" >/dev/null 2>&1; then
    return
  fi
  curl -fsSL -o "$file" "https://raw.githubusercontent.com/copy/v86/${commit}/bios/${name}"
  if ! shasum -a 256 -c <<< "$sha256  $file" >/dev/null 2>&1; then
    echo "ERROR: $file does not match its pinned checksum." >&2
    echo "  expected $sha256" >&2
    echo "  got      $(shasum -a 256 "$file" | cut -d' ' -f1)" >&2
    rm -f "$file"
    exit 1
  fi
}

fetch seabios.bin 73e3f359102e3a9982c35fce98eb7cd08f18303ac7f1ba6ebfbe6cdc1c244d98
fetch vgabios.bin a4bc0d80cc3ca028c73dafa8fee396b8d054ce87ebd8abfbd31b06b437607880
# The saved machine's memory holds both, so the bundle's NOTICES.txt names where they came from.
echo "https://github.com/copy/v86/tree/${commit}/bios" > "$out/SOURCE"
echo "BIOS images in $out verified."
