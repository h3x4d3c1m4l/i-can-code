import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_code/views/catalog_screen/lesson_runs.dart';

void main() {
  group('runsBy', () {
    test('gathers neighbours that share a key', () {
      final runs = runsBy(['a1', 'a2', 'b1'], (item) => item[0]);

      expect(runs.map((run) => run.key), ['a', 'b']);
      expect(runs.map((run) => run.items), [
        ['a1', 'a2'],
        ['b1'],
      ]);
    });

    test('never reorders: a key that comes back opens a run of its own', () {
      // The filename's number is the only source of lesson order, so a group
      // that recurs later gets a second heading rather than pulling its
      // lessons forward past the ones in between.
      final runs = runsBy(['a1', 'b1', 'a2'], (item) => item[0]);

      expect(runs.map((run) => run.key), ['a', 'b', 'a']);
    });

    test('lessons without a group form a run with no key', () {
      final runs = runsBy<String, String?>(['x', 'y', 'a1'], (item) => item.startsWith('a') ? 'a' : null);

      expect(runs.map((run) => run.key), [null, 'a']);
      expect(runs.first.items, ['x', 'y']);
    });

    test('nothing in, nothing out', () {
      expect(runsBy(<String>[], (item) => item), isEmpty);
    });
  });
}
