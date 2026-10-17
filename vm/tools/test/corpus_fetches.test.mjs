// update-image.sh's report of corpus cases that fetch more on a new image than on the old one.

import assert from 'node:assert/strict';
import { test } from 'node:test';

import { fetchIncreases } from '../lib/corpus-fetches.mjs';

test('a case that fetches more, or one the earlier report does not name, is listed with the files that are new', () => {
  const before = {
    results: [
      { name: 'traceback', fetches: 0, fetched: [] },
      { name: 'cold', fetches: 2, fetched: ['/usr/lib/python3.12/__pycache__/enum.cpython-312.pyc', '/etc/fonts/fonts.conf'] },
      { name: 'label', fetches: 1, fetched: ['/etc/fonts/fonts.conf'] },
      { name: 'gone', fetches: 0, fetched: [] },
    ],
  };
  const after = {
    results: [
      { name: 'traceback', fetches: 2, fetched: ['/usr/lib/python3.14/__pycache__/traceback.cpython-314.pyc', '/usr/lib/python3.14/__pycache__/_colorize.cpython-314.pyc'] },
      { name: 'cold', fetches: 3, fetched: ['/usr/lib/python3.14/__pycache__/enum.cpython-314.pyc', '/etc/fonts/fonts.conf', '/usr/share/X11/Xcms.txt'] },
      { name: 'label', fetches: 0, fetched: [] },
      { name: 'new-case', fetches: 5, fetched: ['/usr/share/X11/locale/locale.dir'] },
      { name: 'new-and-quiet', fetches: 0, fetched: [] },
    ],
  };
  assert.deepEqual(fetchIncreases(before, after), [
    { name: 'traceback', before: 0, after: 2, added: ['/usr/lib/python3.14/__pycache__/traceback.cpython-314.pyc', '/usr/lib/python3.14/__pycache__/_colorize.cpython-314.pyc'] },
    { name: 'cold', before: 2, after: 3, added: ['/usr/share/X11/Xcms.txt'] },
    { name: 'new-case', before: null, after: 5, added: ['/usr/share/X11/locale/locale.dir'] },
  ]);
});
