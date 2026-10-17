// The released form of an image bundle: web/vm/image/ as a zstd-compressed tar, and the pin
// (vm/image.lock) that names one release of it. package-image.mjs writes both, fetch-image.mjs
// reads them back, check-image-pin.mjs holds the pin to the tree. See docs/vm-build.md,
// "Publishing the image".
//
// The tar is written and read here rather than by the system's tar: macOS's bsdtar and GNU tar
// disagree on zstd and on the extended headers they add, and Node has zstd built in.

import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';

import { mismatch } from '../../../web/vm/vm_bundle.js';
import { VERSION as AGENT_PROTO } from '../../../web/vm/vm_protocol.js';

export { AGENT_PROTO };

/** What build-state.mjs names an image: the first 16 hex digits of its state's sha256. */
const IMAGE_ID = /^[0-9a-f]{16}$/;

/** The one pin a checkout ships with, beside the sources it was built from. */
export const PIN_FILE = 'vm/image.lock';

export const archiveName = imageId => `vm-image-${imageId}.tar.zst`;

/**
 * The free space, in KB, that writing `bytes` needs: three times as much, room for a download,
 * its unpacked copy and a copy across file systems. ICC_VM_MIN_FREE_KB replaces it.
 *
 * Scaled rather than the 5.5 GB build-image.sh and build-state.mjs keep to: these tools write
 * about 150 MB, and they run in CI, where a runner is not measured by a Mac's floor.
 */
export function minFreeKb(bytes, env = process.env) {
  const override = env.ICC_VM_MIN_FREE_KB;
  if (override !== undefined && override !== '') {
    const kb = Number(override);
    if (!Number.isSafeInteger(kb) || kb < 0) throw new Error(`ICC_VM_MIN_FREE_KB=${override} is not a whole number of KB.`);
    return kb;
  }
  return Math.ceil(3 * bytes / 1024);
}

/** Throws DISK_LOW when `dir`'s file system has less free than writing `bytes` needs (minFreeKb). */
export function checkDisk(dir, what, bytes) {
  const floorKb = minFreeKb(bytes);
  const { bavail, bsize } = fs.statfsSync(dir);
  const freeKb = bavail * bsize / 1024;
  if (freeKb < floorKb) {
    throw new Error(`DISK_LOW: ${Math.round(freeKb / 1024)} MiB free under ${dir}, under the ${Math.ceil(floorKb / 1024)} MiB floor, ${what}.`);
  }
}

export function requireZstd() {
  if (typeof zlib.zstdCompressSync !== 'function') {
    throw new Error(`Node ${process.versions.node} has no zstd in node:zlib; the image tools need Node 22.15 or newer.`);
  }
}

export const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');

// Pins

/**
 * Reads and checks a pin. Every field is required: a pin is written by package-image.mjs and
 * edited by hand only for its `url`.
 *
 * @returns {{imageId: string, url: string, sha256: string, bytes: number, sourceHash: string,
 *     agentProto: number, builtAt?: string}}
 */
export function readPin(file) {
  const pin = JSON.parse(fs.readFileSync(file, 'utf8'));
  const problems = [];
  if (!IMAGE_ID.test(pin.imageId ?? '')) problems.push('`imageId` is not 16 hex digits');
  if (!/^(https:|http:|file:)/.test(pin.url ?? '')) problems.push('`url` is not an https:, http: or file: URL');
  if (!/^[0-9a-f]{64}$/.test(pin.sha256 ?? '')) problems.push('`sha256` is not 64 lowercase hex digits');
  if (!Number.isSafeInteger(pin.bytes) || pin.bytes <= 0) problems.push('`bytes` is not a positive integer');
  if (!/^sha256:[0-9a-f]{64}$/.test(pin.sourceHash ?? '')) problems.push('`sourceHash` is not sha256: and 64 hex digits');
  if (!Number.isSafeInteger(pin.agentProto)) problems.push('`agentProto` is not an integer');
  if (problems.length) throw new Error(`${file}: ${problems.join('; ')}.`);
  return pin;
}

export function pinFor(manifest, { url, sha256: hash, bytes }) {
  return {
    imageId: manifest.imageId,
    url,
    sha256: hash,
    bytes,
    sourceHash: manifest.sourceHash,
    agentProto: manifest.agentProto,
    builtAt: manifest.builtAt,
  };
}

// Bundles

