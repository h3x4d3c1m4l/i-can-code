import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:get_it/get_it.dart';
import 'package:i_can_code/l10n/generated/app_localizations.dart';
import 'package:i_can_code/services/feature_toggles.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/lessons/lesson.dart';
import 'package:i_can_code/services/progress/code_draft_store.dart';
import 'package:i_can_code/services/progress/progress_store.dart';
import 'package:i_can_code/theme/theme.dart';
import 'package:i_can_code/views/catalog_screen/catalog_screen.dart';
import 'package:i_can_code/views/catalog_screen/components/anchor_target.dart';
import 'package:i_can_code/views/catalog_screen/components/catalog_anchor_scope.dart';
import 'package:i_can_code/views/catalog_screen/components/catalog_tile.dart';
import 'package:i_can_code/views/catalog_screen/components/sticky_group_heading.dart';
import 'package:i_can_code/views/components/app_header.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// Where a stuck heading's text sits: under the bar, past the sliver's own gap.
const double _pinned = AppHeader.height + StickyGroupHeading.topGap;

/// The catalog as the address `/learn-python?group=…&lesson=…` opens it. With
/// [navigator], under a real [Navigator], which a dialog needs.
Widget _catalog({String? group, String? lesson, bool lessMotion = false, bool navigator = false}) {
  final screen = CatalogScreen(subjectSlug: 'learn-python', group: group, lesson: lesson);

  return FTheme(
    data: buildAppTheme(),
    child: Localizations(
      locale: const Locale('nl'),
      delegates: AppLocalizations.localizationsDelegates,
      child: Directionality(
        textDirection: TextDirection.ltr,
        // The test surface's own size, so the gutters are worked out against the
        // width the page actually has.
        child: MediaQuery(
          data: MediaQueryData(size: const Size(800, 600), disableAnimations: lessMotion),
          // The router's navigator gives every screen an overlay, and the copy
          // menu opens in it.
          child: navigator
              ? Navigator(onGenerateRoute: (_) => PageRouteBuilder<void>(pageBuilder: (_, _, _) => screen))
              : Overlay.wrap(child: screen),
        ),
      ),
    ),
  );
}

/// Lets an address take effect: the frame that starts the scroll, the scroll,
/// and the first frames of the ring. Not `pumpAndSettle`, which would run the
/// ring out before anything could look at it.
Future<void> _arrive(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(AnchorTarget.scrollDuration);
  await tester.pump(const Duration(milliseconds: 100));
}

/// Whether the part of the catalog that shows [label] is lit. Wherever it
/// is: a part scrolled past is off stage, and still a part.
bool _lit(WidgetTester tester, String label) {
  final target = find
      .ancestor(of: find.text(label, skipOffstage: false), matching: find.byType(AnchorTarget, skipOffstage: false))
      .first;
  final ring = find.descendant(of: target, matching: find.byType(CustomPaint, skipOffstage: false)).first;

  return tester.widget<CustomPaint>(ring).foregroundPainter != null;
}

/// A point on [label]'s tile near its top. The title sits under a picture,
/// below where a test window ends.
Offset _onTile(WidgetTester tester, String label) =>
    tester.getTopLeft(find.ancestor(of: find.text(label), matching: find.byType(CatalogTile)).first) +
    const Offset(40, 40);

