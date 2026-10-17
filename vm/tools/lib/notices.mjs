// The NOTICES.txt a bundle ships beside its state: who wrote what the saved machine holds, under
// which licence, with the text of every one of those licences and where the source is.
// build-state.mjs writes it from the package lock, the kernel's kernel.txt and the agent's crates
// list that build-image.sh leaves in the build directory, and write-notices.mjs writes it again
// into a bundle that is already built. The texts come from vm/licences/ (lib/licences.mjs).
// docs/vm-build.md, "Licences", says what it does not yet cover.

import { licenceTexts, TEXTS_HEADING } from './licences.mjs';

const REPOSITORY = 'https://github.com/h3x4d3c1m4l/i-can-code';

/** Parts of the image that are no package and declare no licence of their own. */
const KERNEL_LICENCE = 'GPL-2.0-only';
const SEABIOS_LICENCE = 'LGPL-3.0-or-later';

/**
 * @param {object} parts
 * @param {{release: string, arch: string, packages: object[]}} parts.lock readLock()'s result.
 * @param {{toolchain: string[], crates: object[]}} parts.agent readCrates()'s result.
 * @param {{version: string, license: string}} parts.v86 The v86 build the bundle carries.
 * @param {string} parts.biosSource Where the BIOS images the guest booted with came from.
 * @param {string} parts.sourceHash The manifest's.
 * @param {object} [parts.kernel] readKernel()'s result: the guest's kernel, which is no package.
 */