/** How copy-to-sha256.py names a rootfs file: the first 10 hex digits of its content's sha256. */
const ROOTFS_FILE = /^([0-9a-f]{10})\.bin\.zst$/;

/**
 * Why the rootfs file `name` does not hold what its name says, or null when it does. v86 fetches
 * each file by that name and uses what arrives, so one damaged in place fails only once a run
 * reads it.
 */
export function rootfsMismatch(name, data) {
  const match = ROOTFS_FILE.exec(name);
  if (!match) return 'is not named for its content';
  let content = data;
  // copy-to-sha256.py writes an empty file as no bytes at all rather than as an empty frame.
  if (data.byteLength > 0) {
    try {
      content = zlib.zstdDecompressSync(data);
    } catch (error) {
      return `does not decompress (${error.message})`;
    }
  }
  const hash = sha256(content).slice(0, 10);
  return hash === match[1] ? null : `holds content whose sha256 begins ${hash}`;
}

/**
 * Checks the bundle in `imageDir` the way a page would read it: the top manifest names
 * `<imageId>/`, whose own manifest is the same file, `<imageId>/` holds nothing the manifest does
 * not name, the state, the wasm and NOTICES.txt (when it has one) match the manifest's sizes and
 * sha256, the rootfs holds as many files and bytes as it says and each file the content its name
 * says, and the page in this tree speaks its protocol. Needs zstd in node:zlib.
 *
 * @returns {Promise<object>} The manifest.
 * @throws {Error} Naming the first thing that does not hold.
 */
export async function verifyBundle(imageDir) {
  const top = fs.readFileSync(path.join(imageDir, 'manifest.json'));
  const manifest = JSON.parse(top.toString('utf8'));
  const id = manifest.imageId;
  if (!IMAGE_ID.test(id ?? '')) throw new Error(`${imageDir}/manifest.json names no image.`);
  const bundle = path.join(imageDir, id);
  if (!top.equals(fs.readFileSync(path.join(bundle, 'manifest.json')))) {
    throw new Error(`${imageDir}/manifest.json is not ${id}/manifest.json.`);
  }
  if (manifest.agentProto !== AGENT_PROTO) {
    throw new Error(`The image speaks protocol ${manifest.agentProto}, web/vm/vm_protocol.js ${AGENT_PROTO}.`);
  }
  const files = [
    [manifest.v86.wasm, { bytes: manifest.v86.wasmBytes, sha256: manifest.v86.wasmSha256 }],
    [manifest.state.file, { bytes: manifest.state.bytes, sha256: manifest.state.sha256 }],
  ];
  // Images built before NOTICES.txt existed have none, and a pin may still name one of them.
  if (manifest.notices) files.push([manifest.notices.file, { bytes: manifest.notices.bytes, sha256: manifest.notices.sha256 }]);
  for (const [name, check] of files) {
    if (typeof check.sha256 !== 'string') throw new Error(`The manifest has no sha256 for ${name}.`);
    const problem = await mismatch(fs.readFileSync(path.join(bundle, name)), check);
    if (problem) throw new Error(`${id}/${name} ${problem}.`);
  }
  if (!fs.statSync(path.join(bundle, manifest.v86.lib)).isFile()) throw new Error(`${id}/${manifest.v86.lib} is missing.`);
  // package-image.mjs packs all of it, and `flutter build web` ships all of it.
  const named = new Set(['manifest.json', manifest.v86.lib, manifest.v86.wasm, manifest.state.file, manifest.rootfs.dir.replace(/\/$/, '')]);
  if (manifest.notices) named.add(manifest.notices.file);
  for (const name of fs.readdirSync(bundle)) {
    if (!named.has(name)) throw new Error(`${id}/${name} is not part of the image.`);
  }
  const rootfs = path.join(bundle, manifest.rootfs.dir);
  let count = 0;
  let bytes = 0;
  for (const entry of fs.readdirSync(rootfs, { withFileTypes: true })) {
    const name = `${id}/${manifest.rootfs.dir}${entry.name}`;
    if (!entry.isFile()) throw new Error(`${name} is not a file.`);
    const data = fs.readFileSync(path.join(rootfs, entry.name));
    count++;
    bytes += data.byteLength;
    const problem = rootfsMismatch(entry.name, data);
    if (problem) throw new Error(`${name} ${problem}.`);
  }
  if (count !== manifest.rootfs.files || bytes !== manifest.rootfs.bytes) {
    throw new Error(`${id}/${manifest.rootfs.dir} holds ${count} files of ${bytes} bytes, not ${manifest.rootfs.files} of ${manifest.rootfs.bytes}.`);
  }
  return manifest;
}

