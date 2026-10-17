// Downloads the image vm/image.lock pins, checks it against the pin, and unpacks it into
// web/vm/image/, where `flutter build web` picks it up. A download whose sha256 or size is not the
// pin's is deleted and nothing is unpacked; so is a bundle that is not the image the pin names or
// that the page in this tree could not load. See docs/vm-build.md, "Publishing the image".
//
// Usage: node fetch-image.mjs [--lock FILE] [--dest DIR] [--force]
//
// An image already in place that the pin names is kept if every file of it checks out, and
// anything beside it in the destination is removed. One the pin does not name, such as a local
// build, is replaced only with --force.

import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { Readable } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import zlib from 'node:zlib';

import { AGENT_PROTO, checkDisk, PIN_FILE, readPin, readTar, requireZstd, verifyBundle } from './lib/image-archive.mjs';

const repoDir = path.resolve(path.dirname(new URL(import.meta.url).pathname), '../..');

const { values: opts } = parseArgs({
  options: {
    lock: { type: 'string', default: path.join(repoDir, PIN_FILE) },
    dest: { type: 'string', default: path.join(repoDir, 'web/vm/image') },
    force: { type: 'boolean', default: false },
  },
});

const log = message => console.log(`fetch-image: ${message}`);
const dest = path.resolve(opts.dest);
const workDir = path.join(repoDir, 'vm/build');

try {
  requireZstd();
  if (!fs.existsSync(opts.lock)) throw new Error(`${opts.lock} does not exist: no image is pinned.`);
  const pin = readPin(opts.lock);
  if (pin.agentProto !== AGENT_PROTO) {
    throw new Error(`The pinned image speaks protocol ${pin.agentProto}, web/vm/vm_protocol.js ${AGENT_PROTO}; publish an image built from this tree.`);
  }

  if (!opts.force && fs.existsSync(path.join(dest, 'manifest.json'))) {
    const here = JSON.parse(fs.readFileSync(path.join(dest, 'manifest.json'), 'utf8')).imageId;
    if (here !== pin.imageId) {
      throw new Error(`${dest} holds image ${here}, not the pinned ${pin.imageId}. A local build? Pass --force to replace it.`);
    }
    let intact = true;
    try {
      const manifest = await verifyBundle(dest);
      if (manifest.sourceHash !== pin.sourceHash) throw new Error(`it names ${manifest.sourceHash}, and the pin ${pin.sourceHash}`);
    } catch (error) {
      intact = false;
      log(`${pin.imageId} is in ${dest} but not intact (${error.message}); fetching it again.`);
    }
    if (intact) {
      // `flutter build web` ships everything in there, and the page only ever loads the image
      // manifest.json names.
      for (const name of fs.readdirSync(dest)) {
        if (name === 'manifest.json' || name === pin.imageId) continue;
        fs.rmSync(path.join(dest, name), { recursive: true, force: true });
        log(`removed ${name} from ${dest}: it is not part of image ${pin.imageId}`);
      }
      log(`${pin.imageId} is already in ${dest}, and every file of it holds what the manifest says.`);
      process.exit(0);
    }
  }

  fs.mkdirSync(workDir, { recursive: true });
  checkDisk(workDir, 'before the download', pin.bytes);
  const download = path.join(workDir, `.fetch-${process.pid}.tar.zst`);
  // Not beside the destination: whatever a crash leaves under web/ goes into the next build.
  const staging = path.join(workDir, `.fetch-${process.pid}`);
  try {
    const started = performance.now();
    const { bytes, hash } = await fetchTo(pin.url, download, pin.bytes);
    if (bytes !== pin.bytes || hash !== pin.sha256) {
      throw new Error(`${pin.url} is ${bytes} bytes with sha256 ${hash}, and the pin says ${pin.bytes} bytes with ${pin.sha256}. Refusing it.`);
    }
    log(`downloaded ${(bytes / 1048576).toFixed(1)} MiB in ${Math.round(performance.now() - started)} ms; sha256 matches the pin`);

    const entries = readTar(zlib.zstdDecompressSync(fs.readFileSync(download)));
    fs.rmSync(download, { force: true });
    fs.rmSync(staging, { recursive: true, force: true });
    for (const entry of entries) {
      const [top] = entry.name.split('/');
      if (entry.name !== 'manifest.json' && top !== pin.imageId) {
        throw new Error(`The archive holds ${entry.name}, outside image ${pin.imageId}.`);
      }
      const target = path.join(staging, entry.name);
      if (entry.directory) fs.mkdirSync(target, { recursive: true });
      else {
        fs.mkdirSync(path.dirname(target), { recursive: true });
        fs.writeFileSync(target, entry.data);
      }
    }
    const manifest = await verifyBundle(staging);
    if (manifest.imageId !== pin.imageId || manifest.sourceHash !== pin.sourceHash) {
      throw new Error(`The archive holds image ${manifest.imageId} from ${manifest.sourceHash}, not the pinned ${pin.imageId} from ${pin.sourceHash}.`);
    }

    fs.rmSync(dest, { recursive: true, force: true });
    moveDir(staging, dest);
    log(`${pin.imageId} is in ${dest}: ${manifest.rootfs.files} rootfs files, ${manifest.interpreter?.python ?? 'Python'}, Tk ${manifest.interpreter?.tk ?? '?'}`);
  } finally {
    fs.rmSync(download, { force: true });
    fs.rmSync(staging, { recursive: true, force: true });
  }
} catch (error) {
  console.error(`fetch-image: ${error.message}`);
  process.exit(1);
}

function moveDir(from, to) {
  try {
    fs.renameSync(from, to);
  } catch (error) {
    if (error.code !== 'EXDEV') throw error;
    fs.cpSync(from, to, { recursive: true });
    fs.rmSync(from, { recursive: true, force: true });
  }
}

/**
 * Downloads `url` to `file`, hashing as it goes. More than `limit` bytes is already wrong, so
 * the download stops there rather than filling the disk.
 */
async function fetchTo(url, file, limit) {
  let source;
  if (url.startsWith('file:')) {
    source = fs.createReadStream(fileURLToPath(url));
  } else {
    const response = await fetch(url).catch(error => {
      throw new Error(`${url} could not be downloaded: ${error.cause?.message ?? error.message}`);
    });
    if (!response.ok) throw new Error(`${url} answered HTTP ${response.status}.`);
    source = Readable.fromWeb(response.body);
  }
  const hash = createHash('sha256');
  let bytes = 0;
  await pipeline(source, async function* (chunks) {
    for await (const chunk of chunks) {
      bytes += chunk.length;
      if (bytes > limit) throw new Error(`${url} is larger than the pin's ${limit} bytes. Refusing it.`);
      hash.update(chunk);
      yield chunk;
    }
  }, fs.createWriteStream(file));
  return { bytes, hash: hash.digest('hex') };
}
