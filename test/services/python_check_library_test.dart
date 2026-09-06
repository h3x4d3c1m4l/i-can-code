import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_code/extensions/app_localizations_extension.dart';
import 'package:i_can_code/l10n/generated/app_localizations_en.dart';
import 'package:i_can_code/l10n/generated/app_localizations_nl.dart';
import 'package:i_can_code/services/python/python_check_library.dart';

/// Runs [expression] against the check library in whatever CPython is on this
/// machine, and reads the answer back as JSON.
///
/// The library is a plain module, so it can be asked about itself without the
/// wrapper program or a browser around it.
Object? _ask(String expression) {
  // Carried as base64 for the reason `buildProgram` does it: the source cannot
  // terminate the literal holding it.
  final payload = base64.encode(utf8.encode(kCheckLibrary));
  final program = '''
import base64, json
_lib = {}
exec(compile(base64.b64decode("$payload").decode("utf-8"), "checks.py", "exec"), _lib)
print(json.dumps($expression))
''';
  final run = Process.runSync('python3', ['-c', program]);

  if (run.exitCode != 0) {
    fail('Could not ask the check library about itself:\n${run.stderr}');
  }
  return jsonDecode('${run.stdout}');
}

bool get _hasPython3 {
  try {
    return Process.runSync('python3', ['--version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

void main() {
  group('the check library', () {
    test('names the same unphrased constructs the app has strings for', () {
      // The one coupling between a Python dict and a Dart switch. Left to drift,
      // a new construct would reach a student as a bare English word in a Dutch
      // sentence — which is the whole thing the translation is there to prevent.
      final phrased = (_ask('sorted(_lib["_PHRASES"])')! as List).cast<String>();

      expect(phrased.toSet(), kPhrasedConstructs);
    });

    test('everything else it can refuse is a real Python keyword', () {
      // What makes leaving them untranslated correct: a keyword is the same word
      // in every language, so it is set as code rather than said.
      final unphrased = (_ask(
        'sorted(set(_lib["Program"]._CONSTRUCTS) - set(_lib["_PHRASES"]))',
      )! as List).cast<String>();
      final notKeywords = (_ask(
        'sorted(c for c in set(_lib["Program"]._CONSTRUCTS) - set(_lib["_PHRASES"]) '
        'if not _lib["_is_keyword"](c))',
      )! as List).cast<String>();

      expect(unphrased, isNotEmpty);
      expect(notKeywords, isEmpty, reason: 'these need a phrase and a translation');
    });

    test('every group it offers stands for constructs it knows', () {
      final unknown = (_ask(
        'sorted(n for names in _lib["Program"]._GROUPS.values() for n in names '
        'if n not in _lib["Program"]._CONSTRUCTS)',
      )! as List).cast<String>();

      expect(unknown, isEmpty);
    });
  }, skip: _hasPython3 ? false : 'python3 is not on PATH');

  group('the refusal a student reads', () {
    test('sets a keyword as code and leaves it untranslated', () {
      expect(AppLocalizationsNl().checkNotAllowed('if'), contains('`if`'));
      expect(AppLocalizationsEn().checkNotAllowed('if'), contains('`if`'));
    });

    test('says a construct with no keyword in the reader\'s language', () {
      final dutch = AppLocalizationsNl().checkNotAllowed('assignment');
      final english = AppLocalizationsEn().checkNotAllowed('assignment');

      expect(dutch, contains('geen toewijzing'));
      expect(dutch, isNot(contains('assignment')));
      expect(english, contains('an assignment'));
      expect(dutch, isNot(english));
    });

    test('phrases every construct it claims to phrase, in both languages', () {
      for (final locale in [AppLocalizationsNl(), AppLocalizationsEn()]) {
        for (final construct in kPhrasedConstructs) {
          expect(
            locale.checkNotAllowed(construct),
            isNot(contains('`')),
            reason: '$construct fell through to the code-span fallback',
          );
        }
      }
    });

    test('a construct this build has no phrase for degrades instead of throwing', () {
      expect(AppLocalizationsNl().checkNotAllowed('walrus'), contains('`walrus`'));
    });
  });
}
