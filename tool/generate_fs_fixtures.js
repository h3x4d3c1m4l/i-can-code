// Records what @microbit/microbit-fs writes into the filesystem region, as the
// fixtures rust/tests/fs_golden.rs holds the port against.
//
// Run deliberately, not on every build: a golden that is recomputed each time
// adopts an upstream change silently, which is the one thing it exists to catch.
//
//   just fetch-microbit-firmware
//   npm install @microbit/microbit-fs
//   node tool/generate_fs_fixtures.js \
//     assets/microbit/micropython-microbit-v2.1.1.hex rust/tests/fixtures/fs

const fs = require('fs');
const path = require('path');
const { MicropythonFsHex, microbitBoardId } = require('@microbit/microbit-fs');

const BASE = fs.readFileSync(process.argv[2], 'utf8');
const OUT = process.argv[3];
const FS_START = 0x6D000, FS_END = 0x73000;
const CHUNK_DATA_LEN = 126;

function toMap(text) {
  const map = new Map();
  let upper = 0;
  for (const line of text.split(/\r?\n/)) {
    if (!line.startsWith(':')) continue;
    const b = [];
    for (let i = 1; i + 1 < line.length; i += 2) b.push(parseInt(line.substr(i, 2), 16));
    const [len, hi, lo, type] = b;
    const off = (hi << 8) | lo, data = b.slice(4, 4 + len);
    if (type === 0x00) data.forEach((v, i) => map.set(upper | (off + i), v));
    else if (type === 0x04) upper = ((data[0] << 8) | data[1]) << 16;
    else if (type === 0x02) upper = ((data[0] << 8) | data[1]) << 4;
  }
  return map;
}

function region(text) {
  const map = toMap(text);
  const out = Buffer.alloc(FS_END - FS_START, 0xFF);
  for (let a = FS_START; a < FS_END; a++) if (map.has(a)) out[a - FS_START] = map.get(a);
  return out;
}

// Each case is a list of [name, content] written in order.
const cases = {
  // Nothing written: only the persistent-data marker on the last page.
  'empty': [],
  // Header (1 + 1 + 7) plus 35 bytes of data: one chunk, room to spare.
  'one-chunk': [['main.py', 'from microbit import *\ndisplay.scroll("hi")\n']],
  // Exactly fills a chunk's data area, so the end offset lands on zero.
  'exact-chunk': [['main.py', 'x'.repeat(CHUNK_DATA_LEN - 9)]],
  // One byte past a chunk: forces a second chunk holding a single byte.
  'chunk-plus-one': [['main.py', 'x'.repeat(CHUNK_DATA_LEN - 8)]],
  // Long enough to link four chunks, which is where the tail and marker
  // pointers actually have to agree.
  'many-chunks': [['main.py', 'print("line")\n'.repeat(30)]],
  // Two files, so free-chunk allocation has to carry on from where it stopped.
  'two-files': [
    ['main.py', 'import helper\nhelper.go()\n'],
    ['helper.py', 'def go():\n    print("helping")\n'],
  ],
  // A name at the length limit, which shares the chunk header with the data.
  'long-name': [['a'.repeat(100) + '.py', 'pass\n']],
};

fs.mkdirSync(OUT, { recursive: true });
const manifest = {};

for (const [name, files] of Object.entries(cases)) {
  const mpfs = new MicropythonFsHex([{ hex: BASE, boardId: microbitBoardId.V2 }]);
  for (const [filename, content] of files) mpfs.write(filename, content);
  const bytes = region(mpfs.getIntelHex(microbitBoardId.V2));
  fs.writeFileSync(path.join(OUT, `${name}.bin`), bytes);
  manifest[name] = {
    files: files.map(([filename, content]) => ({ filename, content })),
    usedBytes: bytes.filter(b => b !== 0xFF).length,
  };
  console.log(`${name.padEnd(16)} ${bytes.filter(b => b !== 0xFF).length} niet-0xFF bytes`);
}

fs.writeFileSync(path.join(OUT, 'cases.json'), JSON.stringify(manifest, null, 2) + '\n');
console.log('\nregio', `0x${FS_START.toString(16)}..0x${FS_END.toString(16)}`, `= ${FS_END - FS_START} bytes`);