export function renderNotices({ lock, agent, v86, biosSource, sourceHash, kernel }) {
  const branch = `v${lock.release.split('.').slice(0, 2).join('.')}`;
  const out = [];
  const section = title => out.push('', title, '='.repeat(title.length), '');
  const para = text => out.push(...wrap(text), '');

  out.push('Notices for the Tkinter VM image of I Can Code', '');
  para('This bundle is a saved virtual machine that the page restores in the browser: the v86 ' +
    'emulator, and a Linux guest built from Alpine Linux packages. Each part below keeps its own ' +
    'licence.');
  para(`The image was built from ${REPOSITORY}, sources ${sourceHash}.`);

  section('v86');
  para(`libv86.mjs and v86.wasm are v86 ${v86.version}, https://github.com/copy/v86, under the ` +
    'licence below. They also hold code under other licences, which v86\'s repository keeps beside ' +
    'it: Berkeley SoftFloat (lib/softfloat/), zstd\'s decoder (lib/zstd/) and parts of QEMU\'s floppy ' +
    'emulation (LICENSE.MIT).');
  out.push(...v86.license.trimEnd().split('\n').map(line => (line ? `    ${line}` : '')), '');

  section('SeaBIOS');
  para(`The guest booted with the seabios.bin and vgabios.bin of ${biosSource}, and the saved ` +
    'machine\'s memory holds a copy of both. They are SeaBIOS and its VGA BIOS, under the LGPL-3.0 ' +
    '(COPYING.LESSER in that directory), whose fetch-and-build-seabios.sh and seabios.config name ' +
    'the SeaBIOS source they were built from.');

  if (kernel) {
    const config = kernel.config;
    section(`Linux ${kernel.release}`);
    para(`The guest's kernel is Linux ${kernel.release}, under GPL-2.0-only WITH Linux-syscall-note. ` +
      `This project builds it unpatched from ${kernel.source}${kernel.sha256 ? ` (sha256 ${kernel.sha256})` : ''}, ` +
      `starting from the config of Alpine's ${config.name} ${config.version}` +
      `${config.commit ? ` (${config.origin || config.name} at aports commit ${config.commit})` : ''}, which ` +
      `vm/image/kernel/configure.sh in ${REPOSITORY} cuts down. That script and vm/image/Dockerfile are ` +
      'the rest of what building it takes.');
  }

  section(`Alpine Linux ${lock.release} (${lock.arch})`);
  para(`The guest's ${lock.packages.length} packages, with the licence each declares as an SPDX ` +
    'expression and the commit of Alpine\'s aports repository its APKBUILD was built at. The APKBUILD ' +
    `is main/<origin>/APKBUILD or community/<origin>/APKBUILD at https://gitlab.alpinelinux.org/alpine/aports/-/tree/<commit>; ` +
    'it names the upstream source and every patch Alpine applies. Alpine keeps the upstream sources ' +
    `it built ${branch} from at https://distfiles.alpinelinux.org/distfiles/${branch}/.`);
  // The licence last: an SPDX expression runs to 70 characters, and would push every column after it.
  out.push(...table(['package', 'version', 'origin', 'aports commit', 'licence'],
    lock.packages.map(p => [p.name, p.version, p.origin, p.commit, p.license])), '');

  section('icc-agent');
  para(`/usr/local/bin/icc-agent and /usr/lib/icc/ are this project's own code, ${REPOSITORY} ` +
    '(vm/agent/ and vm/image/files/). The agent is linked statically with Rust\'s standard library ' +
    '(MIT OR Apache-2.0), musl (MIT) and the crates below.');
  if (agent.toolchain.length) out.push(...agent.toolchain.map(line => `    ${line}`), '');
  out.push(...table(['crate', 'version', 'licence'], agent.crates.map(c => [c.name, c.version, c.license || '(this project)'])), '');

  const parts = [
    { name: `Linux ${kernel?.release ?? ''}`.trim(), licence: KERNEL_LICENCE },
    { name: 'SeaBIOS', licence: SEABIOS_LICENCE },
    ...lock.packages.map(p => ({ name: p.name, licence: p.license, own: true })),
    ...agent.crates.filter(c => c.license).map(c => ({ name: c.name, licence: c.license })),
  ];
  const { sections, missing, noText } = licenceTexts(parts);

  section('Source');
  para('The complete corresponding source of everything above is the asset whose name ends in ' +
    '-source.tar.zst, on the same release as this image: the Alpine aports tree at each commit in ' +
    'the table, the upstream archives those APKBUILDs name, the kernel tarball named above, the ' +
    `SeaBIOS source named above, and this project's own sources at ${sourceHash}.`);
  para('Where you have the binaries without it, this is a written offer, good for three years ' +
    `from the day this image was released: ask at ${REPOSITORY}/issues for the complete ` +
    'corresponding machine-readable source of any GPL or LGPL part of this image, and it will be ' +
    'given to you on a medium customarily used for software interchange, for no more than the ' +
    'cost of performing that distribution. The offer is made to any third party, whoever passed ' +
    'the image on to you.');

  section(TEXTS_HEADING);
  para('The text of every licence named above, as the SPDX licence list publishes it, and the ' +
    'licence file of a package whose licence is its own. A text is the licence and not the ' +
    'copyright lines: those are in each package\'s own source, which the source above carries.');
  if (noText.length) para(`Declaring no licence to carry a text for: ${noText.join(', ')}.`);
  if (missing.length) {
    para('No text is carried for: ' + missing.map(m => `${m.token} (${m.named.join(', ')})`).join('; ') +
      '. Add it to vm/licences/ in the repository above.');
  }
  for (const { tokens, note, text } of sections) {
    out.push('-'.repeat(80), `Licence text: ${tokens.join(', ')}${note ? ` (${note})` : ''}`, '-'.repeat(80), '');
    out.push(text, '');
  }
  return out.join('\n').trimStart();
}

function wrap(text, width = 80) {
  const lines = [];
  let line = '';
  for (const word of text.split(/\s+/)) {
    if (line && line.length + 1 + word.length > width) {
      lines.push(line);
      line = word;
    } else {
      line = line ? `${line} ${word}` : word;
    }
  }
  if (line) lines.push(line);
  return lines;
}

function table(header, rows) {
  const widths = header.map((h, i) => Math.max(h.length, ...rows.map(r => r[i].length)));
  const format = row => `    ${row.map((cell, i) => (i === row.length - 1 ? cell : cell.padEnd(widths[i]))).join('  ')}`;
  return [format(header), ...rows.map(format)];
}
