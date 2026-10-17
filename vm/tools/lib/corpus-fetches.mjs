// What a new image makes the corpus fetch that the old one did not. Every case can pass while a
// module the warm interpreter used to hold is now a fetch over the network, which is slow in a
// page and wrong nowhere, so no check fails on it. update-image.sh prints this after the corpus.

/**
 * The corpus cases whose rootfs fetches rose from report `before` to report `after`, both as
 * corpus.mjs writes them, with the files the new image fetched that the old one did not.
 * Paths are compared with the Python version taken out, so python3.12 and python3.14 match.
 *
 * A case the BEFORE report does not name is reported with `before: null` whenever it fetched
 * anything: it was added in the same round as the image change, and it is the round's own new
 * case that is most likely to fetch something nothing warms.
 *
 * @returns {{name: string, before: number | null, after: number, added: string[]}[]}
 */
export function fetchIncreases(before, after) {
  const unversioned = file => file.replace(/python3\.\d+/g, 'python3.X').replace(/cpython-3\d+/g, 'cpython-3X');
  const old = new Map(before.results.map(result => [result.name, result]));
  const rises = [];
  for (const result of after.results) {
    const previous = old.get(result.name);
    const was = previous ? previous.fetches ?? 0 : null;
    const now = result.fetches ?? 0;
    if (was === null ? now === 0 : now <= was) continue;
    const seen = new Set((previous?.fetched ?? []).map(unversioned));
    rises.push({ name: result.name, before: was, after: now, added: (result.fetched ?? []).filter(file => !seen.has(unversioned(file))) });
  }
  return rises;
}
