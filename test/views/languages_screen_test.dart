import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:get_it/get_it.dart';
import 'package:i_can_code/l10n/generated/app_localizations.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/lessons/lesson.dart';
import 'package:i_can_code/services/progress/progress_store.dart';
import 'package:i_can_code/theme/theme.dart';
import 'package:i_can_code/views/languages_screen/languages_screen.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();

    GetIt.I
      ..registerSingleton<Course>(
        Course(
          lessons: [
            // Two, because a language with every lesson done shows a tick in
            // place of the count.
            for (final entry in Course.entriesFrom([
              'assets/lessons/python/01-hello.nl.md',
              'assets/lessons/python/02-again.nl.md',
            ]))
              CourseLesson(
                entry: entry,
                translations: {
                  'nl': Lesson(
                    id: entry.slug,
                    title: entry.slug,
                    sections: const [LessonSection(id: 'a', title: 'A', kind: SectionKind.info, prose: '')],
                  ),
                },
              ),
          ],
        ),
      )
      ..registerSingleton<ProgressStore>(ProgressStore());
  });

  tearDown(GetIt.I.reset);

  testWidgets('a language\'s count follows progress, a reset included', (tester) async {
    final progress = GetIt.I<ProgressStore>();
    await progress.markFinished(GetIt.I<Course>().lessons.first, 'a');

    await tester.pumpWidget(
      FTheme(
        data: buildAppTheme(),
        child: Localizations(
          locale: const Locale('nl'),
          delegates: AppLocalizations.localizationsDelegates,
          child: const Directionality(
            textDirection: TextDirection.ltr,
            child: MediaQuery(data: MediaQueryData(size: Size(1200, 900)), child: LanguagesScreen()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('1 / 2'), findsOneWidget);

    await progress.clear();
    await tester.pumpAndSettle();

    expect(find.textContaining('0 / 2'), findsOneWidget, reason: 'a reset has to reach the card');
  });
}