/** Every directory and file under `root` as tar entries, parents first and in name order. */
export function entriesUnder(root, prefix) {
  const entries = [{ name: `${prefix}/`, directory: true }];
  for (const entry of fs.readdirSync(path.join(root, prefix), { withFileTypes: true }).sort((a, b) => (a.name < b.name ? -1 : 1))) {
    const name = `${prefix}/${entry.name}`;
    if (entry.isDirectory()) entries.push(...entriesUnder(root, name));
    else if (entry.isFile()) entries.push({ name, data: fs.readFileSync(path.join(root, name)) });
    else throw new Error(`${name} is neither a file nor a directory.`);
  }
  return entries;
}

// Tar, ustar only: regular files and directories, names up to 100 bytes

const BLOCK = 512;

/**
 * @param {{name: string, directory?: boolean, data?: Uint8Array}[]} entries
 * @param {number} mtime Seconds; one for every entry, so the same bundle packs to the same bytes.
 */
export function writeTar(entries, mtime) {
  const blocks = [];
  for (const entry of entries) {
    const name = Buffer.from(entry.name, 'utf8');
    if (name.length > 100) throw new Error(`${entry.name} is longer than a tar name can be.`);
    const size = entry.directory ? 0 : entry.data.byteLength;
    const header = Buffer.alloc(BLOCK);
    name.copy(header, 0);
    header.write(entry.directory ? '0000755\0' : '0000644\0', 100, 'ascii');
    header.write('0000000\0', 108, 'ascii');
    header.write('0000000\0', 116, 'ascii');
    header.write(`${size.toString(8).padStart(11, '0')}\0`, 124, 'ascii');
    header.write(`${mtime.toString(8).padStart(11, '0')}\0`, 136, 'ascii');
    header.write('        ', 148, 'ascii');
    header.write(entry.directory ? '5' : '0', 156, 'ascii');
    header.write('ustar\0' + '00', 257, 'ascii');
    let sum = 0;
    for (const byte of header) sum += byte;
    header.write(`${sum.toString(8).padStart(6, '0')}\0 `, 148, 'ascii');
    blocks.push(header);
    if (size > 0) {
      blocks.push(Buffer.from(entry.data.buffer, entry.data.byteOffset, size));
      if (size % BLOCK) blocks.push(Buffer.alloc(BLOCK - (size % BLOCK)));
    }
  }
  blocks.push(Buffer.alloc(2 * BLOCK));
  return Buffer.concat(blocks);
}

/**
 * Reads a tar that writeTar wrote. Anything else it refuses rather than guesses at: another
 * entry type, a bad header checksum, an absolute name or one with a `..` segment.
 *
 * @returns {{name: string, directory: boolean, data: Buffer}[]}
 */
export function readTar(tar) {
  const entries = [];
  for (let at = 0; at + BLOCK <= tar.length;) {
    const header = tar.subarray(at, at + BLOCK);
    if (header.every(byte => byte === 0)) return entries;
    const field = (start, length) => header.toString('ascii', start, start + length).replace(/\0.*$/s, '').trim();
    let sum = 0;
    for (let i = 0; i < BLOCK; i++) sum += i >= 148 && i < 156 ? 0x20 : header[i];
    if (Number.parseInt(field(148, 8), 8) !== sum) throw new Error(`The tar header at ${at} has a bad checksum.`);
    const name = header.toString('utf8', 0, 100).replace(/\0.*$/s, '');
    const prefix = header.toString('utf8', 345, 500).replace(/\0.*$/s, '');
    const full = prefix ? `${prefix}/${name}` : name;
    const type = String.fromCharCode(header[156]);
    const size = Number.parseInt(field(124, 12), 8) || 0;
    if (!['0', '\0', '5'].includes(type)) throw new Error(`${full} is not a file or a directory (tar type ${JSON.stringify(type)}).`);
    if (full.startsWith('/') || full.includes('\\') || full.split('/').some(part => part === '..')) {
      throw new Error(`${full} would land outside the image directory.`);
    }
    at += BLOCK;
    if (at + size > tar.length) throw new Error(`${full} runs past the end of the tar.`);
    entries.push({ name: full, directory: type === '5', data: tar.subarray(at, at + size) });
    at += Math.ceil(size / BLOCK) * BLOCK;
  }
  throw new Error('The tar has no end-of-archive marker.');
}
