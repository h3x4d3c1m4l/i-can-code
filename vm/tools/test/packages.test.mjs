// vm/image/packages.lock and the bundle's NOTICES.txt: the lock read out of an apk database, read
// back, diffed against another, and the notices rendered from it.

import assert from 'node:assert/strict';
import { test } from 'node:test';

import { renderNotices } from '../lib/notices.mjs';
import { diffLocks, formatLock, parseInstalled, readCrates, readKernel, readLock } from '../lib/packages.mjs';

/** The line that opens each carried licence text, and so the end of the notices' own prose. */
const RULE = '-'.repeat(80);

// Two records as apk writes them, file lines and all. The second has no origin or commit.
const INSTALLED = `C:Q18Pz9wvTaBYr2RzvEXE6rYpFiJbI=
P:python3
V:3.12.14-r0
A:x86
L:PSF-2.0
o:python3
c:0123456789abcdef0123456789abcdef01234567
F:usr/bin
R:python3
a:0:0:755
Z:Q1SLkS9hBidUbPwwrw+XR0Whv3ww8=

C:Q1aOF8uBj142eLXKB+WyA7KXUVmdE=
P:font-dejavu
V:2.37-r6
A:noarch
L:Bitstream-Vera AND Public-Domain
F:usr/share/fonts
`;

