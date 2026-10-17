// The guest image's package lock, from the command line. build-image.sh writes the lock with
// `lock`; update-image.sh reports what a rebuild changed with `diff`. See lib/packages.mjs.
//
// Usage: node image-packages.mjs lock INSTALLED RELEASE OUT [KERNEL]
//        node image-packages.mjs diff OLD NEW
//
// INSTALLED is the image's /lib/apk/db/installed, RELEASE its /etc/alpine-release, and KERNEL the
// kernel.txt of the kernel it boots. `diff` takes a missing OLD as an empty lock, so a first
// build lists every package as added.

import fs from 'node:fs';

import { diffLocks, formatLock, parseInstalled, readKernel, readLock } from './lib/packages.mjs';

const [command, ...args] = process.argv.slice(2);

try {
  if (command === 'lock' && (args.length === 3 || args.length === 4)) {
    const [installed, release, out, kernelFile] = args;
    const { arch, packages } = parseInstalled(fs.readFileSync(installed, 'utf8'));
    const kernel = kernelFile ? readKernel(fs.readFileSync(kernelFile, 'utf8')) : undefined;
    fs.writeFileSync(out, formatLock({ release: release.trim(), arch, packages, kernel }));
    console.log(`image-packages: ${packages.length} packages of Alpine ${release.trim()} ${arch} in ${out}`);
  } else if (command === 'diff' && args.length === 2) {
    const [before, after] = args.map(file => (fs.existsSync(file) ? readLock(fs.readFileSync(file, 'utf8')) : { release: null, packages: [] }));
    console.log(diffLocks(before, after).lines.join('\n'));
  } else {
    console.error('Usage: node image-packages.mjs lock INSTALLED RELEASE OUT [KERNEL] | diff OLD NEW');
    process.exit(2);
  }
} catch (error) {
  console.error(`image-packages: ${error.message}`);
  process.exit(1);
}
