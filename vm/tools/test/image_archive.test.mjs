// The released image: vm/tools/lib/image-archive.mjs's tar and pin, and package-image.mjs and
// fetch-image.mjs round-tripping a small bundle through a file: URL, with the refusals that keep a
// wrong download out of web/vm/image/.

import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { after, test } from 'node:test';
import { pathToFileURL } from 'node:url';
import zlib from 'node:zlib';

import { minFreeKb, readPin, readTar, rootfsMismatch, verifyBundle, writeTar } from '../lib/image-archive.mjs';

const tools = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const noZstd = typeof zlib.zstdCompressSync === 'function' ? false : 'needs a Node with zstd in node:zlib';
const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'icc-vm-image-'));
after(() => fs.rmSync(scratch, { recursive: true, force: true }));

// Tar

test('a tar comes back as it was written, whatever the sizes', () => {
  const entries = [
    { name: 'manifest.json', data: Buffer.from('{}') },
    { name: 'abc/', directory: true },
    { name: 'abc/empty', data: Buffer.alloc(0) },
    { name: 'abc/block', data: Buffer.alloc(512, 7) },
    { name: 'abc/odd', data: Buffer.alloc(1000, 9) },
  ];
  const read = readTar(writeTar(entries, 1_700_000_000));
  assert.deepEqual(read.map(e => [e.name, e.directory, e.data.length]), [
    ['manifest.json', false, 2], ['abc/', true, 0], ['abc/empty', false, 0], ['abc/block', false, 512], ['abc/odd', false, 1000],
  ]);
  assert.deepEqual(read[4].data, entries[4].data);
});

test('a tar that would write outside its directory, or holds a link, is refused', () => {
  assert.throws(() => readTar(writeTar([{ name: '../escape', data: Buffer.from('x') }], 0)), /outside the image directory/);
  assert.throws(() => readTar(writeTar([{ name: '/etc/passwd', data: Buffer.from('x') }], 0)), /outside the image directory/);
  const link = writeTar([{ name: 'link', data: Buffer.alloc(0) }], 0);
  link.write('2', 156, 'ascii');
  let sum = 0;
  for (let i = 0; i < 512; i++) sum += i >= 148 && i < 156 ? 0x20 : link[i];
  link.write(`${sum.toString(8).padStart(6, '0')}\0 `, 148, 'ascii');
  assert.throws(() => readTar(link), /not a file or a directory/);
});

test('a damaged or cut tar is refused', () => {
  const tar = writeTar([{ name: 'a', data: Buffer.alloc(2000, 1) }], 0);
  const damaged = Buffer.from(tar);
  damaged[3] ^= 1;
  assert.throws(() => readTar(damaged), /bad checksum/);
  assert.throws(() => readTar(tar.subarray(0, 1024)), /past the end/);
});

// Pins

const PIN = {
  imageId: '0123456789abcdef',
  url: 'https://example.org/vm-image-0123456789abcdef.tar.zst',
  sha256: 'a'.repeat(64),
  bytes: 1234,
  sourceHash: `sha256:${'b'.repeat(64)}`,
  agentProto: 1,
};

function pinFile(pin) {
  const file = path.join(fs.mkdtempSync(path.join(scratch, 'pin-')), 'image.lock');
  fs.writeFileSync(file, JSON.stringify(pin));
  return file;
}

test('a pin names every field it needs, in the shape it needs', () => {
  assert.deepEqual(readPin(pinFile(PIN)), PIN);
  assert.throws(() => readPin(pinFile({ ...PIN, sha256: 'A'.repeat(64) })), /`sha256`/);
  assert.throws(() => readPin(pinFile({ ...PIN, url: 'ftp://example.org/x' })), /`url`/);
  assert.throws(() => readPin(pinFile({ ...PIN, imageId: '../../etc' })), /`imageId`/);
  const { bytes, ...noBytes } = PIN;
  void bytes;
  assert.throws(() => readPin(pinFile(noBytes)), /`bytes`/);
});

// Bundles, packed and fetched

/** A rootfs file as copy-to-sha256.py writes it: zstd, named for its content, and no bytes when empty. */
function rootfsFile(content) {
  return [`${sha256(content).slice(0, 10)}.bin.zst`, content.length ? zlib.zstdCompressSync(content) : Buffer.alloc(0)];
}

/** A bundle laid out as build-state.mjs writes one, small enough to pack in a test.
 *  `notices` is false for a bundle from before NOTICES.txt, or the text one carries. */