test('a lock lists every package of the apk database, by name, and reads back as written', () => {
  const { arch, packages } = parseInstalled(INSTALLED);
  assert.equal(arch, 'x86', 'noarch packages do not name the image');
  assert.deepEqual(packages.map(p => p.name), ['font-dejavu', 'python3']);
  assert.deepEqual(packages[1], {
    name: 'python3', version: '3.12.14-r0', license: 'PSF-2.0', origin: 'python3', commit: '0123456789abcdef0123456789abcdef01234567',
  });
  assert.equal(packages[0].origin, 'font-dejavu', 'a package with no origin is its own');

  const text = formatLock({ release: '3.22.6', arch, packages });
  assert.match(text, /^# Alpine 3\.22\.6 x86$/m);
  assert.deepEqual(readLock(text), { release: '3.22.6', arch: 'x86', packages });
  assert.throws(() => parseInstalled('\n\n'), /no packages/);
  assert.throws(() => readLock('python3\t3.12\n'), /2 columns/);
});

test('a diff names what changed, came and went, and counts the rest', () => {
  const pkg = (name, version, license = 'MIT') => ({ name, version, license, origin: name, commit: '' });
  const before = { release: '3.22.6', packages: [pkg('python3', '3.12.14-r0'), pkg('tk', '8.6.16-r0'), pkg('lib2to3', '1-r0'), pkg('musl', '1.2.5-r12')] };
  const after = { release: '3.24.2', packages: [pkg('python3', '3.14.7-r1'), pkg('tk', '8.6.16-r0', 'TCL'), pkg('mpdecimal', '4.0.1-r0'), pkg('musl', '1.2.5-r12')] };
  const { lines, counts } = diffLocks(before, after);
  assert.equal(lines[0], 'Alpine 3.22.6 -> 3.24.2');
  assert.deepEqual(counts, { changed: 2, added: 1, removed: 1, unchanged: 1 });
  assert.ok(lines.some(line => /^~ python3 +3\.12\.14-r0 -> 3\.14\.7-r1$/.test(line)), lines.join('\n'));
  assert.ok(lines.some(line => /^~ tk .*\(licence MIT -> TCL\)$/.test(line)));
  assert.ok(lines.some(line => /^\+ mpdecimal +4\.0\.1-r0$/.test(line)));
  assert.ok(lines.some(line => /^- lib2to3 +1-r0$/.test(line)));
  assert.equal(diffLocks({ release: null, packages: [] }, after).counts.added, 4, 'no lock before: everything is new');
});

// As the Dockerfile's kernel stage writes it.
const KERNEL = [
  'release 6.18.52',
  'source https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.18.52.tar.xz',
  `sha256 ${'b'.repeat(64)}`,
  'config linux-virt 6.18.52-r0 linux-lts 0464ec74b2be9b5bb303482cda729f4f46f854c7',
  '',
].join('\n');

test('the kernel is a line of the lock, so a lock that moves it differs, and a diff names it', () => {
  const kernel = readKernel(KERNEL);
  assert.deepEqual(kernel.config, { name: 'linux-virt', version: '6.18.52-r0', origin: 'linux-lts', commit: '0464ec74b2be9b5bb303482cda729f4f46f854c7' });
  const { arch, packages } = parseInstalled(INSTALLED);
  const text = formatLock({ release: '3.24.2', arch, packages, kernel });
  assert.match(text, /^# Linux 6\.18\.52, built from https:\/\/cdn\.kernel\.org\/\S+ with the config of linux-virt 6\.18\.52-r0$/m);
  assert.deepEqual(readLock(text), { release: '3.24.2', arch, packages, kernel: '6.18.52' });
  const before = readLock(formatLock({ release: '3.24.2', arch, packages, kernel: { ...kernel, release: '6.18.40' } }));
  assert.deepEqual(diffLocks(before, readLock(text)).lines.slice(0, 2), ['Alpine 3.24.2', 'Linux 6.18.40 -> 6.18.52']);
  assert.deepEqual(diffLocks({ release: '3.22.6', packages }, readLock(text)).lines[1], 'Linux (none) -> 6.18.52');
  assert.throws(() => readKernel('release 6.18.52\n'), /lacks/);
});

test('the crates list keeps the toolchain lines and every crate once, the agent itself included', () => {
  const { toolchain, crates } = readCrates([
    '# rustc 1.87.0 (17067e9ac 2025-05-09) (Alpine Linux)',
    '# musl-dev 1.2.5-r12',
    'icc-vm-agent v0.1.0 (/src)|',
    'serde v1.0.219|MIT OR Apache-2.0',
    'x11rb v0.14.1|MIT OR Apache-2.0',
    'serde v1.0.219|MIT OR Apache-2.0 (*)',
    '',
  ].join('\n'));
  assert.deepEqual(toolchain, ['rustc 1.87.0 (17067e9ac 2025-05-09) (Alpine Linux)', 'musl-dev 1.2.5-r12']);
  assert.deepEqual(crates.map(c => `${c.name} ${c.version} ${c.license}`), ['icc-vm-agent 0.1.0 ', 'serde 1.0.219 MIT OR Apache-2.0', 'x11rb 0.14.1 MIT OR Apache-2.0']);
});

test('the notices carry v86\'s licence, every package with its aports commit, and where the sources are', () => {
  const lock = readLock(formatLock({ release: '3.22.6', ...parseInstalled(INSTALLED) }));
  const text = renderNotices({
    lock,
    agent: readCrates('# rustc 1.87.0\nserde v1.0.219|MIT OR Apache-2.0\n'),
    v86: { version: '0.5.461+g589487c', license: 'Copyright (c) 2012, The v86 contributors\nAll rights reserved.\n' },
    biosSource: 'https://github.com/copy/v86/tree/589487c/bios',
    sourceHash: `sha256:${'a'.repeat(64)}`,
  });
  assert.match(text, /v86 0\.5\.461\+g589487c/);
  assert.match(text, /^ {4}Copyright \(c\) 2012, The v86 contributors$/m);
  assert.match(text, /LGPL-3\.0/);
  assert.match(text, /^ {4}python3 +3\.12\.14-r0 +python3 +0123456789abcdef0123456789abcdef01234567 +PSF-2\.0$/m);
  assert.match(text, /distfiles\.alpinelinux\.org\/distfiles\/v3\.22\//);
  assert.match(text, /^ {4}serde +1\.0\.219 +MIT OR Apache-2\.0$/m);
  // A licence text is carried word for word, so the notices' own writing is what these hold.
  // Everything above the first rule is that writing; the texts follow it.
  const prose = text.slice(0, text.indexOf(RULE));
  assert.doesNotMatch(prose, /^Linux/m, 'no kernel section without a kernel.txt');
  assert.doesNotMatch(prose, /\u2014/, 'no em dashes');
  assert.ok(prose.split('\n').every(line => line.length <= 80 || line.startsWith('    ')), 'prose wraps at 80 columns');

  assert.match(text, /^Licence text: GPL-2\.0-only$/m, 'the kernel\'s licence travels with the binary');
  assert.match(text, /^Licence text: LGPL-3\.0-or-later$/m, 'and SeaBIOS\'s');
  assert.match(text, /^Licence text: PSF-2\.0$/m, 'and a package\'s');
  assert.match(text, /GNU GENERAL PUBLIC LICENSE/, 'the text itself, not the identifier again');
  assert.match(text, /good for three\s+years/, 'the written offer stands where the source archive is not to hand');
  assert.doesNotMatch(text, /^No text is carried for/m, 'nothing these parts declare is left without one');
});

test('the notices name the kernel, its tarball and the config it started from', () => {
  const text = renderNotices({
    lock: readLock(formatLock({ release: '3.24.2', ...parseInstalled(INSTALLED) })),
    agent: readCrates(''),
    v86: { version: '0.5.461+g589487c', license: 'MIT\n' },
    biosSource: 'https://github.com/copy/v86/tree/589487c/bios',
    sourceHash: `sha256:${'a'.repeat(64)}`,
    kernel: readKernel(KERNEL),
  });
  const section = text.slice(text.indexOf('Linux 6.18.52\n'), text.indexOf('Alpine Linux 3.24.2'));
  const prose = section.replace(/\s+/g, ' ');
  assert.match(prose, /GPL-2\.0-only WITH Linux-syscall-note/);
  assert.match(prose, /linux-6\.18\.52\.tar\.xz \(sha256 b{64}\)/);
  assert.match(prose, /linux-virt 6\.18\.52-r0 \(linux-lts at aports commit 0464ec74/);
  assert.match(prose, /vm\/image\/kernel\/configure\.sh/);
});
