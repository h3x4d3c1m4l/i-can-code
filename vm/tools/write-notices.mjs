// Writes a bundle's NOTICES.txt again, from the build directory the bundle was built in, and
// names it in the manifest. build-state.mjs writes the same file at the end of a build; this is
// the way to correct a licence text or a wording afterwards, because neither is part of the saved
// machine and neither is worth a new imageId.
//
// Usage: node write-notices.mjs [--image-dir DIR] [--check]
//
// --check writes nothing and exits 1 when the bundle's NOTICES.txt is not what this would write.
//
// It reads packages.lock, agent-crates.txt, bios/SOURCE and kernel.txt from the build directory,
// so the build that made the bundle must still be there. See docs/vm-build.md, "Licences".

import fs from 'node:fs';
import path from 'node:path';
import { parseArgs } from 'node:util';

import { buildDir, imageDir, repoDir } from './lib/dirs.mjs';
import { sha256 } from './lib/image-archive.mjs';
import { renderNotices } from './lib/notices.mjs';
import { readCrates, readKernel, readLock } from './lib/packages.mjs';

const { values: opts } = parseArgs({
  options: {
    'image-dir': { type: 'string', default: imageDir },
    check: { type: 'boolean', default: false },
  },
});

try {
  const manifestFile = path.join(opts['image-dir'], 'manifest.json');
  const manifest = JSON.parse(fs.readFileSync(manifestFile, 'utf8'));
  const bundle = path.join(opts['image-dir'], manifest.imageId);

  const inputs = ['packages.lock', 'agent-crates.txt', 'bios/SOURCE', 'kernel.txt'].map(name => path.join(buildDir, name));
  const missing = inputs.filter(file => !fs.existsSync(file));
  if (missing.length) {
    throw new Error(`${missing.map(file => path.relative(repoDir, file)).join(', ')} missing: this needs the build the bundle came from.`);
  }
  const [lock, crates, bios, kernel] = inputs.map(file => fs.readFileSync(file, 'utf8'));
  const v86Build = path.dirname(new URL(import.meta.resolve('v86')).pathname);
  const text = Buffer.from(renderNotices({
    lock: readLock(lock),
    agent: readCrates(crates),
    v86: { version: manifest.v86.version, license: fs.readFileSync(path.join(v86Build, '../LICENSE'), 'utf8') },
    biosSource: bios.trim(),
    sourceHash: manifest.sourceHash,
    kernel: readKernel(kernel),
  }));

  const noticesFile = path.join(bundle, 'NOTICES.txt');
  const held = fs.existsSync(noticesFile) ? fs.readFileSync(noticesFile) : null;
  if (opts.check) {
    if (held?.equals(text)) {
      console.log(`write-notices: ${manifest.imageId}/NOTICES.txt is what these sources write, ${text.byteLength} B.`);
      process.exit(0);
    }
    throw new Error(`${manifest.imageId}/NOTICES.txt is not what these sources write; run \`node vm/tools/write-notices.mjs\`.`);
  }
  fs.writeFileSync(noticesFile, text);
  manifest.notices = { file: 'NOTICES.txt', bytes: text.byteLength, sha256: sha256(text) };
  // The top manifest and the bundle's own are one file, and package-image.mjs holds them to that.
  const json = `${JSON.stringify(manifest, null, 1)}\n`;
  fs.writeFileSync(manifestFile, json);
  fs.writeFileSync(path.join(bundle, 'manifest.json'), json);
  console.log(`write-notices: ${manifest.imageId}/NOTICES.txt, ${text.byteLength} B, sha256 ${manifest.notices.sha256}`);
} catch (error) {
  console.error(`write-notices: ${error.message}`);
  process.exit(1);
}
