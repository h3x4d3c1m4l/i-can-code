// The sourceHash in an image's manifest: what the image was built from, so a checkout can tell
// whether the image it would ship is stale.
//
// It hashes the working tree rather than git's tree objects, so an image built from uncommitted
// changes still names them, and hashing writes nothing into .git.

import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { readFileSync, statSync } from 'node:fs';
import path from 'node:path';

/** Everything that decides what the saved state holds. */
export const SOURCE_PATHS = ['vm/agent', 'vm/image', 'vm/tools/build-state.mjs', 'web/vm/vm_protocol.js'];

/**
 * Every file under `paths` that git tracks or would track, as repository paths in path order.
 * Git-ignored files are not among them, which is why build-image.sh builds from a copy of these
 * rather than from vm/image itself.
 */
export function sourceFiles(repoDir, paths = SOURCE_PATHS) {
  const listed = execFileSync('git', ['ls-files', '-z', '--cached', '--others', '--exclude-standard', '--', ...paths],
    { cwd: repoDir, encoding: 'utf8' });
  return [...new Set(listed.split('\0').filter(Boolean))].sort();
}

/**
 * sha256 over every file of sourceFiles(), each as its repository path, its mode as git records
 * it, and the sha256 of its content, NUL-separated.
 *
 * @returns {{hash: string, files: number}} `hash` is `sha256:` and 64 hex digits.
 */
export function sourceHash(repoDir) {
  const outer = createHash('sha256');
  let count = 0;
  for (const file of sourceFiles(repoDir)) {
    const full = path.join(repoDir, file);
    let content;
    let mode;
    try {
      content = readFileSync(full);
      mode = statSync(full).mode;
    } catch (error) {
      // Tracked, but deleted in the working tree: it is not part of what was built.
      if (error.code === 'ENOENT') continue;
      throw error;
    }
    outer.update(`${file}\0${gitMode(mode)}\0${createHash('sha256').update(content).digest('hex')}\n`);
    count++;
  }
  return { hash: `sha256:${outer.digest('hex')}`, files: count };
}

/**
 * The exec bit, which `COPY files/ /` carries into the image (mdev-input runs only because it is
 * set). Only the owner's, as git reads it: the other bits follow the checkout's umask, and a CI
 * runner and a Mac would hash one tree two ways.
 */
function gitMode(mode) {
  return mode & 0o100 ? '100755' : '100644';
}
