// The licence texts a bundle carries: which ones a set of parts needs, which are missing, and the
// check that stands between a bundle and a release. lib/licences.mjs, and vm/licences/ itself
// against the committed package lock.

import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

import {
  isCopyleft,
  licenceFamily,
  licenceIds,
  licenceTexts,
  licenceTextsIn,
  missingCopyleftTexts,
  readLicenceTexts,
} from '../lib/licences.mjs';
import { renderNotices } from '../lib/notices.mjs';
import { readLock } from '../lib/packages.mjs';

const repo = fileURLToPath(new URL('../../..', import.meta.url));

/** A vm/licences/ of its own, so these tests say nothing about how many texts the repository has. */
function texts(files, own = {}) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'icc-licences-'));
  fs.mkdirSync(path.join(dir, 'packages'));
  for (const [name, text] of Object.entries(files)) fs.writeFileSync(path.join(dir, `${name}.txt`), text);
  for (const [name, text] of Object.entries(own)) fs.writeFileSync(path.join(dir, 'packages', `${name}.txt`), text);
  return readLicenceTexts(dir);
}

test('an expression names every licence the binary could be under, whichever way it joins them', () => {
  assert.deepEqual(licenceIds('MIT OR Apache-2.0'), ['MIT', 'Apache-2.0']);
  assert.deepEqual(licenceIds('GPL-2.0-only WITH Linux-syscall-note'), ['GPL-2.0-only', 'Linux-syscall-note']);
  assert.deepEqual(licenceIds('(MIT AND BSD-3-Clause) OR MIT'), ['MIT', 'BSD-3-Clause'], 'each one once');
  assert.deepEqual(licenceIds('custom'), ['custom'], 'what Alpine writes where SPDX has no name');
  assert.deepEqual(licenceIds(''), []);
  assert.deepEqual(licenceIds(undefined), []);
});

test('copyleft is what asks for its text and its source, and -only and -or-later are one text', () => {
  assert.ok(isCopyleft('GPL-2.0-only'));
  assert.ok(isCopyleft('LGPL-2.1-or-later'));
  assert.ok(isCopyleft('MPL-2.0'));
  assert.ok(!isCopyleft('MIT'));
  assert.ok(!isCopyleft('Apache-2.0'));
  assert.ok(!isCopyleft('custom'));
  assert.equal(licenceFamily('GPL-2.0-only'), 'GPL-2.0');
  assert.equal(licenceFamily('GPL-2.0-or-later'), 'GPL-2.0');
  assert.equal(licenceFamily('MIT'), 'MIT');
});

test('a text is carried once however many parts share it, and the parts that share it are named', () => {
  const { sections, missing, noText } = licenceTexts([
    { name: 'busybox', licence: 'GPL-2.0-only', own: true },
    { name: 'musl', licence: 'MIT', own: true },
    { name: 'serde', licence: 'MIT OR Apache-2.0' },
  ], texts({ 'GPL-2.0-only': 'GNU GPL v2', MIT: 'MIT text', 'Apache-2.0': 'Apache text' }));
  assert.deepEqual(missing, []);
  assert.deepEqual(noText, []);
  assert.deepEqual(sections.map(s => s.tokens), [['Apache-2.0'], ['GPL-2.0-only'], ['MIT']]);
  assert.deepEqual(sections.map(s => s.text), ['Apache text', 'GNU GPL v2', 'MIT text']);
});

test('two identifiers whose text is the same file are one section under both names', () => {
  const both = 'GNU GENERAL PUBLIC LICENSE Version 2';
  const { sections } = licenceTexts([
    { name: 'busybox', licence: 'GPL-2.0-only' },
    { name: 'util-linux', licence: 'GPL-2.0-or-later' },
  ], texts({ 'GPL-2.0-only': both, 'GPL-2.0-or-later': both }));
  assert.equal(sections.length, 1);
  assert.deepEqual(sections[0].tokens, ['GPL-2.0-only', 'GPL-2.0-or-later']);
});