function makeBundle(dir, { agentProto = 1, notices = true } = {}) {
  const state = Buffer.from('a saved machine');
  const noticesText = Buffer.from(typeof notices === 'string' ? notices : 'Notices for the Tkinter VM image\n');
  const wasm = Buffer.from([0, 0x61, 0x73, 0x6D, 1, 0, 0, 0]);
  const imageId = sha256(state).slice(0, 16);
  const rootfs = Object.fromEntries([Buffer.from('print("hello")\n'.repeat(200)), Buffer.from('x = 1\n'), Buffer.alloc(0)].map(rootfsFile));
  const rootfsBytes = Object.values(rootfs).reduce((sum, data) => sum + data.length, 0);
  const manifest = {
    imageId,
    v86: { version: 'test', lib: 'libv86.mjs', wasm: 'v86.wasm', wasmBytes: wasm.length, wasmSha256: sha256(wasm) },
    state: { file: 'state.bin.zst', bytes: state.length, sha256: sha256(state), rawBytes: 64 },
    rootfs: { dir: 'rootfs/', files: 3, bytes: rootfsBytes },
    ...(notices ? { notices: { file: 'NOTICES.txt', bytes: noticesText.length, sha256: sha256(noticesText) } } : {}),
    agentProto,
    sourceHash: `sha256:${'c'.repeat(64)}`,
    builtAt: '2026-09-19T12:00:00.000Z',
  };
  const bundle = path.join(dir, imageId);
  fs.mkdirSync(path.join(bundle, 'rootfs'), { recursive: true });
  fs.writeFileSync(path.join(bundle, 'state.bin.zst'), state);
  fs.writeFileSync(path.join(bundle, 'v86.wasm'), wasm);
  fs.writeFileSync(path.join(bundle, 'libv86.mjs'), 'export class V86 {}\n');
  if (notices) fs.writeFileSync(path.join(bundle, 'NOTICES.txt'), noticesText);
  for (const [name, data] of Object.entries(rootfs)) fs.writeFileSync(path.join(bundle, 'rootfs', name), data);
  const json = `${JSON.stringify(manifest, null, 1)}\n`;
  fs.writeFileSync(path.join(bundle, 'manifest.json'), json);
  fs.writeFileSync(path.join(dir, 'manifest.json'), json);
  return manifest;
}

function node(script, args, env = {}) {
  const result = spawnSync(process.execPath, [path.join(tools, script), ...args], { encoding: 'utf8', env: { ...process.env, ...env } });
  return { code: result.status, out: result.stdout + result.stderr };
}

/** The bundle's first non-empty rootfs file, the one a test damages. */
function firstRootfsFile(dir, manifest) {
  const rootfs = path.join(dir, manifest.imageId, 'rootfs');
  return path.join(rootfs, fs.readdirSync(rootfs).sort().find(name => fs.statSync(path.join(rootfs, name)).size > 0));
}

/** One bit flipped in the middle, so the file keeps its size. */
function flipMiddle(file) {
  const data = fs.readFileSync(file);
  data[data.length >> 1] ^= 1;
  fs.writeFileSync(file, data);
}

test('a bundle is held to its manifest', { skip: noZstd }, async () => {
  const dir = fs.mkdtempSync(path.join(scratch, 'bundle-'));
  const manifest = makeBundle(dir);
  assert.equal((await verifyBundle(dir)).imageId, manifest.imageId);

  fs.appendFileSync(firstRootfsFile(dir, manifest), 'x');
  await assert.rejects(verifyBundle(dir), new RegExp(`holds 3 files of ${manifest.rootfs.bytes + 1} bytes`));
  fs.writeFileSync(path.join(dir, manifest.imageId, 'v86.wasm'), Buffer.from([0, 0x61, 0x73, 0x6D, 1, 0, 0, 1]));
  await assert.rejects(verifyBundle(dir), /v86\.wasm has sha256/);

  const other = fs.mkdtempSync(path.join(scratch, 'bundle-'));
  makeBundle(other, { agentProto: 99 });
  await assert.rejects(verifyBundle(other), /protocol 99/);
});

test('a rootfs file damaged in place, at the same size, is refused by its name', { skip: noZstd }, async () => {
  const dir = fs.mkdtempSync(path.join(scratch, 'bundle-'));
  const manifest = makeBundle(dir);
  const file = firstRootfsFile(dir, manifest);
  flipMiddle(file);

  await assert.rejects(verifyBundle(dir), new RegExp(`${path.basename(file).replace('.', '\\.')} (does not decompress|holds content whose sha256 begins)`));
});

