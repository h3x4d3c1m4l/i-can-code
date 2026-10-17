// Packs the bundle in web/vm/image/ into the release asset a deploy fetches:
// vm/build/vm-image-<imageId>.tar.zst, its .sha256, and vm/build/vm-image-<imageId>.lock, the pin
// to commit as vm/image.lock once the asset is uploaded. It uploads nothing and writes no pin into
// the tree. See docs/vm-build.md, "Publishing the image".
//
// Usage: node package-image.mjs [--url URL] [--allow-stale] [--image-dir DIR] [--out-dir DIR]
//
// --url is where the asset will be downloaded from; without it the pin names the GitHub release
// `vm-image-<imageId>` of the origin remote. --allow-stale packs an image whose sourceHash is not
// the tree's.

import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { parseArgs } from 'node:util';
import zlib from 'node:zlib';

import {
  archiveName,
  checkDisk,
  entriesUnder,
  pinFor,
  PIN_FILE,
  requireZstd,
  sha256,
  verifyBundle,
  writeTar,
} from './lib/image-archive.mjs';
import { buildDir, imageDir, repoDir } from './lib/dirs.mjs';
import { missingCopyleftTexts } from './lib/licences.mjs';
import { sourceHash } from './lib/source-hash.mjs';

const { values: opts } = parseArgs({
  options: {
    url: { type: 'string' },
    'allow-stale': { type: 'boolean', default: false },
    'image-dir': { type: 'string', default: imageDir },
    'out-dir': { type: 'string', default: buildDir },
  },
});

try {
  requireZstd();
  const imageDir = opts['image-dir'];
  if (!fs.existsSync(path.join(imageDir, 'manifest.json'))) {
    throw new Error(`${imageDir} holds no bundle; run \`just build-vm-image\` first.`);
  }
  const manifest = await verifyBundle(imageDir);
  const id = manifest.imageId;
  if (manifest.debugShell) throw new Error(`${id} was saved with a root shell (--debug-shell), which never ships.`);
  if (!manifest.notices) throw new Error(`${id} has no NOTICES.txt, the licences of what it holds; rebuild it with \`just build-vm-image\`.`);
  // The GPL and the LGPL ask for their text to travel with the binary. A release that leaves one
  // out cannot be put right afterwards: it is already in somebody's browser.
  const notices = fs.readFileSync(path.join(imageDir, id, manifest.notices.file), 'utf8');
  const uncovered = missingCopyleftTexts(notices);
  if (uncovered.length) {
    throw new Error(`${id}/${manifest.notices.file} names ${uncovered.join(', ')} and carries no text for ` +
      `${uncovered.length === 1 ? 'it' : 'them'}. Add the text to vm/licences/ and run \`node vm/tools/write-notices.mjs\`.`);
  }

  const tree = sourceHash(repoDir).hash;
  if (manifest.sourceHash !== tree) {
    const message = `${id} was built from ${manifest.sourceHash}, and the tree is ${tree} now: it is not what these sources build.`;
    if (!opts['allow-stale']) throw new Error(`${message} Rebuild with \`just build-vm-image\`, or pass --allow-stale.`);
    console.warn(`package-image: ${message}`);
  }

  const started = performance.now();
  const entries = [{ name: 'manifest.json', data: fs.readFileSync(path.join(imageDir, 'manifest.json')) }, ...entriesUnder(imageDir, id)];
  fs.mkdirSync(opts['out-dir'], { recursive: true });
  checkDisk(opts['out-dir'], 'before packing the image', entries.reduce((sum, entry) => sum + (entry.data?.byteLength ?? 0), 0));
  const others = fs.readdirSync(imageDir).filter(name => name !== 'manifest.json' && name !== id);
  if (others.length) console.warn(`package-image: left out ${others.join(', ')}: not part of image ${id}.`);
  const mtime = Math.floor(Date.parse(manifest.builtAt) / 1000) || 0;
  // Nearly every byte is a zstd frame already, so a higher level buys nothing but time.
  const archive = zlib.zstdCompressSync(writeTar(entries, mtime), { params: { [zlib.constants.ZSTD_c_compressionLevel]: 3 } });

  const name = archiveName(id);
  const file = path.join(opts['out-dir'], name);
  const hash = sha256(archive);
  fs.writeFileSync(file, archive);
  fs.writeFileSync(`${file}.sha256`, `${hash}  ${name}\n`);

  const url = opts.url ?? releaseUrl(id, name);
  const pin = pinFor(manifest, { url: url ?? 'https://REPLACE-WITH-THE-ASSET-URL', sha256: hash, bytes: archive.byteLength });
  const pinFile = path.join(opts['out-dir'], `vm-image-${id}.lock`);
  fs.writeFileSync(pinFile, `${JSON.stringify(pin, null, 2)}\n`);

  const rel = p => path.relative(process.cwd(), p) || '.';
  console.log(`package-image: ${rel(file)}: ${entries.length} entries, ${(archive.byteLength / 1048576).toFixed(1)} MiB, sha256 ${hash}, in ${Math.round(performance.now() - started)} ms`);
  console.log(`package-image: ${rel(pinFile)} is the pin for it. To publish:`);
  console.log(`  1. Upload ${rel(file)} as the asset \`${name}\`${url ? ` so that it downloads from\n     ${url}` : ', and put its download URL in the pin\'s `url`'}.`);
  console.log(`  2. cp ${rel(pinFile)} ${PIN_FILE}, and check it with \`just fetch-vm-image --force\`.`);
  console.log(`  3. Commit ${PIN_FILE}. The next deploy fetches the image and shows the Tkinter page.`);
} catch (error) {
  console.error(`package-image: ${error.message}`);
  process.exit(1);
}

/** The asset's URL on the GitHub release `vm-image-<imageId>` of the origin remote, if it is on GitHub. */
function releaseUrl(id, name) {
  let remote;
  try {
    remote = execFileSync('git', ['remote', 'get-url', 'origin'], { cwd: repoDir, encoding: 'utf8' }).trim();
  } catch {
    return null;
  }
  const match = /github\.com[:/]([^/]+)\/(.+?)(?:\.git)?$/.exec(remote);
  return match ? `https://github.com/${match[1]}/${match[2]}/releases/download/vm-image-${id}/${name}` : null;
}