test('a package whose licence is its own is answered by its own file, and says where the text came from', () => {
  const { sections, missing } = licenceTexts(
    [{ name: 'libxcvt', licence: 'custom', own: true }],
    texts({}, { libxcvt: 'Copyright the X.Org contributors' }),
  );
  assert.deepEqual(missing, []);
  assert.deepEqual(sections[0].tokens, ['libxcvt'], 'under the package name: there is no identifier to name it by');
  assert.match(sections[0].note, /the package's own licence file; it declares "custom"/);
});

test('a licence nothing carries a text for is reported, with the parts that need it and whether it is copyleft', () => {
  const { missing, sections } = licenceTexts([
    { name: 'busybox', licence: 'GPL-2.0-only' },
    { name: 'util-linux', licence: 'GPL-2.0-only' },
    { name: 'tk', licence: 'TCL' },
    { name: 'font-dejavu', licence: 'Bitstream-Vera AND Public-Domain' },
  ], texts({ 'Bitstream-Vera': 'Bitstream text' }));
  assert.deepEqual(sections.map(s => s.tokens), [['Bitstream-Vera']]);
  assert.deepEqual(missing, [
    { token: 'GPL-2.0-only', copyleft: true, named: ['busybox', 'util-linux'] },
    { token: 'TCL', copyleft: false, named: ['tk'] },
  ]);
});

test('a declaration that is no licence is not a gap: there is no text to carry', () => {
  const { missing, noText } = licenceTexts(
    [{ name: 'encodings', licence: 'Public Domain' }, { name: 'font-misc', licence: 'Public-Domain' }],
    texts({}),
  );
  assert.deepEqual(missing, [], 'nothing to fetch and nothing to add');
  assert.deepEqual(noText, ['encodings (Public Domain)', 'font-misc (Public-Domain)']);
});

test('a package that declares "custom" and carries no file of its own is a gap, not a free pass', () => {
  const { missing } = licenceTexts([{ name: 'font-alias', licence: 'custom', own: true }], texts({}));
  assert.deepEqual(missing, [{ token: 'custom', copyleft: false, named: ['font-alias'] }]);
});

// The release gate

const NOTICES = (named, carried = []) => [
  'Notices for the Tkinter VM image of I Can Code',
  '',
  'The guest booted with SeaBIOS, under the LGPL-3.0-or-later.',
  '',
  '    package  version  licence',
  ...named.map(licence => `    a-package  1.0  ${licence}`),
  '',
  'Licence texts',
  '=============',
  '',
  ...carried.flatMap(token => ['-'.repeat(80), `Licence text: ${token}`, '-'.repeat(80), '', 'THE TEXT', '']),
].join('\n');

test('the tokens a NOTICES.txt carries a text for are read back off its own headings', () => {
  const notices = NOTICES(['MIT'], ['GPL-2.0-only, GPL-2.0-or-later', "libxcvt (the package's own licence file; it declares \"custom\")"]);
  assert.deepEqual([...licenceTextsIn(notices)].sort(), ['GPL-2.0-only', 'GPL-2.0-or-later', 'libxcvt']);
});

test('a copyleft licence the notices name without carrying its text is what stands between a bundle and a release', () => {
  assert.deepEqual(missingCopyleftTexts(NOTICES(['GPL-2.0-only', 'MIT'], ['MIT'])), ['GPL-2.0', 'LGPL-3.0'],
    'the prose names SeaBIOS\'s licence too, and it is as much a gap as a package\'s');
  assert.deepEqual(missingCopyleftTexts(NOTICES(['MIT'], ['MIT', 'LGPL-3.0-or-later'])), [],
    'a permissive licence with no text is no reason to hold a release: this check is the copyleft one');
});

test('one text answers a whole family, so GPL-2.0-only is covered by the GPL-2.0-or-later text', () => {
  assert.deepEqual(missingCopyleftTexts(NOTICES(['GPL-2.0-only'], ['GPL-2.0-or-later', 'LGPL-3.0-or-later'])), []);
});

test('an identifier that appears only inside a carried text asks for nothing: the texts quote each other', () => {
  const notices = `${NOTICES(['MIT'], ['LGPL-3.0-or-later'])}\nyou may convey it under the terms of the GPL-3.0-or-later instead.\n`;
  assert.deepEqual(missingCopyleftTexts(notices), [], 'the wanted set is read above the texts, not through them');
});

test('every licence the committed package lock declares has a text in vm/licences/', { skip: lockSkip() }, () => {
  const lock = readLock(fs.readFileSync(path.join(repo, 'vm/image/packages.lock'), 'utf8'));
  // The notices of that lock alone: the packages, plus the kernel and SeaBIOS, which are no
  // package and whose licences notices.mjs states. What the agent's crates declare is in the
  // build directory, so a release is where those are held to this, not a checkout.
  const notices = renderNotices({
    lock,
    agent: { toolchain: [], crates: [] },
    v86: { version: 'test', license: 'MIT\n' },
    biosSource: 'https://github.com/copy/v86/tree/test/bios',
    sourceHash: `sha256:${'a'.repeat(64)}`,
  });
  assert.doesNotMatch(notices, /^No text is carried for/m,
    'add the text to vm/licences/ (vm/licences/README.md says where each came from)');
  assert.deepEqual(missingCopyleftTexts(notices), []);
});

function lockSkip() {
  return fs.existsSync(path.join(repo, 'vm/image/packages.lock')) ? false : 'needs vm/image/packages.lock';
}