test('a rootfs file is what its name says, an empty one included', { skip: noZstd }, () => {
  const [name, data] = rootfsFile(Buffer.from('import tkinter\n'));
  assert.equal(rootfsMismatch(name, data), null);
  assert.equal(rootfsMismatch(...rootfsFile(Buffer.alloc(0))), null);
  assert.equal(rootfsMismatch('e3b0c44298.bin.zst', Buffer.alloc(0)), null, 'what copy-to-sha256.py writes for an empty file');
  assert.match(rootfsMismatch(`0000000000.bin.zst`, data), /sha256 begins/);
  assert.match(rootfsMismatch('notes.txt', data), /not named for its content/);
});

test('a bundle holding a file its manifest does not name is refused', { skip: noZstd }, async () => {
  const dir = fs.mkdtempSync(path.join(scratch, 'bundle-'));
  const manifest = makeBundle(dir);
  fs.writeFileSync(path.join(dir, manifest.imageId, '.DS_Store'), 'x');

  await assert.rejects(verifyBundle(dir), /\.DS_Store is not part of the image/);
});

test('NOTICES.txt is held to its manifest, and a bundle without one is fetched but never packed', { skip: noZstd }, async () => {
  const dir = fs.mkdtempSync(path.join(scratch, 'bundle-'));
  const manifest = makeBundle(dir);
  fs.appendFileSync(path.join(dir, manifest.imageId, 'NOTICES.txt'), 'x');
  await assert.rejects(verifyBundle(dir), /NOTICES\.txt is \d+ bytes/);

  const old = fs.mkdtempSync(path.join(scratch, 'bundle-'));
  const oldManifest = makeBundle(old, { notices: false });
  assert.equal((await verifyBundle(old)).imageId, oldManifest.imageId, 'a pin may name an image from before NOTICES.txt');
  fs.writeFileSync(path.join(old, oldManifest.imageId, 'NOTICES.txt'), 'x');
  await assert.rejects(verifyBundle(old), /NOTICES\.txt is not part of the image/);
  fs.rmSync(path.join(old, oldManifest.imageId, 'NOTICES.txt'));

  const out = fs.mkdtempSync(path.join(scratch, 'out-'));
  const refused = node('package-image.mjs', ['--image-dir', old, '--out-dir', out, '--url', 'https://example.org/x', '--allow-stale']);
  assert.equal(refused.code, 1);
  assert.match(refused.out, /has no NOTICES\.txt/);
  assert.deepEqual(fs.readdirSync(out), []);
});

test('a bundle whose notices name a copyleft licence and carry no text for it is never packed', { skip: noZstd }, () => {
  const named = 'Notices for the Tkinter VM image\n\n    busybox  1.37.0-r1  GPL-2.0-only\n';
  const dir = fs.mkdtempSync(path.join(scratch, 'bundle-'));
  makeBundle(dir, { notices: named });
  const out = fs.mkdtempSync(path.join(scratch, 'out-'));
  const refused = node('package-image.mjs', ['--image-dir', dir, '--out-dir', out, '--url', 'https://example.org/x', '--allow-stale']);
  assert.equal(refused.code, 1);
  assert.match(refused.out, /names GPL-2\.0 and carries no text for it/);
  assert.deepEqual(fs.readdirSync(out), [], 'a gap cannot be put right once the image is in a browser');

  const carried = fs.mkdtempSync(path.join(scratch, 'bundle-'));
  makeBundle(carried, { notices: `${named}\nLicence texts\n\n${'-'.repeat(80)}\nLicence text: GPL-2.0-only\n${'-'.repeat(80)}\n\nGNU GPL v2\n` });
  const packed = node('package-image.mjs', ['--image-dir', carried, '--out-dir', out, '--url', 'https://example.org/x', '--allow-stale']);
  assert.equal(packed.code, 0, packed.out);
  assert.ok(fs.readdirSync(out).some(name => name.endsWith('.tar.zst')));
});

// Disk

test('the free space asked for scales with what is written, and the environment can set it', () => {
  assert.equal(minFreeKb(74_000_000, {}), Math.ceil(3 * 74_000_000 / 1024));
  assert.equal(minFreeKb(74_000_000, { ICC_VM_MIN_FREE_KB: '0' }), 0);
  assert.equal(minFreeKb(1, { ICC_VM_MIN_FREE_KB: '5767168' }), 5_767_168);
  assert.equal(minFreeKb(1024, { ICC_VM_MIN_FREE_KB: '' }), 3, 'an empty variable is no override');
  assert.throws(() => minFreeKb(1, { ICC_VM_MIN_FREE_KB: '5.5G' }), /ICC_VM_MIN_FREE_KB=5\.5G/);
});

