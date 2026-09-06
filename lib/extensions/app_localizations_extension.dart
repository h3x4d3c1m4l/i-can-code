import 'package:i_can_code/l10n/generated/app_localizations.dart';

/// The constructs `kCheckLibrary` has no Python keyword to quote for.
///
/// Everything else it can refuse is a keyword — `if`, `for`, `def` — which is
/// the same word in every language and is therefore set as code rather than
/// translated. `test/services/python_check_library_test.dart` holds this against
/// the library's own `_PHRASES`, so the two cannot drift apart unnoticed.
const Set<String> kPhrasedConstructs = {
  'call',
  'assignment',
  'expression',
  'comprehension',
  'f-string',
  'type-alias',
};

extension AppLocalizationsExtension on AppLocalizations {

  /// What a step says when its `allow_only` or `disallow` refused something and
  /// the lesson author wrote no message of their own.
  ///
  /// [construct] is a name out of the check library — `if`, `assignment` — never
  /// a finished sentence, which is what lets it be said in the reader's own
  /// language. A name this build has no phrase for is set as code: right for a
  /// keyword, and merely plain for anything else, so a library that grows a
  /// construct degrades instead of throwing.
  String checkNotAllowed(String construct) =>
      lessonScreen_checkNotAllowed(_constructPhrase(construct) ?? '`$construct`');

  String? _constructPhrase(String construct) => switch (construct) {
    'call' => lessonScreen_constructCall,
    'assignment' => lessonScreen_constructAssignment,
    'expression' => lessonScreen_constructExpression,
    'comprehension' => lessonScreen_constructComprehension,
    'f-string' => lessonScreen_constructFString,
    'type-alias' => lessonScreen_constructTypeAlias,
    _ => null,
  };

}
