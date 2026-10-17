// Whether the image vm/image.lock pins was built from the sources in this tree: its sourceHash
// against the tree's (vm/tools/lib/source-hash.mjs), and its protocol against the page's. Exits 1
// when either differs, 0 when they match or nothing is pinned.
//
// Usage: node check-image-pin.mjs [--lock FILE]

import fs from 'node:fs';
import path from 'node:path';
import { parseArgs } from 'node:util';

import { AGENT_PROTO, PIN_FILE, readPin } from './lib/image-archive.mjs';
import { sourceHash, SOURCE_PATHS } from './lib/source-hash.mjs';

const repoDir = path.resolve(path.dirname(new URL(import.meta.url).pathname), '../..');
const { values: opts } = parseArgs({ options: { lock: { type: 'string', default: path.join(repoDir, PIN_FILE) } } });

try {
  if (!fs.existsSync(opts.lock)) {
    console.log(`check-image-pin: no ${PIN_FILE}, so builds leave the Tkinter page out.`);
    process.exit(0);
  }
  const pin = readPin(opts.lock);
  const tree = sourceHash(repoDir);
  const problems = [];
  if (pin.agentProto !== AGENT_PROTO) {
    problems.push(`the image speaks protocol ${pin.agentProto} and the page ${AGENT_PROTO}, so every load would fail as incompatible`);
  }
  if (pin.sourceHash !== tree.hash) {
    problems.push(`the image was built from ${pin.sourceHash}, and ${SOURCE_PATHS.join(', ')} hash to ${tree.hash} now`);
  }
  if (problems.length) {
    console.error(`check-image-pin: ${pin.imageId} is stale: ${problems.join('; ')}.`);
    console.error('Rebuild with `just build-vm-image`, then publish it (docs/vm-build.md, "Publishing the image").');
    process.exit(1);
  }
  console.log(`check-image-pin: ${pin.imageId} was built from these sources (${tree.files} files, ${tree.hash}).`);
} catch (error) {
  console.error(`check-image-pin: ${error.message}`);
  process.exit(1);
}
