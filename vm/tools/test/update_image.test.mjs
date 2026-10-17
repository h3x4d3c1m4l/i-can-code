// update-image.sh's committed files: vm/image/Dockerfile and vm/image/packages.lock are rewritten
// before and during the build, so a run that fails afterwards has to put them back. The script
// runs here against a repository of its own, with everything it shells out to stubbed: what is
// under test is which files it leaves behind and what it says about them.

import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { afterEach, test } from 'node:test';

const toolsDir = fileURLToPath(new URL('..', import.meta.url));

const DOCKERFILE = 'ARG ALPINE_VERSION=3.22\nFROM alpine:${ALPINE_VERSION} AS image\n';

const LOCK = (release, extra = '') => [
  '# Every apk package in the guest image.',
  `# Alpine ${release}.1 x86`,
  '# name\tversion\tlicense\torigin\tcommit',
  `busybox\t1.37.0-r1\tGPL-2.0-only\tbusybox\tabc123${extra}`,
  '',
].join('\n');

const stubs = {
  // build-image.sh writes the build's lock and copies it over the committed one, as the real one
  // does for a build of the pinned release into vm/build.
  'build-image.sh': `#!/usr/bin/env bash
set -euo pipefail
mkdir -p "$ICC_VM_BUILD_DIR/logs"
cat > "$ICC_VM_BUILD_DIR/packages.lock" <<'LOCK'
${LOCK('3.24', 'def').trimEnd()}
LOCK
cp "$ICC_VM_BUILD_DIR/packages.lock" "$(dirname "$0")/../image/packages.lock"
`,
  'build-state.mjs': `import fs from 'node:fs';
import path from 'node:path';
const dir = path.join(path.dirname(new URL(import.meta.url).pathname), '../../web/vm/image');
fs.mkdirSync(dir, { recursive: true });
fs.writeFileSync(path.join(dir, 'manifest.json'), JSON.stringify({ imageId: 'abc0123456789def', interpreter: { python: '3.14.7', tk: '8.6.17' } }));
`,
  'check-image.mjs': 'process.exit(0);\n',
  'check-state.mjs': 'process.exit(process.env.ICC_TEST_CHECK_STATE_FAILS ? 1 : 0);\n',
};

let repo = null;

afterEach(() => {
  if (repo) fs.rmSync(repo, { recursive: true, force: true });
  repo = null;
});

/** A repository holding only what update-image.sh reads, with its own tools stubbed out. */
function fakeRepo() {
  repo = fs.mkdtempSync(path.join(os.tmpdir(), 'icc-update-'));
  const tools = path.join(repo, 'vm/tools');
  fs.mkdirSync(path.join(tools, 'lib'), { recursive: true });
  fs.mkdirSync(path.join(repo, 'vm/image'), { recursive: true });
  // Present, so the script's `npm ci` is skipped: nothing here needs a package.
  fs.mkdirSync(path.join(tools, 'node_modules'), { recursive: true });
  for (const file of ['update-image.sh', 'image-packages.mjs']) {
    fs.copyFileSync(path.join(toolsDir, file), path.join(tools, file));
  }
  fs.copyFileSync(path.join(toolsDir, 'lib/packages.mjs'), path.join(tools, 'lib/packages.mjs'));
  for (const [name, source] of Object.entries(stubs)) {
    fs.writeFileSync(path.join(tools, name), source, { mode: name.endsWith('.sh') ? 0o755 : 0o644 });
  }
  fs.writeFileSync(path.join(repo, 'vm/image/Dockerfile'), DOCKERFILE);
  fs.writeFileSync(path.join(repo, 'vm/image/packages.lock'), LOCK('3.22'));
  return repo;
}

function update(repo, { fails }) {
  return spawnSync('bash', [path.join(repo, 'vm/tools/update-image.sh'), '--alpine', '3.24', '--skip-corpus'], {
    encoding: 'utf8',
    env: { ...process.env, ICC_VM_BUILD_DIR: '', ICC_TEST_CHECK_STATE_FAILS: fails ? '1' : '' },
  });
}

const read = (repo, file) => fs.readFileSync(path.join(repo, file), 'utf8');

test('a failed update puts the Dockerfile pin and the package lock back, and says what it could not put back', () => {
  const repo = fakeRepo();
  const result = update(repo, { fails: true });
  assert.equal(result.status, 1, result.stdout + result.stderr);
  assert.match(result.stdout, /vm\/image\/Dockerfile now pins Alpine 3\.24/, 'the pin was written before the build');
  assert.equal(read(repo, 'vm/image/Dockerfile'), DOCKERFILE, 'and is the pin it was again');
  assert.equal(read(repo, 'vm/image/packages.lock'), LOCK('3.22'), 'the committed lock is the one it was');
  assert.match(result.stderr, /FAILED: check-state/);
  assert.match(result.stderr, /Put back:\n {2}vm\/image\/Dockerfile \(Alpine 3\.22 again\)\n {2}vm\/image\/packages\.lock\n/);
  assert.match(result.stderr, /NOT put back: .*web\/vm\/image now holds the bundle this run built/);
});

test('an update that passes keeps the new pin, the new lock and the new bundle', () => {
  const repo = fakeRepo();
  const result = update(repo, { fails: false });
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.match(read(repo, 'vm/image/Dockerfile'), /^ARG ALPINE_VERSION=3\.24$/m);
  assert.equal(read(repo, 'vm/image/packages.lock'), LOCK('3.24', 'def'));
  assert.match(result.stdout, /Every check passed/);
  assert.equal(result.stderr.trim(), '', 'nothing is said about putting anything back');
  assert.ok(fs.existsSync(path.join(repo, 'web/vm/image/manifest.json')));
});

test('a failure before the bundle is built says the app\'s image was not touched', () => {
  const repo = fakeRepo();
  fs.writeFileSync(path.join(repo, 'vm/tools/build-image.sh'), '#!/usr/bin/env bash\nexit 3\n', { mode: 0o755 });
  const result = update(repo, { fails: false });
  assert.equal(result.status, 3);
  assert.equal(read(repo, 'vm/image/Dockerfile'), DOCKERFILE);
  assert.equal(read(repo, 'vm/image/packages.lock'), LOCK('3.22'), 'the build never got as far as rewriting it');
  assert.match(result.stderr, /Put back:\n {2}vm\/image\/Dockerfile \(Alpine 3\.22 again\)\n/);
  assert.match(result.stderr, /web\/vm\/image was not touched/);
});
