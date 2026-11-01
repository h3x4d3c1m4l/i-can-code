import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:get_it/get_it.dart';
import 'package:i_can_code/l10n/generated/app_localizations.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/lessons/lesson.dart';
import 'package:i_can_code/services/progress/progress_file.dart';
import 'package:i_can_code/services/progress/progress_store.dart';
import 'package:i_can_code/theme/theme.dart';
import 'package:i_can_code/views/components/progress_transfer.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

CourseLesson _lesson(String id) => CourseLesson(
  entry: const LessonEntry(subject: 'python', order: 1, paths: {'nl': 'x'}),
  translations: {
    'nl': Lesson(
      id: id,
      title: 'T',
      sections: [
        for (final sectionId in ['a', 'b'])
          LessonSection(id: sectionId, title: sectionId, kind: SectionKind.info, prose: ''),
      ],
    ),
  },
);

/// A progress file in which [done] are the finished steps, by lesson id.
String _file(Map<String, List<String>> done) => jsonEncode({
  'format': ProgressFile.format,
  'version': 1,
  'lessons': [
    for (final MapEntry(key: id, value: steps) in done.entries)
      {
        'id': id,
        'steps': [for (final step in steps) {'id': step, 'done': true}],
      },
  ],
});

/// Pumps an empty page and returns a context below its Navigator, which is
/// where `OverlayHost` puts every screen.
Future<BuildContext> _page(WidgetTester tester) async {
  late BuildContext page;
  await tester.pumpWidget(
    FTheme(
      data: buildAppTheme(),
      child: Localizations(
        locale: const Locale('nl'),
        delegates: AppLocalizations.localizationsDelegates,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: const MediaQueryData(size: Size(1024, 800)),
            child: Navigator(
              onGenerateRoute: (_) => PageRouteBuilder<void>(
                pageBuilder: (_, _, _) => Builder(
                  builder: (context) {
                    page = context;
                    return const SizedBox.expand();
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return page;
}

void main() {
  final intro = _lesson('intro');
  final loops = _lesson('loops');
  late ProgressStore progress;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    progress = ProgressStore();
    GetIt.I
      ..registerSingleton<Course>(Course(lessons: [intro, loops]))
      ..registerSingleton<ProgressStore>(progress);
  });

  tearDown(GetIt.I.reset);

  /// Starts an import of [file] and lets it settle on its first dialog.
  Future<void> import(WidgetTester tester, Future<String?> Function() file) async {
    final page = await _page(tester);
    unawaited(ProgressTransfer.importFile(page, open: file));
    await tester.pumpAndSettle();
  }

  testWidgets('with nothing here, a file comes in without a question', (tester) async {
    await import(
      tester,
      () async => _file({
        'python/intro': ['a', 'b'],
      }),
    );

    expect(find.text('Samenvoegen of vervangen?'), findsNothing);
    expect(find.text('Voortgang geïmporteerd'), findsOneWidget);
    expect(find.text('2 afgeronde stappen uit 1 les.'), findsOneWidget);
    expect(progress.finishedIn(intro), {'a', 'b'});
  });

  group('with progress here', () {
    setUp(() async => progress.markFinished(loops, 'a'));

    Future<void> importAndAnswer(WidgetTester tester, String answer) async {
      await import(
        tester,
        () async => _file({
          'python/intro': ['a'],
        }),
      );
      expect(find.text('Samenvoegen of vervangen?'), findsOneWidget);

      await tester.tap(find.text(answer));
      await tester.pumpAndSettle();
    }

    testWidgets('merging keeps what was here', (tester) async {
      await importAndAnswer(tester, 'Samenvoegen');

      expect(progress.finishedIn(intro), {'a'});
      expect(progress.finishedIn(loops), {'a'});
      expect(find.text('Voortgang geïmporteerd'), findsOneWidget);
    });

    testWidgets('replacing keeps only the file', (tester) async {
      await importAndAnswer(tester, 'Vervangen');

      expect(progress.finishedIn(intro), {'a'});
      expect(progress.isStarted(loops), isFalse);
    });

    testWidgets('cancelling changes nothing and says nothing more', (tester) async {
      await importAndAnswer(tester, 'Annuleren');

      expect(progress.isStarted(intro), isFalse);
      expect(progress.finishedIn(loops), {'a'});
      expect(find.text('Voortgang geïmporteerd'), findsNothing);
    });

    testWidgets('a damaged file changes nothing and says so', (tester) async {
      await import(tester, () async => jsonEncode({'format': ProgressFile.format, 'version': 1}));

      expect(find.text('Dit bestand kan niet worden geïmporteerd'), findsOneWidget);
      expect(find.text('Er klopt iets niet in dit voortgangsbestand. Er is niets veranderd.'), findsOneWidget);
      expect(progress.finishedIn(loops), {'a'});
    });
  });

  testWidgets('steps the course does not have are counted, beside what came in', (tester) async {
    await import(
      tester,
      () async => _file({
        'python/intro': ['a', 'gone'],
        'python/renamed': ['a'],
      }),
    );

    expect(
      find.text(
        '1 afgeronde stap uit 1 les. 2 stappen uit het bestand zijn overgeslagen, '
        'omdat deze versie van de app ze niet heeft.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a file of steps the course does not have imports nothing', (tester) async {
    await import(
      tester,
      () async => _file({
        'python/renamed': ['a'],
      }),
    );

    expect(find.text('Niets om te importeren'), findsOneWidget);
    expect(progress.hasProgress, isFalse);
  });

  testWidgets('a file that cannot be read as text is not a progress file', (tester) async {
    await import(tester, () async => throw const FormatException('Larger than 1048576 bytes'));

    expect(find.textContaining('Dit is geen voortgangsbestand'), findsOneWidget);
  });

  testWidgets('a cancelled pick says nothing', (tester) async {
    await import(tester, () async => null);

    expect(find.byType(FDialog), findsNothing);
  });
}