/// Past the end of a ring. An animation is done only once its time is over,
/// not as it runs out.
const Duration _over = Duration(milliseconds: 50);

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
            for (var order = 1; order <= 6; order++)
              CourseLesson(
                entry: LessonEntry(
                  subject: 'python',
                  group: order <= 3
                      ? const LessonGroup(id: 'week-1', titles: {'nl': 'Week 1'})
                      : const LessonGroup(id: 'week-2', titles: {'nl': 'Week 2'}),
                  order: order,
                  paths: const {'nl': 'x'},
                ),
                translations: {
                  'nl': Lesson(
                    // An id apiece: progress keys on it.
                    id: 'lesson-$order',
                    title: 'lesson-$order',
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
      ..registerSingleton<FeatureToggles>(FeatureToggles())
      ..registerSingleton<ProgressStore>(ProgressStore())
      ..registerSingleton<CodeDraftStore>(CodeDraftStore());
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

  testWidgets('a lesson or a week behind a feature toggle is listed once the toggle is on', (tester) async {
    CourseLesson lesson(int order, LessonGroup group, {String? feature}) => CourseLesson(
      entry: LessonEntry(subject: 'python', group: group, order: order, paths: const {'nl': 'x'}),
      translations: {
        'nl': Lesson(
          id: 'lesson-$order',
          title: 'lesson-$order',
          feature: feature,
          sections: const [LessonSection(id: 'a', title: 'A', kind: SectionKind.info, prose: '')],
        ),
      },
    );
    const week1 = LessonGroup(id: 'week-1', titles: {'nl': 'Week 1'});
    const week2 = LessonGroup(id: 'week-2', titles: {'nl': 'Week 2'}, feature: 'files');
    await GetIt.I.unregister<Course>();
    GetIt.I.registerSingleton<Course>(
      Course(lessons: [lesson(1, week1), lesson(2, week1, feature: 'csv'), lesson(3, week2)]),
    );
    final toggles = GetIt.I<FeatureToggles>();

    await tester.pumpWidget(_catalog());
    await tester.pumpAndSettle();

    expect(find.text('lesson-1', skipOffstage: false), findsOneWidget);
    expect(find.text('lesson-2', skipOffstage: false), findsNothing);
    expect(_heading('WEEK 2'), findsNothing, reason: 'a week whose toggle is off goes with its lessons');

    // Switched while the catalog is open, as the debug menu over it does.
    await toggles.set('csv', on: true);
    await toggles.set('files', on: true);
    await tester.pumpAndSettle();

    expect(find.text('lesson-2', skipOffstage: false), findsOneWidget);
    expect(_heading('WEEK 2'), findsOneWidget);
    expect(find.text('lesson-3', skipOffstage: false), findsOneWidget);
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

    // Past the cache extent a heading is laid out but not placed, so where it
    // reads on screen is stale. Bring week 2 into the window before reading it.
    _scroll(tester).jumpTo(_scroll(tester).pixels + 500);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(_heading('WEEK 1')).dy, closeTo(_pinned, 0.5), reason: 'week 1 is still passing');

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

  group('an address that names a place', () {
    testWidgets('brings a group\'s heading under the bar, and lights the heading and its cards', (tester) async {
      await tester.pumpWidget(_catalog(group: 'week-1'));
      await _arrive(tester);

      expect(tester.getTopLeft(_heading('WEEK 1')).dy, closeTo(_pinned, 0.5));
      expect(_surfaceOpacity(tester, 'WEEK 1'), 0, reason: 'it stands in its own spot, and is not held up there');

      expect(tester.hasRunningAnimations, isTrue, reason: 'the ring starts once the page has come to rest');
      for (final label in ['WEEK 1', 'lesson-1', 'lesson-2', 'lesson-3']) {
        expect(_lit(tester, label), isTrue, reason: label);
      }
      for (final label in ['WEEK 2', 'lesson-4']) {
        expect(_lit(tester, label), isFalse, reason: label);
      }

      await tester.pump(CatalogAnchorScope.ringDuration + _over);
      expect(tester.hasRunningAnimations, isFalse, reason: 'it lights up for a moment, not for good');
    });

    testWidgets('brings a lesson\'s tile to just under its group\'s stuck heading, and lights only that tile', (
      tester,
    ) async {
      // In the second row: a tile in the first comes to rest with its heading
      // where the list put it, which is the tile's clearance below the pin.
      await tester.pumpWidget(_catalog(lesson: 'lesson-3'));
      await _arrive(tester);

      final tile = find.ancestor(of: find.text('lesson-3'), matching: find.byType(AnchorTarget)).first;
      expect(
        tester.getTopLeft(tile).dy,
        greaterThan(tester.getTopLeft(find.ancestor(of: find.text('lesson-1'), matching: find.byType(AnchorTarget)).first).dy),
        reason: 'the lesson is in a lower row than the first',
      );
      expect(tester.getTopLeft(_heading('WEEK 1')).dy, closeTo(_pinned, 0.5), reason: 'the heading stuck on the way');
      final gap = tester.getTopLeft(tile).dy - tester.getBottomLeft(_heading('WEEK 1')).dy;
      expect(gap, greaterThan(0), reason: 'the tile is clear of the heading, not behind it');
      expect(gap, lessThan(80), reason: 'and right under it, not somewhere down the page');

      expect(_lit(tester, 'lesson-3'), isTrue);
      for (final label in ['WEEK 1', 'lesson-1', 'lesson-2']) {
        expect(_lit(tester, label), isFalse, reason: label);
      }
    });

    testWidgets('a lesson wins from a group, being the narrower of the two', (tester) async {
      await tester.pumpWidget(_catalog(group: 'week-1', lesson: 'lesson-5'));
      await _arrive(tester);

      expect(_lit(tester, 'lesson-5'), isTrue);
      expect(_lit(tester, 'WEEK 1'), isFalse);
    });

    testWidgets('an id the course does not have opens the catalog as it would without one', (tester) async {
      for (final catalog in [_catalog(), _catalog(group: 'week-9'), _catalog(lesson: 'gone')]) {
        await tester.pumpWidget(catalog);
        await _arrive(tester);

        expect(_scroll(tester).pixels, 0);
        expect(tester.hasRunningAnimations, isFalse);
      }
    });

    testWidgets('moves a catalog that is already open, which is what a pasted link meets', (tester) async {
      // auto_route hands a page that only changed its query new arguments,
      // rather than a new screen.
      await tester.pumpWidget(_catalog());
      await tester.pumpAndSettle();
      _scroll(tester).jumpTo(_scroll(tester).maxScrollExtent);
      await tester.pumpAndSettle();

      await tester.pumpWidget(_catalog(group: 'week-1'));
      await _arrive(tester);

      expect(tester.getTopLeft(_heading('WEEK 1')).dy, closeTo(_pinned, 0.5));
      expect(_lit(tester, 'WEEK 1'), isTrue);
    });

    testWidgets('leaves the page where it is when the address stops naming one', (tester) async {
      await tester.pumpWidget(_catalog(group: 'week-1'));
      await tester.pumpAndSettle();
      final rest = _scroll(tester).pixels;
      expect(rest, greaterThan(0));

      await tester.pumpWidget(_catalog());
      await tester.pumpAndSettle();

      expect(_scroll(tester).pixels, rest, reason: 'the reader moved on, and that is no request');
    });

    testWidgets('jumps there for a reader who asked for less motion, and still lights up', (tester) async {
      await tester.pumpWidget(_catalog(group: 'week-1', lessMotion: true));
      // The frame that jumps, and one for the ring. No time passes.
      await tester.pump();
      await tester.pump();

      expect(tester.getTopLeft(_heading('WEEK 1')).dy, closeTo(_pinned, 0.5));
      expect(_lit(tester, 'WEEK 1'), isTrue);
      expect(tester.hasRunningAnimations, isTrue, reason: 'the ring stands for a while, though nothing moves');

      await tester.pump(CatalogAnchorScope.reducedHold + _over);
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('a right click', () {
    late List<String> copied;

    setUp(() {
      copied = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
          return null;
        },
      );
    });

    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    testWidgets('on a card copies the address that opens the catalog at that lesson', (tester) async {
      await tester.pumpWidget(_catalog());
      await tester.pumpAndSettle();
      expect(find.text('Link kopiëren'), findsNothing);

      await tester.tapAt(_onTile(tester, 'lesson-2'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      final menu = tester.getSize(find.byType(FItem).first);

      await tester.tap(find.text('Link kopiëren'));
      await tester.pump();

      expect(copied.single, endsWith('#/learn-python?lesson=lesson-2'));
      expect(Uri.parse(copied.single).hasScheme, isTrue, reason: 'a whole address, to paste somewhere else');
      expect(find.text('Gekopieerd'), findsOneWidget, reason: 'a copy changes nothing else the reader can see');
      expect(tester.getSize(find.byType(FItem).first), menu, reason: 'the item says so without changing size');

      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.byType(FItem), findsNothing, reason: 'and the menu closes by itself');
    });

    testWidgets('on a group\'s heading copies the address of the group', (tester) async {
      await tester.pumpWidget(_catalog());
      await tester.pumpAndSettle();

      await tester.tap(_heading('WEEK 1'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Link kopiëren'));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(copied.single, endsWith('#/learn-python?group=week-1'));
    });

    testWidgets('opens the menu and leaves the lesson shut', (tester) async {
      await tester.pumpWidget(_catalog());
      await tester.pumpAndSettle();

      await tester.tapAt(_onTile(tester, 'lesson-1'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.byType(CatalogScreen), findsOneWidget);
      expect(find.byType(FItem), findsNWidgets(2), reason: 'copying the link, and starting the lesson over');
    });

    testWidgets('on a group\'s heading offers only the link', (tester) async {
      await tester.pumpWidget(_catalog());
      await tester.pumpAndSettle();

      await tester.tap(_heading('WEEK 1'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.text('Les opnieuw beginnen'), findsNothing);
    });

    testWidgets('greys out starting over a lesson that has nothing to forget', (tester) async {
      await tester.pumpWidget(_catalog());
      await tester.pumpAndSettle();

      await tester.tapAt(_onTile(tester, 'lesson-2'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(tester.widget<FItem>(find.widgetWithText(FItem, 'Les opnieuw beginnen')).enabled, isFalse);
    });

    testWidgets('starts a lesson over once asked, and only that lesson', (tester) async {
      final lessons = GetIt.I<Course>().lessons;
      final progress = GetIt.I<ProgressStore>();
      final drafts = GetIt.I<CodeDraftStore>();
      await progress.markFinished(lessons[0], 'a');
      await progress.markFinished(lessons[1], 'a');
      drafts.keep(lessons[0], 'b', 'print(1)');

      // showFDialog looks up a Navigator, which the router would give.
      await tester.pumpWidget(_catalog(navigator: true));
      await tester.pumpAndSettle();

      Future<void> askToRestart() async {
        await tester.tapAt(_onTile(tester, 'lesson-1'), buttons: kSecondaryButton);
        await tester.pumpAndSettle();
        expect(tester.widget<FItem>(find.widgetWithText(FItem, 'Les opnieuw beginnen')).enabled, isTrue);
        await tester.tap(find.text('Les opnieuw beginnen'));
        await tester.pumpAndSettle();
        expect(find.text('“lesson-1” opnieuw beginnen?'), findsOneWidget);
      }

      await askToRestart();
      await tester.tap(find.text('Annuleren'));
      await tester.pumpAndSettle();
      expect(progress.isStarted(lessons[0]), isTrue, reason: 'cancelling forgets nothing');

      await askToRestart();
      await tester.tap(find.text('Opnieuw beginnen'));
      await tester.pumpAndSettle();
      expect(progress.isStarted(lessons[0]), isFalse);
      expect(drafts.hasCodeIn(lessons[0]), isFalse);
      expect(progress.isStarted(lessons[1]), isTrue, reason: 'the lesson beside it keeps its tick');
      expect(find.textContaining('1 / 2'), findsOneWidget, reason: 'the card shows it at once');
    });

    testWidgets('has a way in from the keyboard, on the card that has the focus', (tester) async {
      await tester.pumpWidget(_catalog());
      await tester.pumpAndSettle();

      // Tab is the app shell's shortcut, and there is no shell here.
      Focus.of(tester.element(find.text('lesson-1'))).requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.f10);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();

      expect(find.text('Link kopiëren'), findsOneWidget);
    });

    testWidgets('has a way in for a screen reader, on the tile\'s own node', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_catalog());
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(find.byType(CatalogTile).first),
        isSemantics(
          isButton: true,
          customActions: [
            const CustomSemanticsAction(label: 'Link kopiëren'),
            const CustomSemanticsAction(label: 'Les opnieuw beginnen'),
          ],
        ),
      );
      handle.dispose();
    });
  });
}
