import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_code/services/folder_store.dart';

void main() {
  late FolderStore folder;

  setUp(() => folder = FolderStore());

  String textOf(String path, {String subject = 'python'}) => utf8.decode(folder.filesOf(subject)[path]!);

  test('keeps a folder per subject, in the order the files arrived', () {
    folder
      ..put('python', 'b.csv', utf8.encode('b'))
      ..put('python', 'a.csv', utf8.encode('a'))
      ..put('csharp', 'c.txt', utf8.encode('c'));

    expect(folder.filesOf('python').keys, ['b.csv', 'a.csv']);
    expect(folder.filesOf('csharp').keys, ['c.txt']);
    expect(folder.filesOf('rust'), isEmpty);
  });

  test('a file that is replaced keeps its place', () {
    folder
      ..put('python', 'a.csv', utf8.encode('1'))
      ..put('python', 'b.csv', utf8.encode('2'))
      ..put('python', 'a.csv', utf8.encode('3'));

    expect(folder.filesOf('python').keys, ['a.csv', 'b.csv']);
    expect(textOf('a.csv'), '3');
  });

  test('what the interpreter reports is applied in one go', () {
    folder
      ..put('python', 'in.csv', utf8.encode('x'))
      ..put('python', 'weg.csv', utf8.encode('y'))
      ..apply('python', changed: {'uit.csv': utf8.encode('z'), 'in.csv': utf8.encode('x2')}, removed: ['weg.csv']);

    expect(folder.filesOf('python').keys, ['in.csv', 'uit.csv']);
    expect(textOf('in.csv'), 'x2');
  });

  group('a name for a typed file', () {
    test('is refused when empty, with a slash, too long or taken', () {
      folder.put('python', 'cijfers.csv', utf8.encode(''));

      expect(folder.problemWith('python', '  '), FolderNameProblem.empty);
      expect(folder.problemWith('python', 'data/x.csv'), FolderNameProblem.slash);
      expect(folder.problemWith('python', r'data\x.csv'), FolderNameProblem.slash);
      expect(folder.problemWith('python', 'x' * (FolderStoreBase.maxNameLength + 1)), FolderNameProblem.tooLong);
      expect(folder.problemWith('python', 'cijfers.csv'), FolderNameProblem.taken);
      expect(folder.problemWith('python', 'nieuw.csv'), isNull);
    });

    test('may not be one the interpreter keeps for itself', () {
      for (final name in [...kReservedFolderNames, '.', '..']) {
        expect(folder.problemWith('python', name), FolderNameProblem.reserved, reason: name);
      }
    });

    test('may stay what it is, even where a new file could not have it', () {
      // A program may write into a directory, which a typed name cannot.
      folder.put('python', 'uit/x.csv', utf8.encode(''));

      expect(folder.problemWith('python', 'uit/x.csv', current: 'uit/x.csv'), isNull);
      expect(folder.problemWith('python', 'uit/y.csv', current: 'uit/x.csv'), FolderNameProblem.slash);
    });
  });
}
