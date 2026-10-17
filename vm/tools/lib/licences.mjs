// The licence texts a bundle has to carry, and the check that it carries them. The GPL and the
// LGPL ask for their text to travel with the binary, so NOTICES.txt holds the text of every
// licence the image's packages, the kernel, SeaBIOS and the agent's crates declare.
//
// The texts are vm/licences/: one file per SPDX identifier, plus packages/<name>.txt for a
// package whose licence is its own. vm/licences/README.md says where each came from.
// docs/vm-build.md, "Licences", is the whole picture, the source archive included.

import fs from 'node:fs';
import path from 'node:path';

import { repoDir } from './dirs.mjs';

/** One file per SPDX identifier, and packages/<name>.txt for a licence of a package's own. */
export const licencesDir = path.join(repoDir, 'vm/licences');

/** The heading of the section that carries the texts, and the line that opens each one. */
export const TEXTS_HEADING = 'Licence texts';
const TEXT_MARK = 'Licence text: ';

/** A declaration that is not a licence and has no text to carry. `custom` is not one of them:
 *  it is a licence whose text is the package's own, and a package that has neither is a gap. */
const NO_TEXT = new Set(['Public Domain', 'Public-Domain']);

/** A licence that asks for its own text to travel with the binary, and for source to be offered. */
const COPYLEFT = /^(?:LGPL|AGPL|GPL|MPL|EPL|CDDL|EUPL|OSL|CECILL)-/i;

/** The same, as it appears in prose and in the package table: `LGPL-2.1-or-later`, `MPL-2.0`. */
const COPYLEFT_ID = /\b(?:LGPL|AGPL|GPL|MPL|EPL|CDDL|EUPL|OSL|CECILL)-\d+(?:\.\d+)*(?:-only|-or-later)?\b/g;

/**
 * The licence identifiers an SPDX expression names, in the order it names them. `OR`, `AND` and
 * `WITH` all count: an image ships the binary, so every licence it could be under is one whose
 * text a reader may need. Alpine writes a few that SPDX does not know (`custom`, `Public Domain`);
 * they come back as they are and `NO_TEXT` decides what to do with them.
 */
export function licenceIds(expression) {
  return [...new Set(String(expression ?? '')
    .replace(/[()]/g, ' ')
    .split(/\s+(?:OR|AND|WITH)\s+/i)
    .map(id => id.trim())
    .filter(Boolean))];
}

export function isCopyleft(id) {
  return COPYLEFT.test(id);
}

/** `GPL-2.0-only` and `GPL-2.0-or-later` are one text, and so one family. */
export function licenceFamily(id) {
  return id.replace(/-(?:only|or-later)$/i, '');
}

/** The texts in `dir`: `byId` from `<id>.txt`, `byPackage` from `packages/<name>.txt`. */
export function readLicenceTexts(dir = licencesDir) {
  const read = from => {
    const texts = new Map();
    if (!fs.existsSync(from)) return texts;
    for (const entry of fs.readdirSync(from, { withFileTypes: true })) {
      if (entry.isFile() && entry.name.endsWith('.txt')) {
        texts.set(entry.name.slice(0, -4), fs.readFileSync(path.join(from, entry.name), 'utf8').trimEnd());
      }
    }
    return texts;
  };
  return { byId: read(dir), byPackage: read(path.join(dir, 'packages')) };
}

/**
 * The licence texts `parts` need, each text once however many parts share it.
 *
 * @param {{name: string, licence: string, own?: boolean}[]} parts What declares a licence: a
 *     package, a crate, or something that is neither (the kernel, SeaBIOS). `own` allows a part
 *     to be answered by `packages/<name>.txt`, which is how a package that declares `custom`
 *     carries its licence at all.
 * @param {{byId: Map<string, string>, byPackage: Map<string, string>}} [texts]
 * @returns {{sections: {tokens: string[], note: string, text: string}[],
 *     missing: {token: string, copyleft: boolean, named: string[]}[], noText: string[]}}
 *     `sections` in identifier order, `missing` what nothing carries a text for, and `noText`
 *     the parts whose declaration is not a licence.
 */
export function licenceTexts(parts, texts = readLicenceTexts()) {
  const byText = new Map();
  const missing = new Map();
  const noText = [];
  const add = (token, note, text) => {
    const found = byText.get(text) ?? { tokens: [], note, text };
    if (!found.tokens.includes(token)) found.tokens.push(token);
    byText.set(text, found);
  };
  for (const part of parts) {
    for (const id of licenceIds(part.licence)) {
      const text = texts.byId.get(id);
      if (text) {
        add(id, '', text);
        continue;
      }
      const own = part.own ? texts.byPackage.get(part.name) : undefined;
      if (own) {
        add(part.name, `the package's own licence file; it declares ${JSON.stringify(part.licence)}`, own);
        continue;
      }
      if (NO_TEXT.has(id)) {
        noText.push(`${part.name} (${id})`);
        continue;
      }
      const seen = missing.get(id) ?? { token: id, copyleft: isCopyleft(id), named: [] };
      seen.named.push(part.name);
      missing.set(id, seen);
    }
  }
  const sections = [...byText.values()].sort((a, b) => (a.tokens[0] < b.tokens[0] ? -1 : 1));
  for (const section of sections) section.tokens.sort();
  return { sections, missing: [...missing.values()], noText };
}

/** The tokens NOTICES.txt carries a text for: SPDX identifiers, and package names. */
export function licenceTextsIn(notices) {
  const found = new Set();
  for (const line of notices.split('\n')) {
    if (line.startsWith(TEXT_MARK)) {
      // Everything from the first " (" is the note that says where the text came from.
      for (const token of line.slice(TEXT_MARK.length).replace(/\s+\(.*$/, '').split(',')) found.add(token.trim());
    }
  }
  return found;
}

/**
 * The copyleft licences NOTICES.txt names without carrying their text, by family, so that a text
 * for `GPL-2.0-or-later` answers a package under `GPL-2.0-only`. It reads the notices the way a
 * reader would: every copyleft identifier in the prose and the tables above the texts is one
 * whose text has to be below them.
 *
 * @returns {string[]} Empty when the bundle can be released.
 */
export function missingCopyleftTexts(notices) {
  const cut = notices.indexOf(`\n${TEXTS_HEADING}\n`);
  const named = cut === -1 ? notices : notices.slice(0, cut);
  const wanted = new Set([...named.matchAll(COPYLEFT_ID)].map(found => licenceFamily(found[0])));
  const carried = new Set([...licenceTextsIn(notices)].map(licenceFamily));
  return [...wanted].filter(family => !carried.has(family)).sort();
}
