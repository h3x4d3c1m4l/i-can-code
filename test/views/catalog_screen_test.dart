import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:get_it/get_it.dart';
import 'package:i_can_code/l10n/generated/app_localizations.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/lessons/lesson.dart';
import 'package:i_can_code/services/progress/progress_store.dart';
import 'package:i_can_code/theme/theme.dart';
import 'package:i_can_code/views/catalog_screen/catalog_screen.dart';
import 'package:i_can_code/views/catalog_screen/components/sticky_group_heading.dart';
import 'package:i_can_code/views/components/app_header.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// Where a stuck heading's text sits: under the bar, past the sliver's own gap.
const double _pinned = AppHeader.height + StickyGroupHeading.topGap;

Widget _catalog() => FTheme(
  data: buildAppTheme(),
  child: Localizations(
    locale: const Locale('nl'),
    delegates: AppLocalizations.localizationsDelegates,
    child: const Directionality(
      textDirection: TextDirection.ltr,
      // The test surface's own size, so the gutters are worked out against the
      // width the page actually has.
      child: MediaQuery(
        data: MediaQueryData(size: Size(800, 600)),
        child: CatalogScreen(subjectSlug: 'learn-python'),
      ),
    ),
  ),
);

ScrollPosition _scroll(WidgetTester tester) => tester
    .state<ScrollableState>(find.descendant(of: find.byType(CustomScrollView), matching: find.byType(Scrollable)))
    .position;

/// The heading's text, wherever it is. A heading pushed off is still laid out.
Finder _heading(String label) => find.text(label, skipOffstage: false);

double _surfaceOpacity(WidgetTester tester, String label) => tester
    .widget<AnimatedOpacity>(
      find.descendant(of: find.widgetWithText(StickyGroupHeading, label), matching: find.byType(AnimatedOpacity)),
    )
    .opacity;

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();

    GetIt.I
      ..registerSingleton<Course>(
        Course(
          lessons: [
            // Two weeks of three, so each week's cards are taller than the
            // distance the tests scroll into it.
            for (final (index, entry) in Course.entriesFrom([
              // A slug apiece: progress keys on the lesson's id.
              for (var order = 1; order <= 6; order++) 'assets/lessons/python/0$order-lesson-$order.nl.md',
            ]).indexed)
              CourseLesson(
                entry: entry,
                translations: {
                  'nl': Lesson(
                    id: entry.slug,
                    title: entry.slug,
                    group: index < 3 ? 'Week 1' : 'Week 2',
                    sections: const [
                      LessonSection(id: 'a', title: 'A', kind: SectionKind.info, prose: ''),
                      LessonSection(id: 'b', title: 'B', kind: SectionKind.info, prose: ''),
                    ],
                  ),
                },
              ),
          ],
        ),
      )
      ..registerSingleton<ProgressStore>(ProgressStore());
  });

  tearDown(GetIt.I.reset);

  testWidgets('a lesson\'s count follows progress, a reset included', (tester) async {
    final progress = GetIt.I<ProgressStore>();
    await progress.markFinished(GetIt.I<Course>().lessons.first, 'a');

    await tester.pumpWidget(_catalog());
    await tester.pumpAndSettle();
    expect(find.textContaining('1 / 2'), findsOneWidget);

    await progress.clear();
    await tester.pumpAndSettle();

    // The rows are built during layout, where the screen's own build is no
    // longer listening.
    expect(find.textContaining('1 / 2'), findsNothing, reason: 'a reset has to reach the card');
  });

  testWidgets('a week\'s heading sticks under the bar while its lessons pass, then gives way', (tester) async {
    await tester.pumpWidget(_catalog());
    await tester.pumpAndSettle();

    final week1 = tester.getTopLeft(_heading('WEEK 1')).dy;
    expect(week1, greaterThan(_pinned), reason: 'it starts where the list put it');
    expect(_surfaceOpacity(tester, 'WEEK 1'), 0, reason: 'and as plain text, not as a label');

    // Its own spot is now 100px behind the bar.
    _scroll(tester).jumpTo(week1 - _pinned + 100);
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(_heading('WEEK 1')).dy, closeTo(_pinned, 0.5));
    expect(_surfaceOpacity(tester, 'WEEK 1'), 1, reason: 'stuck, it floats as a label of its own');

    final week2 = tester.getTopLeft(_heading('WEEK 2')).dy;
    _scroll(tester).jumpTo(_scroll(tester).pixels + week2 - _pinned + 100);
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(_heading('WEEK 2')).dy, closeTo(_pinned, 0.5));
    expect(
      tester.getBottomLeft(_heading('WEEK 1')).dy,
      lessThan(AppHeader.height),
      reason: 'the end of its week pushed it off, rather than the two stacking',
    );
  });
}
