// vm/tools/lib/source-hash.mjs: what an image's manifest says it was built from.

import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { test } from 'node:test';

import { sourceHash } from '../lib/source-hash.mjs';

/** A repository with one file under vm/image, untracked, which sourceFiles() counts too. */
function repo(t) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'icc-source-hash-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  execFileSync('git', ['init', '--quiet', dir]);
  const file = path.join(dir, 'vm/image/files/usr/lib/icc/mdev-input');
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, '#!/bin/sh\n');
  fs.chmodSync(file, 0o644);
  return { dir, file };
}

test('the exec bit is part of the hash, since COPY carries it into the image', t => {
  const { dir, file } = repo(t);
  const plain = sourceHash(dir);
  assert.equal(plain.files, 1);

  fs.chmodSync(file, 0o755);
  assert.notEqual(sourceHash(dir).hash, plain.hash);

  fs.chmodSync(file, 0o644);
  assert.equal(sourceHash(dir).hash, plain.hash);
});

test('the bits a checkout takes from its umask are not', t => {
  const { dir, file } = repo(t);
  const plain = sourceHash(dir).hash;

  fs.chmodSync(file, 0o664);
  assert.equal(sourceHash(dir).hash, plain, 'group write');
  fs.chmodSync(file, 0o600);
  assert.equal(sourceHash(dir).hash, plain, 'no read for others');
  fs.chmodSync(file, 0o700);
  const executable = sourceHash(dir).hash;
  fs.chmodSync(file, 0o775);
  assert.equal(sourceHash(dir).hash, executable);
});
