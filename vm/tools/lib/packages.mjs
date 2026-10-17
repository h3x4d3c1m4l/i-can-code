// vm/image/packages.lock: every apk package in the guest image with its version, licence, origin
// and the aports commit it was built from, read out of the image's own apk database. It is what
// makes a rebuild's package changes a diff, and what the bundle's NOTICES.txt lists.
// See docs/vm-build.md, "Regenerating the image".

/** The columns of a lock line, tab-separated: a licence expression can hold spaces. */
const COLUMNS = ['name', 'version', 'license', 'origin', 'commit'];

/**
 * The packages in an apk installed database (/lib/apk/db/installed), sorted by name. apk-tools 2
 * and 3 both write this format: one blank-line-separated record per package, one field per line.
 *
 * @returns {{arch: string, packages: {name: string, version: string, license: string, origin: string, commit: string}[]}}
 */
export function parseInstalled(text) {
  const packages = [];
  const arches = new Set();
  for (const record of text.split(/\n\s*\n/)) {
    const field = {};
    for (const line of record.split('\n')) {
      // Only the first of each: F, R and the other per-file fields repeat.
      const match = /^([A-Za-z]):(.*)$/.exec(line);
      if (match && !(match[1] in field)) field[match[1]] = match[2];
    }
    if (!field.P) continue;
    if (field.A) arches.add(field.A);
    packages.push({ name: field.P, version: field.V ?? '', license: field.L ?? '', origin: field.o ?? field.P, commit: field.c ?? '' });
  }
  if (packages.length === 0) throw new Error('the apk database lists no packages');
  // noarch packages (fonts, tzdata, scripts) sit beside the image's own architecture.
  arches.delete('noarch');
  return { arch: [...arches].sort().join(' ') || 'noarch', packages: packages.sort((a, b) => (a.name < b.name ? -1 : 1)) };
}

/**
 * The kernel.txt the Dockerfile's kernel stage writes, `key value` lines: the Linux release it
 * built, the tarball and its sha256, and the linux-virt package whose config it started from.
 *
 * @returns {{release: string, source: string, sha256: string, config: {name: string, version: string, origin: string, commit: string}}}
 */
export function readKernel(text) {
  const fields = {};
  for (const line of text.split('\n')) {
    const match = /^(\S+) (.+)$/.exec(line.trim());
    if (match) fields[match[1]] = match[2];
  }
  const [name, version, origin = '', commit = ''] = (fields.config ?? '').split(' ');
  if (!fields.release || !fields.source || !version) throw new Error('kernel.txt lacks the release, the source or the config it was built with');
  return { release: fields.release, source: fields.source, sha256: fields.sha256 ?? '', config: { name, version, origin, commit } };
}

/**
 * The lock file's text for the packages of an image built on Alpine `release`. The kernel is no
 * apk package, so it is a header line: a lock that moves it still shows as a change.
 */
export function formatLock({ release, arch, packages, kernel }) {
  const clean = value => String(value).replace(/[\t\n]/g, ' ');
  return [
    '# Every apk package in the guest image. Written by vm/tools/build-image.sh from the image\'s',
    '# own apk database; a rebuild rewrites it, so a change here is a change in the image.',
    `# Alpine ${release} ${arch}`,
    ...(kernel ? [`# Linux ${kernel.release}, built from ${kernel.source} with the config of ${kernel.config.name} ${kernel.config.version}`] : []),
    `# ${COLUMNS.join('\t')}`,
    ...packages.map(p => COLUMNS.map(c => clean(p[c])).join('\t')),
    '',
  ].join('\n');
}

/** @returns {{release: string|null, arch: string|null, packages: object[], kernel?: string}} */
export function readLock(text) {
  let release = null;
  let arch = null;
  let kernel = null;
  const packages = [];
  for (const line of text.split('\n')) {
    const header = /^# Alpine (\S+) (.+)$/.exec(line);
    if (header) [, release, arch] = header;
    const linux = /^# Linux ([^\s,]+)/.exec(line);
    if (linux) kernel = linux[1];
    if (!line || line.startsWith('#')) continue;
    const values = line.split('\t');
    if (values.length !== COLUMNS.length) throw new Error(`a lock line has ${values.length} columns, not ${COLUMNS.length}: ${line}`);
    packages.push(Object.fromEntries(COLUMNS.map((c, i) => [c, values[i]])));
  }
  return { release, arch, packages, ...(kernel ? { kernel } : {}) };
}

/**
 * What changed from lock `before` to lock `after`, as lines to print. Versions are listed, not
 * ranked: apk's version order is not worth reimplementing to say "up" or "down".
 */
export function diffLocks(before, after) {
  const old = new Map(before.packages.map(p => [p.name, p]));
  const now = new Map(after.packages.map(p => [p.name, p]));
  const width = Math.max(8, ...[...old.keys(), ...now.keys()].map(name => name.length));
  const lines = [];
  const counts = { changed: 0, added: 0, removed: 0, unchanged: 0 };
  lines.push(before.release === after.release ? `Alpine ${after.release}` : `Alpine ${before.release ?? '(none)'} -> ${after.release}`);
  if (before.kernel || after.kernel) {
    lines.push(before.kernel === after.kernel ? `Linux ${after.kernel}` : `Linux ${before.kernel ?? '(none)'} -> ${after.kernel ?? '(none)'}`);
  }
  for (const name of [...new Set([...old.keys(), ...now.keys()])].sort()) {
    const a = old.get(name);
    const b = now.get(name);
    if (!a) {
      counts.added++;
      lines.push(`+ ${name.padEnd(width)} ${b.version}`);
    } else if (!b) {
      counts.removed++;
      lines.push(`- ${name.padEnd(width)} ${a.version}`);
    } else if (a.version !== b.version || a.license !== b.license) {
      counts.changed++;
      const license = a.license === b.license ? '' : `  (licence ${a.license} -> ${b.license})`;
      lines.push(`~ ${name.padEnd(width)} ${a.version} -> ${b.version}${license}`);
    } else {
      counts.unchanged++;
    }
  }
  lines.push(`${counts.changed} changed, ${counts.added} added, ${counts.removed} removed, ${counts.unchanged} unchanged`);
  return { lines, counts };
}

/**
 * The crates list build-image.sh takes out of the Dockerfile's agent-licences stage: `# ` lines
 * naming the Rust and musl-dev it was linked with, then `cargo tree`'s `name vX.Y.Z|licence`,
 * once per crate.
 *
 * @returns {{toolchain: string[], crates: {name: string, version: string, license: string}[]}}
 */
export function readCrates(text) {
  const toolchain = [];
  const crates = new Map();
  for (const line of text.split('\n')) {
    if (line.startsWith('# ')) {
      toolchain.push(line.slice(2));
      continue;
    }
    // cargo tree marks a crate it has already printed with a trailing (*), whatever --format says.
    const match = /^(\S+) v(\S+)(?: \([^)]*\))?\|(.*?)(?: \(\*\))?$/.exec(line);
    if (match) crates.set(`${match[1]} ${match[2]}`, { name: match[1], version: match[2], license: match[3] });
  }
  return { toolchain, crates: [...crates.values()] };
}
