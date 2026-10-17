// Copies the files sourceHash hashes under vm/image and vm/agent into DIR/vm/image and
// DIR/vm/agent, the two Docker build contexts build-image.sh builds from. Built from the
// directories themselves, `COPY files/ /` also took git-ignored files, such as a __pycache__ the
// Mac's own python3 left beside the prelude, and two trees with one sourceHash could build two
// different images. See docs/vm-build.md, "What the build does".
//
// Usage: node stage-context.mjs DIR

import fs from 'node:fs';
import path from 'node:path';

import { sourceFiles } from './lib/source-hash.mjs';

const repoDir = path.resolve(path.dirname(new URL(import.meta.url).pathname), '../..');
const CONTEXTS = ['vm/image', 'vm/agent'];

const [dir] = process.argv.slice(2);
if (!dir) {
  console.error('Usage: node stage-context.mjs DIR');
  process.exit(2);
}

const out = path.resolve(dir);
fs.rmSync(out, { recursive: true, force: true });
let copied = 0;
for (const file of sourceFiles(repoDir, CONTEXTS)) {
  const from = path.join(repoDir, file);
  // Tracked, but deleted in the working tree, which sourceHash leaves out as well.
  if (!fs.existsSync(from)) continue;
  const to = path.join(out, file);
  fs.mkdirSync(path.dirname(to), { recursive: true });
  // Timestamps too: COPY keeps them, and they reach the rootfs the page serves.
  fs.cpSync(from, to, { preserveTimestamps: true });
  copied++;
}
console.log(`stage-context: ${copied} files of ${CONTEXTS.join(' and ')} in ${path.relative(repoDir, out) || '.'}`);