test('packing stops with DISK_LOW under the floor, and writes nothing', { skip: noZstd }, () => {
  const image = fs.mkdtempSync(path.join(scratch, 'image-'));
  const out = fs.mkdtempSync(path.join(scratch, 'out-'));
  makeBundle(image);
  // More than any disk has.
  const refused = node('package-image.mjs', ['--image-dir', image, '--out-dir', out, '--url', 'https://example.org/x', '--allow-stale'],
    { ICC_VM_MIN_FREE_KB: String(Number.MAX_SAFE_INTEGER) });
  assert.equal(refused.code, 1);
  assert.match(refused.out, /DISK_LOW/);
  assert.deepEqual(fs.readdirSync(out), []);
});

test('a packed bundle fetches back byte for byte, and a tampered one is refused', { skip: noZstd }, async () => {
  const image = fs.mkdtempSync(path.join(scratch, 'image-'));
  const out = fs.mkdtempSync(path.join(scratch, 'out-'));
  const manifest = makeBundle(image);
  const archive = path.join(out, `vm-image-${manifest.imageId}.tar.zst`);
  const url = pathToFileURL(archive).href;

  const packed = node('package-image.mjs', ['--image-dir', image, '--out-dir', out, '--url', url, '--allow-stale']);
  assert.equal(packed.code, 0, packed.out);
  const pin = readPin(path.join(out, `vm-image-${manifest.imageId}.lock`));
  assert.equal(pin.url, url);
  assert.equal(pin.sha256, sha256(fs.readFileSync(archive)));
  assert.equal(fs.readFileSync(`${archive}.sha256`, 'utf8'), `${pin.sha256}  vm-image-${manifest.imageId}.tar.zst\n`);

  const lock = path.join(out, `vm-image-${manifest.imageId}.lock`);
  const dest = path.join(scratch, 'fetched');
  const fetched = node('fetch-image.mjs', ['--lock', lock, '--dest', dest]);
  assert.equal(fetched.code, 0, fetched.out);
  const files = dir => execFileSync('find', ['.', '-type', 'f'], { cwd: dir, encoding: 'utf8' }).split('\n').sort();
  assert.deepEqual(files(dest), files(image));
  for (const file of files(image).filter(Boolean)) {
    assert.deepEqual(fs.readFileSync(path.join(dest, file)), fs.readFileSync(path.join(image, file)), file);
  }

  const again = node('package-image.mjs', ['--image-dir', image, '--out-dir', out, '--url', url, '--allow-stale']);
  assert.equal(again.code, 0, again.out);
  assert.equal(readPin(lock).sha256, pin.sha256, 'the same bundle packs to the same bytes');

  // Kept, and whatever else was beside it removed: `flutter build web` would ship it.
  fs.mkdirSync(path.join(dest, 'deadbeefdeadbeef', 'rootfs'), { recursive: true });
  fs.writeFileSync(path.join(dest, 'deadbeefdeadbeef', 'manifest.json'), '{}');
  const kept = node('fetch-image.mjs', ['--lock', lock, '--dest', dest]);
  assert.equal(kept.code, 0, kept.out);
  assert.match(kept.out, /removed deadbeefdeadbeef/);
  assert.match(kept.out, /already in/);
  assert.deepEqual(fs.readdirSync(dest).sort(), [manifest.imageId, 'manifest.json'].sort());

  // A rootfs file damaged in place is not kept: the image is fetched again, and the file with it.
  const damaged = firstRootfsFile(dest, manifest);
  flipMiddle(damaged);
  const refetched = node('fetch-image.mjs', ['--lock', lock, '--dest', dest]);
  assert.equal(refetched.code, 0, refetched.out);
  assert.match(refetched.out, /not intact/);
  assert.deepEqual(fs.readFileSync(damaged), fs.readFileSync(path.join(image, path.relative(dest, damaged))));

  const tampered = fs.readFileSync(archive);
  tampered[tampered.length - 20] ^= 1;
  fs.writeFileSync(archive, tampered);
  const refused = node('fetch-image.mjs', ['--lock', lock, '--dest', path.join(scratch, 'refused')]);
  assert.equal(refused.code, 1);
  assert.match(refused.out, /Refusing it/);
  assert.equal(fs.existsSync(path.join(scratch, 'refused')), false, 'nothing is unpacked');
});

test('a pin whose image speaks another protocol is refused before anything is downloaded', () => {
  const refused = node('fetch-image.mjs', ['--lock', pinFile({ ...PIN, agentProto: 99, url: 'file:///nonexistent.tar.zst' }), '--dest', path.join(scratch, 'x')]);
  assert.equal(refused.code, 1);
  assert.match(refused.out, /protocol 99/);
});
