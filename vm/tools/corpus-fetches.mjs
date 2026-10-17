// Prints the corpus cases that fetch more files from the rootfs than they did on an earlier image.
// See lib/corpus-fetches.mjs.
//
// Usage: node corpus-fetches.mjs BEFORE AFTER
//
// BEFORE and AFTER are corpus.json reports. A missing BEFORE prints that there is nothing to
// compare with. Exits 0 either way: a new fetch is for a person to weigh, not a failure.

import fs from 'node:fs';

import { fetchIncreases } from './lib/corpus-fetches.mjs';

const [beforeFile, afterFile] = process.argv.slice(2);
if (!beforeFile || !afterFile) {
  console.error('Usage: node corpus-fetches.mjs BEFORE AFTER');
  process.exit(2);
}
if (!fs.existsSync(beforeFile)) {
  console.log(`Fetches: no earlier corpus report (${beforeFile}) to compare with.`);
  process.exit(0);
}

const read = file => JSON.parse(fs.readFileSync(file, 'utf8'));
const rises = fetchIncreases(read(beforeFile), read(afterFile));
if (rises.length === 0) {
  console.log('Fetches: no corpus case fetches more than it did on the earlier image.');
} else {
  console.log(`Fetches: ${rises.length} corpus case(s) fetch more than on the earlier image. A module the prelude does not warm is a fetch in every page:`);
  for (const { name, before, after, added } of rises) {
    const from = before === null ? 'new case, ' : `${before} -> `;
    console.log(`  ${name}: ${from}${after}${added.length ? `, new: ${added.join(' ')}` : ''}`);
  }
}
