import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_confetti/flutter_confetti.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/l10n/generated/app_localizations.dart';
import 'package:i_can_code/services/lessons/lesson.dart';
import 'package:i_can_code/services/python/python_attempt_runner.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/theme.dart';
import 'package:i_can_code/views/components/app_button.dart';
import 'package:i_can_code/views/components/app_button_row.dart';
import 'package:i_can_code/views/components/catalog_card.dart';
import 'package:i_can_code/views/lesson_screen/components/code_editor_card.dart';
import 'package:i_can_code/views/lesson_screen/components/collapsible_prose_group.dart';
import 'package:i_can_code/views/lesson_screen/components/confetti_burst.dart';
import 'package:i_can_code/views/lesson_screen/components/lesson_complete_panel.dart';
import 'package:i_can_code/views/lesson_screen/components/lesson_prose.dart';
import 'package:i_can_code/views/lesson_screen/components/optional_step_banner.dart';
import 'package:i_can_code/views/lesson_screen/components/output_panel.dart';
import 'package:i_can_code/views/lesson_screen/components/pair_match_board.dart';
import 'package:i_can_code/views/lesson_screen/components/section_heading.dart';
import 'package:i_can_code/views/lesson_screen/components/step_progress_bar.dart';
import 'package:i_can_code/views/lesson_screen/components/step_transition.dart';
import 'package:re_editor/re_editor.dart';

/// Wraps [child] in what the lesson widgets need: the app theme, the
/// localizations, and the scroll view they always sit inside — prose is taller
/// than the viewport, and without one the Column overflows.
Widget _host(Widget child) => FTheme(
  data: buildAppTheme(),
  child: Localizations(
    locale: const Locale('nl'),
    delegates: AppLocalizations.localizationsDelegates,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(size: Size(1200, 800)),
        child: Align(
          child: SizedBox(
            width: 700,
            child: SingleChildScrollView(child: child),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  late Lesson lesson;

  setUpAll(() {
    lesson = Lesson.parse(File('assets/lessons/python/01-input-and-output.nl.md').readAsStringSync());
  });

  group('splitProseOnSubheadings', () {
    test('returns one headless group when there is no subheading', () {
      final groups = splitProseOnSubheadings('Alleen tekst.\n\nEn nog een alinea.');

      expect(groups, hasLength(1));
      expect(groups.single.heading, isNull);
      expect(groups.single.body, 'Alleen tekst.\n\nEn nog een alinea.');
    });

    test('keeps the prose before the first subheading as a headless group', () {
      final groups = splitProseOnSubheadings('Intro.\n\n### Een\n\nInhoud.');

      expect(groups.map((g) => g.heading), [null, 'Een']);
      expect(groups.first.body, 'Intro.');
      expect(groups.last.body, 'Inhoud.');
    });

    test('drops an empty preamble rather than rendering nothing', () {
      final groups = splitProseOnSubheadings('### Een\n\nInhoud.');

      expect(groups.map((g) => g.heading), ['Een']);
    });

    test('a `###` line inside a fence is code, not a heading', () {
      final groups = splitProseOnSubheadings('### Kop\n\n```python\n### niet een kop\n```\n\nNa.');

      expect(groups, hasLength(1));
      expect(groups.single.heading, 'Kop');
      expect(groups.single.body, contains('### niet een kop'));
    });

    test('a heading ending in {collapsed} asks to start folded', () {
      final groups = splitProseOnSubheadings('### Een {collapsed}\n\nInhoud.');

      expect(groups.single.heading, 'Een');
      expect(groups.single.collapsed, isTrue);
    });

    test('a heading without the marker starts open', () {
      final groups = splitProseOnSubheadings('### Een\n\nInhoud.');

      expect(groups.single.collapsed, isFalse);
    });

    test('the marker only counts at the end of the heading', () {
      final groups = splitProseOnSubheadings('### Over {collapsed} als markering\n\nInhoud.');

      expect(groups.single.heading, 'Over {collapsed} als markering');
      expect(groups.single.collapsed, isFalse);
    });

    test('a deeper heading is left to the renderer', () {
      final groups = splitProseOnSubheadings('#### Vier\n\nInhoud.');

      expect(groups, hasLength(1));
      expect(groups.single.heading, isNull);
    });
  });

  group('LessonProse', () {
    testWidgets('renders every shipped section without throwing', (tester) async {
      for (final section in lesson.sections) {
        await tester.pumpWidget(_host(LessonProse(markdown: section.prose)));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: section.title);
      }
    });

    testWidgets('shows the prose but never the hidden blocks', (tester) async {
      await tester.pumpWidget(_host(LessonProse(markdown: lesson.sections.first.prose)));
      await tester.pumpAndSettle();

      expect(find.textContaining('Welkom bij de eerste module'), findsOneWidget);
      expect(find.textContaining('metadata'), findsNothing);
      expect(find.textContaining('raise Exception'), findsNothing);
    });

    testWidgets('keeps a worked example as a code block', (tester) async {
      await tester.pumpWidget(_host(LessonProse(markdown: lesson.sections.first.prose)));
      await tester.pumpAndSettle();

      expect(find.textContaining('print("Hello, world")'), findsOneWidget);
    });

    testWidgets('a code block is spaced evenly above and below', (tester) async {
      await tester.pumpWidget(
        _host(const LessonProse(markdown: 'Voor.\n\n```python\nprint("x")\n```\n\nNa.')),
      );
      await tester.pumpAndSettle();

      final code = find.textContaining('print("x")');
      final card = tester.getRect(find.ancestor(of: code, matching: find.byType(DecoratedBox)).first);
      final above = tester.getRect(find.textContaining('Voor.'));
      final below = tester.getRect(find.textContaining('Na.'));
      final inside = tester.getRect(code);

      // 6 paragraph spacing + 20 sheet blockSpacing + 8 of the block's own.
      // A paragraph carries its spacing below itself, so without the builder's
      // trailing space the gap under a block would be 8px against 26 above.
      expect(card.top - above.bottom, 34);
      expect(below.top - card.bottom, 34);
      // The card's own padding. Its top gap is larger because the language
      // label sits above the code inside the card.
      expect(card.bottom - inside.bottom, CodeEditorCard.codePadding.bottom);
    });

    testWidgets('a subheading becomes a group that starts open', (tester) async {
      await tester.pumpWidget(_host(const LessonProse(markdown: 'Intro.\n\n### Kop\n\nInhoud.')));
      await tester.pumpAndSettle();

      expect(find.byType(CollapsibleProseGroup), findsOneWidget);
      expect(find.textContaining('Inhoud.'), findsOneWidget);
      // The prose before the first `###` stays outside the group.
      expect(find.textContaining('Intro.'), findsOneWidget);
    });

    testWidgets('pressing a subheading folds its prose away, and again unfolds it', (tester) async {
      await tester.pumpWidget(_host(const LessonProse(markdown: '### Kop\n\nInhoud.')));
      await tester.pumpAndSettle();

      final group = find.byType(CollapsibleProseGroup);
      final open = tester.getSize(group).height;
      final heading = tester.getSize(find.text('Kop')).height;

      await tester.tap(find.text('Kop'));
      await tester.pumpAndSettle();

      final folded = tester.getSize(group).height;
      expect(folded, lessThan(open));
      // Nothing of the prose is left standing: only the heading remains.
      expect(folded, lessThanOrEqualTo(heading + 8));

      await tester.tap(find.text('Kop'));
      await tester.pumpAndSettle();

      expect(tester.getSize(group).height, open);
    });

    testWidgets('with a hanging gutter every line of prose shares one left edge', (tester) async {
      await tester.pumpWidget(
        _host(const LessonProse(markdown: 'Intro.\n\n### Kop\n\nInhoud.', hangingGutter: true)),
      );
      await tester.pumpAndSettle();

      final intro = tester.getRect(find.textContaining('Intro.'));
      final heading = tester.getRect(find.text('Kop'));
      final content = tester.getRect(find.textContaining('Inhoud.'));
      final chevron = tester.getRect(find.byIcon(FLucideIcons.chevronDown));

      expect(heading.left, intro.left);
      expect(content.left, intro.left);
      // The chevron sits in the gutter the prose is indented by, not outside it.
      expect(chevron.right, lessThanOrEqualTo(heading.left));
      expect(heading.left - CollapsibleProseGroup.gutter, lessThanOrEqualTo(chevron.left));
    });

    testWidgets('the chevron itself is pressable, not just the heading', (tester) async {
      await tester.pumpWidget(
        _host(const LessonProse(markdown: '### Kop\n\nInhoud.', hangingGutter: true)),
      );
      await tester.pumpAndSettle();

      final group = find.byType(CollapsibleProseGroup);
      final open = tester.getSize(group).height;

      await tester.tapAt(tester.getCenter(find.byIcon(FLucideIcons.chevronDown)));
      await tester.pumpAndSettle();

      expect(tester.getSize(group).height, lessThan(open));
    });

    testWidgets('a heading marked {collapsed} arrives folded, without animating open', (tester) async {
      await tester.pumpWidget(
        _host(const LessonProse(markdown: '### Kop {collapsed}\n\nInhoud.', hangingGutter: true)),
      );
      await tester.pump();

      final group = find.byType(CollapsibleProseGroup);
      final folded = tester.getSize(group).height;
      // The marker is a directive, not part of the title.
      expect(find.text('Kop'), findsOneWidget);

      await tester.pumpAndSettle();
      expect(tester.getSize(group).height, folded);

      await tester.tap(find.text('Kop'));
      await tester.pumpAndSettle();
      expect(tester.getSize(group).height, greaterThan(folded));
    });

    testWidgets('a step without subheadings builds no group at all', (tester) async {
      await tester.pumpWidget(_host(const LessonProse(markdown: 'Alleen tekst.')));
      await tester.pumpAndSettle();

      expect(find.byType(CollapsibleProseGroup), findsNothing);
    });

    testWidgets('a code block names its language in the corner', (tester) async {
      await tester.pumpWidget(
        _host(const LessonProse(markdown: '```python\nprint("x")\n```')),
      );
      await tester.pumpAndSettle();

      expect(find.text('python'), findsOneWidget);

      // Right-aligned, like the editor card's runtime label.
      final card = tester.getRect(
        find.ancestor(of: find.textContaining('print("x")'), matching: find.byType(DecoratedBox)).first,
      );
      final label = tester.getRect(find.text('python'));
      expect(
        card.right - label.right,
        CodeEditorCard.headerPadding.right,
        reason: 'a worked example and the editor indent identically',
      );
    });

    testWidgets('a block with no language has no label', (tester) async {
      await tester.pumpWidget(_host(const LessonProse(markdown: '```\nplain text\n```')));
      await tester.pumpAndSettle();

      final card = tester.getRect(
        find.ancestor(of: find.textContaining('plain text'), matching: find.byType(DecoratedBox)).first,
      );
      final code = tester.getRect(find.textContaining('plain text'));

      expect(
        code.top - card.top,
        CodeEditorCard.headerPadding.top,
        reason: 'without a label the code takes the header inset in its place',
      );
    });

    testWidgets('a python block is syntax highlighted', (tester) async {
      await tester.pumpWidget(_host(LessonProse(markdown: lesson.sections.first.prose)));
      await tester.pumpAndSettle();

      final block = tester.widget<Text>(find.textContaining('print("Hello, world")'));
      final colours = <Color?>{};
      block.textSpan!.visitChildren((span) {
        if (span is TextSpan && (span.text?.isNotEmpty ?? false)) colours.add(span.style?.color);
        return true;
      });

      expect(colours.length, greaterThan(1), reason: 'a highlighted line uses more than one colour');
    });

    testWidgets('a block in an unknown language stays readable', (tester) async {
      // No grammar is not an error — the sample still has to be legible.
      await tester.pumpWidget(_host(const LessonProse(markdown: '```brainfuck\n+[->+]\n```')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('+[->+]'), findsOneWidget);
    });

    testWidgets('a code block is legible on the dark surface', (tester) async {
      // `styleSheet.code` is shared with inline code, which sits on the light
      // page, so the block needs its own builder — keyed on `pre`, not `code`.
      await tester.pumpWidget(_host(LessonProse(markdown: lesson.sections.first.prose)));
      await tester.pumpAndSettle();

      final block = tester.widget<Text>(find.textContaining('print("Hello, world")'));
      final tokens = buildAppTheme().extensions.whereType<AppTheme>().first;

      // The highlighter colours the tokens it recognises and leaves the rest on
      // the base style, which must still read against the dark surface.
      expect(block.textSpan!.style?.color, tokens.colors.codeForeground);
      expect(block.textSpan!.style?.color, isNot(tokens.colors.codeBackground));
    });

    testWidgets('a code block fills the width it is given', (tester) async {
      await tester.pumpWidget(_host(LessonProse(markdown: lesson.sections.first.prose)));
      await tester.pumpAndSettle();

      final box = tester.renderObject<RenderBox>(
        find.ancestor(of: find.textContaining('print("Hello, world")'), matching: find.byType(SizedBox)).first,
      );
      expect(box.size.width, 700, reason: 'the host is 700 wide; a one-line example must not shrink-wrap');
    });
  });

  group('OutputPanel', () {
    testWidgets('a pass shows the output and the verdict', (tester) async {
      await tester.pumpWidget(
        _host(const OutputPanel(result: AttemptResult(passed: true, output: 'Hello, world\n'))),
      );
      await tester.pumpAndSettle();

      expect(find.text('Hello, world'), findsOneWidget);
      expect(find.text('Goed!'), findsOneWidget);
    });

    testWidgets('a failed check shows the validator\'s own words', (tester) async {
      await tester.pumpWidget(
        _host(
          const OutputPanel(
            result: AttemptResult(passed: false, output: '', checkMessage: 'Gebruik de print-functie.'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Gebruik de print-functie.'), findsOneWidget);
      expect(find.text('Goed!'), findsNothing);
    });

    testWidgets('a check message is markdown, not literal backticks', (tester) async {
      // Validator messages are authored beside the lesson's prose and use the
      // same code spans, so they must be rendered the same way.
      await tester.pumpWidget(
        _host(
          const OutputPanel(
            result: AttemptResult(
              passed: false,
              output: '',
              checkMessage: '`print` eerst 42, gebruik 2 losse `print`-regels.',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('`'), findsNothing, reason: 'backticks must be markup, not content');
      expect(find.textContaining('print'), findsWidgets);
    });

    testWidgets('a crash introduces the traceback before showing it', (tester) async {
      await tester.pumpWidget(
        _host(
          const OutputPanel(
            result: AttemptResult(passed: false, output: '', programError: 'NameError: prnt'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // A bare traceback reads as the app breaking.
      expect(find.text('Python kon je code niet (geheel) uitvoeren:'), findsOneWidget);
    });

    testWidgets('a crash shows the traceback and no verdict', (tester) async {
      await tester.pumpWidget(
        _host(
          const OutputPanel(
            result: AttemptResult(
              passed: false,
              output: 'before\n',
              programError: 'Traceback (most recent call last):\nNameError: prnt',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('before'), findsOneWidget);
      expect(find.textContaining('NameError'), findsOneWidget);
      expect(find.text('Goed!'), findsNothing);
    });

    testWidgets('a run with no output at all still shows its verdict', (tester) async {
      await tester.pumpWidget(_host(const OutputPanel(result: AttemptResult(passed: true, output: ''))));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Goed!'), findsOneWidget);
    });
  });

  group('CodeEditorCard', () {
    // re_editor asserts on an unbounded height, and the card always sits inside
    // a scroll view, which is exactly the constraint the app hands it.
    testWidgets('a single-line editor refuses the Enter key', (tester) async {
      final controller = CodeLineEditingController.fromText('print(1)');
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _host(
          CodeEditorCard(
            controller: controller,
            status: 'python',
            singleLine: true,
            height: CodeEditorCard.heightForLines(1),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(CodeEditor));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      // Sized to one line, so a second could only scroll out of sight.
      expect(controller.text, isNot(contains('\n')));
      expect(controller.text, 'print(1)', reason: 'and the split line is rejoined exactly as it was');
    });

    testWidgets('a single-line editor flattens a pasted block', (tester) async {
      final controller = CodeLineEditingController.fromText('print(1)');
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _host(
          CodeEditorCard(
            controller: controller,
            status: 'python',
            singleLine: true,
            height: CodeEditorCard.heightForLines(1),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter is not the only way a newline arrives.
      controller.text = 'print(1)\nprint(2)';
      await tester.pumpAndSettle();

      expect(controller.text, isNot(contains('\n')));
    });

    testWidgets('a normal editor still accepts the Enter key', (tester) async {
      final controller = CodeLineEditingController.fromText('print(1)');
      addTearDown(controller.dispose);

      await tester.pumpWidget(_host(CodeEditorCard(controller: controller, status: 'python')));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(CodeEditor));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(controller.text, contains('\n'));
    });

    testWidgets('shows line numbers', (tester) async {
      final controller = CodeLineEditingController.fromText('print(1)\nprint(2)\nprint(3)');
      addTearDown(controller.dispose);

      await tester.pumpWidget(_host(CodeEditorCard(controller: controller, status: 'python')));
      await tester.pumpAndSettle();

      // A traceback says "line 3", which needs line 3 labelled.
      expect(find.byType(DefaultCodeLineNumber), findsOneWidget);
    });

    testWidgets('a single-line editor has no gutter', (tester) async {
      final controller = CodeLineEditingController.fromText('print(1)');
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _host(
          CodeEditorCard(
            controller: controller,
            status: 'python',
            singleLine: true,
            height: CodeEditorCard.heightForLines(1),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Nothing to number, so a column reading "1" is only clutter.
      expect(find.byType(DefaultCodeLineNumber), findsNothing);
    });

    testWidgets('lays out inside a scroll view', (tester) async {
      final controller = CodeLineEditingController.fromText('print(42)\nprint(3.14)');
      addTearDown(controller.dispose);

      await tester.pumpWidget(_host(CodeEditorCard(controller: controller, status: 'python')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('main.py'), findsOneWidget);
      expect(find.text('python'), findsOneWidget);
    });

    testWidgets('takes the height it is given, however long the code is', (tester) async {
      final long = CodeLineEditingController.fromText(List.filled(80, 'print(1)').join('\n'));
      addTearDown(long.dispose);

      final height = CodeEditorCard.heightForLines(2);
      await tester.pumpWidget(_host(CodeEditorCard(controller: long, status: 'python', height: height)));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(CodeEditor)).height,
        height,
        reason: '80 lines must scroll inside the editor, not stretch the page',
      );
    });
  });

  group('StepProgressBar', () {
    testWidgets('renders one segment per step and reports taps', (tester) async {
      var tapped = -1;
      await tester.pumpWidget(
        _host(
          StepProgressBar(stepCount: 3, current: 1, passed: const {0}, onTap: (step) => tapped = step),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey(0)), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey(2)));
      // FTappable runs a short timer for its pressed state, and leaving it
      // pending fails the test.
      await tester.pumpAndSettle();

      expect(tapped, 2);
    });

    testWidgets('paints passed, current and upcoming differently', (tester) async {
      await tester.pumpWidget(
        _host(
          Align(
            child: StepProgressBar(stepCount: 3, current: 1, passed: const {0}, onTap: (_) {}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      Color? fillOf(int step) {
        final box = tester.widget<DecoratedBox>(
          find.descendant(of: find.byKey(ValueKey(step)), matching: find.byType(DecoratedBox)).first,
        );
        return (box.decoration as ShapeDecoration).color;
      }

      final colors = buildAppTheme().extensions.whereType<AppTheme>().first.colors;

      // An info step reaches `passed` by being walked past, so this is also
      // what a completed reading step looks like.
      expect(fillOf(0), colors.progressComplete);
      expect(fillOf(1), colors.progressCurrent);
      expect(fillOf(2), colors.progressTrack);
    });

    testWidgets('is compact enough to sit in the header', (tester) async {
      await tester.pumpWidget(
        _host(Align(child: StepProgressBar(stepCount: 4, current: 0, passed: const {}, onTap: (_) {}))),
      );
      await tester.pumpAndSettle();

      // Four segments and three 6px gaps.
      expect(
        tester.getSize(find.byType(StepProgressBar)).width,
        4 * StepProgressBar.segmentWidth + 3 * 6,
      );
    });
  });

  group('CodeEditorCard colours', () {
    testWidgets('draws its caret against the editor, not the page', (tester) async {
      // `colors.primary` is near-black in the neutral preset, and so is the
      // editor's surface, which would make the caret invisible.
      final controller = CodeLineEditingController.fromText('print(1)');
      addTearDown(controller.dispose);

      await tester.pumpWidget(_host(CodeEditorCard(controller: controller, status: 'python')));
      await tester.pumpAndSettle();

      final tokens = buildAppTheme().extensions.whereType<AppTheme>().first;
      final style = tester.widget<CodeEditor>(find.byType(CodeEditor)).style!;

      expect(style.cursorColor, tokens.colors.codeForeground);
      expect(style.cursorColor, isNot(tokens.colors.codeBackground));
      expect(style.cursorColor, isNot(buildAppTheme().colors.primary));
    });
  });

  group('the step heading', () {
    // One size for every kind, so the steps read as one sequence.
    for (final kind in SectionKind.values) {
      testWidgets('${kind.name} uses the shared title size', (tester) async {
        final section = lesson.sections.firstWhere((s) => s.kind == kind);

        await tester.pumpWidget(_host(SectionHeading(section: section)));
        await tester.pumpAndSettle();

        // `textContaining`, not `text`: the heading is a `Text.rich` whose
        // first span is the step's emoji.
        expect(
          tester.widget<Text>(find.textContaining(section.title)).style?.fontSize,
          SectionHeading.titleSize,
        );
      });
    }

    testWidgets('the step\'s emoji is drawn in front of its title', (tester) async {
      final section = lesson.sections.first;

      await tester.pumpWidget(_host(SectionHeading(section: section)));
      await tester.pumpAndSettle();

      final heading = tester.widget<Text>(find.textContaining(section.title));

      expect(section.emoji, isNotNull, reason: 'the fixture lesson should carry one');
      expect(heading.textSpan?.toPlainText(), startsWith(section.emoji!));
    });

    testWidgets('a step without an emoji still renders its title', (tester) async {
      const section = LessonSection(id: 's', title: 'Zonder emoji', kind: SectionKind.info, prose: '');

      await tester.pumpWidget(_host(const SectionHeading(section: section)));
      await tester.pumpAndSettle();

      expect(tester.widget<Text>(find.textContaining('Zonder emoji')).textSpan?.toPlainText(), 'Zonder emoji');
    });

    testWidgets('a required step carries no badge and no way past it', (tester) async {
      await tester.pumpWidget(_host(SectionHeading(section: lesson.sections.first)));
      await tester.pumpAndSettle();

      expect(find.byType(OptionalStepBanner), findsNothing);
    });

    testWidgets('an optional step is badged and can be skipped', (tester) async {
      var skipped = 0;
      final section = lesson.sections.first;

      await tester.pumpWidget(_host(SectionHeading(section: section, onSkip: () => skipped++)));
      await tester.pumpAndSettle();

      expect(find.text('VERDIEPING'), findsOneWidget);
      expect(find.textContaining(section.title), findsOneWidget);

      await tester.tap(find.text('Overslaan'));
      await tester.pumpAndSettle();

      expect(skipped, 1);
    });

    testWidgets('the badge and the way past sit under the title, not over it', (tester) async {
      final section = lesson.sections.first;

      await tester.pumpWidget(_host(SectionHeading(section: section, onSkip: () {})));
      await tester.pumpAndSettle();

      // A badge above the title would ask the reader to take in a label for a
      // step they have not been told the name of yet, and would put every
      // optional step's title at a different height from every required one's.
      expect(
        tester.getTopLeft(find.byType(OptionalStepBanner)).dy,
        greaterThan(tester.getBottomLeft(find.textContaining(section.title)).dy - 1),
      );
    });

    testWidgets('the skip link is legible and underlined', (tester) async {
      // `link` rather than `primary`: the neutral accent is 1.2:1 on the page,
      // so it cannot carry text. The underline is what marks it as a link.
      await tester.pumpWidget(_host(SectionHeading(section: lesson.sections.first, onSkip: () {})));
      await tester.pumpAndSettle();

      final tokens = buildAppTheme().extensions.whereType<AppTheme>().first;
      final style = tester.widget<Text>(find.text('Overslaan')).style;

      expect(style?.color, tokens.colors.link);
      expect(style?.decoration, TextDecoration.underline);
    });
  });

  group('CatalogCard', () {
    testWidgets('an emoji fills the tile in place of the label', (tester) async {
      await tester.pumpWidget(
        _host(
          const CatalogCard(label: '2', emoji: '\u{2328}\u{FE0F}', title: 'Invoer en uitvoer', meta: '0 / 3'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('\u{2328}\u{FE0F}'), findsOneWidget);
      expect(find.text('2'), findsNothing);
    });

    testWidgets('without one the tile keeps its number', (tester) async {
      await tester.pumpWidget(
        _host(const CatalogCard(label: '2', title: 'Invoer en uitvoer', meta: '0 / 3')),
      );
      await tester.pumpAndSettle();

      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('the tile label is legible on its own fill', (tester) async {
      await tester.pumpWidget(
        _host(CatalogCard(label: '1', title: 'Invoer en uitvoer', meta: '0 / 3', onTap: () {})),
      );
      await tester.pumpAndSettle();

      // The page's `foreground` is near-black, and so is the `primary` the tile
      // is filled with.
      final colors = buildAppTheme().colors;
      expect(tester.widget<Text>(find.text('1')).style?.color, colors.primaryForeground);
      expect(tester.widget<Text>(find.text('1')).style?.color, isNot(colors.primary));
    });

    testWidgets('a finished row is marked with a filled badge, not a bare tick', (tester) async {
      await tester.pumpWidget(
        _host(CatalogCard(label: '1', title: 'Invoer en uitvoer', meta: '0 / 3', finished: true, onTap: () {})),
      );
      await tester.pumpAndSettle();

      final tokens = buildAppTheme();
      final badge =
          tester
                  .widgetList<DecoratedBox>(
                    find.ancestor(of: find.byIcon(FLucideIcons.check), matching: find.byType(DecoratedBox)),
                  )
                  .first
                  .decoration
              as ShapeDecoration;

      // Filled with the completed colour, with the tick knocked out of it —
      // never white, which fails AA on the greens both presets use here.
      expect(badge.color, tokens.extensions.whereType<AppTheme>().first.colors.progressComplete);
      expect(
        tester.widget<Icon>(find.byIcon(FLucideIcons.check)).color,
        tokens.extensions.whereType<AppTheme>().first.colors.progressCompleteForeground,
      );

      // A lamp, so a circle rather than the squircle everything else is, and a
      // flat disc: an outline round it read as a second shape rather than as a
      // crisper edge.
      //
      // The exact numbers are [CompletedBadge]'s to tune, so nothing here pins
      // one: these hold the shape of the thing, not its settings.
      expect((badge.shape as CircleBorder).side.style, BorderStyle.none);

      // And it is lit by a stack of shadows, not one: a tight core, a halo and
      // a wide bloom, all centred. A single shadow reads as a ring at a small
      // blur and as nothing at a large one.
      final shadows = badge.shadows!;
      expect(shadows.length, greaterThan(1));
      expect(shadows.every((shadow) => shadow.offset == Offset.zero), isTrue);

      // Spreading and fading outward, which is what makes the falloff look
      // like light rather than like stacked rings.
      for (var layer = 1; layer < shadows.length; layer++) {
        expect(shadows[layer].blurRadius, greaterThan(shadows[layer - 1].blurRadius));
        expect(shadows[layer].color.a, lessThan(shadows[layer - 1].color.a));
      }
    });

    testWidgets('an unavailable tile keeps the page colour on its grey fill', (tester) async {
      await tester.pumpWidget(
        _host(const CatalogCard(label: '2', title: 'Condities', meta: 'binnenkort', onTap: null)),
      );
      await tester.pumpAndSettle();

      expect(tester.widget<Text>(find.text('2')).style?.color, buildAppTheme().colors.foreground);
    });
  });

  group('LessonCompletePanel', () {
    Widget panel({int completedSteps = 3, VoidCallback? onNextLesson}) => LessonCompletePanel(
      emoji: '\u{2328}\u{FE0F}',
      title: 'Invoer en uitvoer',
      completedSteps: completedSteps,
      stepCount: 3,
      onNextLesson: onNextLesson,
      onBack: () {},
      backLabel: 'Vorige stap',
      onLeave: () {},
      leaveLabel: 'Terug naar Python',
    );

    testWidgets('a finished lesson is named as finished', (tester) async {
      await tester.pumpWidget(_host(panel()));
      await tester.pumpAndSettle();

      expect(find.text('Invoer en uitvoer afgerond!'), findsOneWidget);
      expect(find.text('3 van de 3 stappen gedaan.'), findsOneWidget);
    });

    testWidgets('a lesson left with a step unfinished does not claim to be', (tester) async {
      // A skipped "Verdieping" reaches the end page without completing the
      // lesson, and the page MUST NOT congratulate the student for it.
      await tester.pumpWidget(_host(panel(completedSteps: 2)));
      await tester.pumpAndSettle();

      expect(find.text('Einde van Invoer en uitvoer'), findsOneWidget);
      expect(find.text('2 van de 3 stappen gedaan.'), findsOneWidget);
    });

    testWidgets('the way forward carries the brand fill, whether or not there is a next lesson', (tester) async {
      final primary = buildAppTheme().colors.primary;
      ShapeDecoration decorationOf(String label) => tester
          .widget<DecoratedBox>(
            find.ancestor(of: find.text(label), matching: find.byType(DecoratedBox)).first,
          )
          .decoration as ShapeDecoration;

      await tester.pumpWidget(_host(panel(onNextLesson: () {})));
      await tester.pumpAndSettle();

      expect(decorationOf('Volgende les').color, primary);
      expect(decorationOf('Terug naar Python').color, isNot(primary));

      // The last lesson of a language has nowhere else to go, so the catalog
      // becomes the way forward rather than the quiet option beside it.
      await tester.pumpWidget(_host(panel()));
      await tester.pumpAndSettle();

      expect(find.text('Volgende les'), findsNothing);
      expect(decorationOf('Terug naar Python').color, primary);
    });
  });

  group('ConfettiBurst', () {
    testWidgets('fires a cannon from either side', (tester) async {
      await tester.pumpWidget(_host(const SizedBox(width: 600, height: 400, child: ConfettiBurst())));
      await tester.pump();

      final cannons = tester.widgetList<Confetti>(find.byType(Confetti)).toList();
      expect(cannons, hasLength(2));
      expect(cannons.map((c) => c.options!.x), [0, 1]);
      // Aimed inward and upward — 90 is straight up.
      expect(cannons.map((c) => c.options!.angle), [60, 120]);
      expect(cannons.every((c) => c.options!.colors.contains(buildAppTheme().colors.primary)), isTrue);

      // Disposes the tickers the cannons started, which would otherwise still
      // be running when the test ends.
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('draws nothing at all for a reader who asked for less motion', (tester) async {
      // `prefers-reduced-motion: reduce` on the web, which the engine maps onto
      // MediaQuery's disableAnimations.
      await tester.pumpWidget(
        _host(
          // Inside the host, whose own MediaQuery would otherwise replace this
          // one wholesale rather than being amended by it.
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: const SizedBox(width: 600, height: 400, child: ConfettiBurst()),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(Confetti), findsNothing);
    });
  });

  group('AppButton', () {
    testWidgets('an icon sits on the side it was given, not always the same one', (tester) async {
      Future<double> iconX(AppButtonIconSide side) async {
        await tester.pumpWidget(
          _host(
            Align(
              child: AppButton(
                icon: FLucideIcons.chevronRight,
                iconSide: side,
                onPress: () {},
                child: const Text('Volgende'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        return tester.getCenter(find.byIcon(FLucideIcons.chevronRight)).dx;
      }

      final labelX = await iconX(AppButtonIconSide.trailing).then((x) async {
        final label = tester.getCenter(find.text('Volgende')).dx;
        expect(x, greaterThan(label), reason: 'a trailing chevron points out of the button');
        return label;
      });

      // Leading, so the glyph names the action rather than the destination.
      expect(await iconX(AppButtonIconSide.leading), lessThan(labelX));
    });

    testWidgets('an outlined button draws an edge and no fill', (tester) async {
      await tester.pumpWidget(
        _host(
          Align(
            child: AppButton.icon(
              icon: FLucideIcons.chevronLeft,
              semanticsLabel: 'Vorige stap',
              onPress: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final decoration =
          tester
                  .widget<DecoratedBox>(
                    find.descendant(of: find.byType(AppButton), matching: find.byType(DecoratedBox)).first,
                  )
                  .decoration
              as ShapeDecoration;
      final theme = buildAppTheme();

      // The page shows through it: an outline that filled would be the neutral
      // tone with a line round it.
      expect(decoration.color?.a ?? 0, 0);
      // The page's ink, which is what the neutral tone is filled with: the same
      // button, with and without its fill.
      expect((decoration.shape as ContinuousRectangleBorder).side.color, theme.colors.foreground);
      // Its glyph is the page's own ink, which `theme_test` already holds to AA
      // against the background — so the tone needs no colour pair of its own.
      expect(tester.widget<Icon>(find.byIcon(FLucideIcons.chevronLeft)).color, theme.colors.foreground);
    });

    testWidgets('an icon-only button is named for a screen reader', (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        _host(
          Align(
            child: AppButton.icon(
              icon: FLucideIcons.chevronLeft,
              semanticsLabel: 'Vorige stap',
              onPress: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // There is no text in it to fall back on, so without this the button is
      // announced as nothing at all.
      expect(find.bySemanticsLabel('Vorige stap'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a row gives an icon-only button the height of the labelled one beside it', (tester) async {
      await tester.pumpWidget(
        _host(
          Align(
            child: AppButtonRow(
              children: [
                AppButton.icon(
                  icon: FLucideIcons.chevronLeft,
                  semanticsLabel: 'Vorige stap',
                  onPress: () {},
                ),
                AppButton(onPress: () {}, child: const Text('Volgende')),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // A glyph is shorter than a line of text, and that line's height belongs
      // to the font. The row is what makes them agree.
      final sizes = tester.widgetList<AppButton>(find.byType(AppButton)).map((b) => tester.getSize(find.byWidget(b)));
      expect(sizes.map((size) => size.height).toSet(), hasLength(1), reason: 'heights: $sizes');
    });

    testWidgets('keeps its width when it starts working', (tester) async {
      await tester.pumpWidget(
        _host(Align(child: AppButton(onPress: () {}, child: const Text('Draai code & controleer')))),
      );
      await tester.pumpAndSettle();
      final idle = tester.getSize(find.byType(AppButton));

      await tester.pumpWidget(
        _host(
          Align(child: AppButton(busy: true, onPress: null, child: const Text('Draai code & controleer'))),
        ),
      );
      await tester.pump();

      expect(tester.getSize(find.byType(AppButton)), idle, reason: 'the button must not jump when pressed');
      expect(find.byType(FCircularProgress), findsOneWidget);
    });
  });

  group('a read-only code block', () {
    /// The page, the card, and nothing else down the middle of the block.
    ///
    /// `MarkdownBody` merges the app's style sheet onto a **Material** one, and
    /// merge keeps the fallback wherever the app leaves a null. That fallback is
    /// built from a default light `ThemeData` — there is no Material ancestor —
    /// so an unset slot paints a fixed light colour that never follows the app's
    /// theme. On the dark page it read as a white halo around the code card.
    Future<Set<int>> colours(WidgetTester tester, Brightness brightness) async {
      final key = GlobalKey();
      final theme = buildAppTheme(brightness: brightness);

      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: FTheme(
            data: theme,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: MediaQuery(
                data: const MediaQueryData(size: Size(700, 400)),
                child: ColoredBox(
                  color: theme.colors.background,
                  child: const Padding(
                    padding: EdgeInsets.all(30),
                    child: LessonProse(markdown: 'Tekst.\n\n```python\nprint("hoi")\n```\n\nNa.'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      late final ui.Image image;
      await tester.runAsync(() async => image = await boundary.toImage());
      final data = (await tester.runAsync(() => image.toByteData()))!;

      // A column down the middle, which crosses the page, the gap above the
      // card, the card itself and the gap below it.
      final seen = <int>{};
      for (var y = 0; y < image.height; y++) {
        final i = (y * image.width + (image.width ~/ 2)) * 4;
        seen.add((data.getUint8(i) << 16) | (data.getUint8(i + 1) << 8) | data.getUint8(i + 2));
      }
      return seen;
    }

    for (final brightness in Brightness.values) {
      testWidgets('sits straight on the ${brightness.name} page, with no Material surface behind it', (tester) async {
        final theme = buildAppTheme(brightness: brightness);
        final seen = await colours(tester, brightness);

        expect(seen, contains(_rgb(theme.colors.background)), reason: 'the page should reach the block');
        expect(seen, contains(_rgb(theme.appTheme.colors.codeBackground)), reason: 'the card should be drawn');
        // Material 3's default light surface. Nothing in this app may paint it.
        expect(seen, isNot(contains(0xFEF7FF)));

        final hex = seen.map((c) => c.toRadixString(16).padLeft(6, '0')).toList();
        expect(seen.length, 2, reason: 'only the page and the card should be painted here, found $hex');
      });
    }
  });

  group('StepTransition', () {
    /// A step, keyed the way the lesson screen keys one: by its index.
    Widget step(int index) =>
        KeyedSubtree(key: ValueKey('step$index'), child: SizedBox.expand(child: Text('stap $index')));

    Widget host(Widget child, {bool motion = true}) => _host(
      Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: !motion),
          child: SizedBox(height: 300, child: child),
        ),
      ),
    );

    /// Where a step sits once it has arrived.
    Future<double> settled(WidgetTester tester) async {
      await tester.pumpAndSettle();
      return tester.getTopLeft(find.byKey(const ValueKey('step0'))).dx;
    }

    testWidgets('going on, the step leaving goes left and the one arriving comes from the right', (tester) async {
      await tester.pumpWidget(host(StepTransition(forward: true, child: step(0))));
      final rest = await settled(tester);

      await tester.pumpWidget(host(StepTransition(forward: true, child: step(1))));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Both are on screen at once, travelling the same way: the one being read
      // is pushed off the way the reader came from.
      expect(tester.getTopLeft(find.byKey(const ValueKey('step0'))).dx, lessThan(rest));
      expect(tester.getTopLeft(find.byKey(const ValueKey('step1'))).dx, greaterThan(rest));

      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('step0')), findsNothing);
      expect(tester.getTopLeft(find.byKey(const ValueKey('step1'))).dx, rest);
    });

    testWidgets('going back, both travel the other way', (tester) async {
      await tester.pumpWidget(host(StepTransition(forward: true, child: step(1))));
      await tester.pumpAndSettle();
      final rest = tester.getTopLeft(find.byKey(const ValueKey('step1'))).dx;

      // The direction of the *move*, which is why it is read off the view model
      // rather than worked out from the two steps here.
      await tester.pumpWidget(host(StepTransition(forward: false, child: step(0))));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.getTopLeft(find.byKey(const ValueKey('step1'))).dx, greaterThan(rest));
      expect(tester.getTopLeft(find.byKey(const ValueKey('step0'))).dx, lessThan(rest));
    });

    testWidgets('a reader who asked for less motion gets the next step and no travel', (tester) async {
      await tester.pumpWidget(host(StepTransition(forward: true, child: step(0)), motion: false));
      final rest = await settled(tester);

      await tester.pumpWidget(host(StepTransition(forward: true, child: step(1)), motion: false));
      await tester.pump();

      expect(find.byKey(const ValueKey('step0')), findsNothing);
      expect(tester.getTopLeft(find.byKey(const ValueKey('step1'))).dx, rest);
    });
  });

  group('boardOrder', () {
    test('deals both halves of every pair, into one pool', () {
      final tiles = boardOrder('printing-pairs', 4);

      expect(tiles, hasLength(8));
      expect(
        tiles,
        unorderedEquals([
          for (var pair = 0; pair < 4; pair++) ...[(pair: pair, cue: true), (pair: pair, cue: false)],
        ]),
      );
    });

    test('the same section deals the same board', () {
      // The board is rebuilt on every pick, hover and resize; a fresh shuffle
      // each time would move the tiles under the reader's hand.
      expect(boardOrder('printing-pairs', 6), boardOrder('printing-pairs', 6));
    });

    test('never comes back in the order the lesson wrote it', () {
      // Which would stand every pair side by side, in the file's own order.
      for (var count = 2; count <= 8; count++) {
        for (final seed in ['a', 'printing-pairs', 'zzz', 'een-twee-drie', '']) {
          final written = [
            for (var pair = 0; pair < count; pair++) ...[(pair: pair, cue: true), (pair: pair, cue: false)],
          ];

          expect(boardOrder(seed, count), isNot(written), reason: '$seed x $count');
        }
      }
    });

    test('does not keep the cues away from the answers', () {
      // One pool is the point: a board split into a block of each tells the
      // student which half of a pair a tile is before they have read it.
      final halves = boardOrder('printing-pairs', 4).map((tile) => tile.cue).toList();

      expect(halves.sublist(0, 4), isNot(everyElement(isTrue)));
    });
  });

  group('PairMatchBoard.tileSizeFor', () {
    test('puts every tile in one row while they fit', () {
      // (700 - 3 gaps) / 4.
      expect(PairMatchBoard.tileSizeFor(700, 4), closeTo(166, 0.5));
    });

    test('takes tiles off the row rather than letting one go under the minimum', () {
      final side = PairMatchBoard.tileSizeFor(700, 8);

      expect(side, greaterThanOrEqualTo(PairMatchBoard.minTileSize));
      // All eight across would be 77 each; four fit at 166, so the block wraps.
      expect(side, closeTo(166, 0.5));
    });

    test('width left over once every tile is placed stops at the cap', () {
      expect(PairMatchBoard.tileSizeFor(2000, 4), PairMatchBoard.maxTileSize);
    });

    test('a board narrower than two tiles draws one per row', () {
      expect(PairMatchBoard.tileSizeFor(260, 4), PairMatchBoard.maxTileSize);
    });
  });

  group('PairMatchBoard', () {
    const pairs = [
      LessonPair(cue: 'kat', answer: 'cat'),
      LessonPair(cue: 'hond', answer: 'dog'),
      LessonPair(cue: 'vis', answer: 'fish'),
    ];

    Widget board({
      Set<int> matched = const {},
      Set<PairHalf> picked = const {},
      ValueChanged<PairHalf>? onPick,
    }) => _host(
      PairMatchBoard(
        seed: 'printing-pairs',
        pairs: pairs,
        matched: matched,
        picked: picked,
        onPick: onPick ?? (_) {},
      ),
    );

    /// What every tile on the board is filled with. The widget's own target
    /// value, not the frame it is currently animating through.
    List<Color> fills(WidgetTester tester) => tester
        .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
        .map((tile) => (tile.decoration! as ShapeDecoration).color!)
        .toList();

    /// A board of squares is taller than the test surface, so a tile has to be
    /// scrolled to before it can be tapped.
    Future<void> press(WidgetTester tester, String half) async {
      await tester.ensureVisible(find.textContaining(half));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining(half), warnIfMissed: false);
      await tester.pumpAndSettle();
    }

    testWidgets('draws a tile for every half', (tester) async {
      await tester.pumpWidget(board());
      await tester.pumpAndSettle();

      expect(fills(tester), hasLength(pairs.length * 2));
      for (final pair in pairs) {
        expect(find.textContaining(pair.cue), findsOneWidget);
        expect(find.textContaining(pair.answer), findsOneWidget);
      }
    });

    testWidgets('every tile is a square, and none larger than the cap', (tester) async {
      await tester.pumpWidget(board());
      await tester.pumpAndSettle();

      final sizes = tester
          .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
          .map((tile) => tester.getSize(find.byWidget(tile)))
          .toList();

      expect(sizes, hasLength(pairs.length * 2));
      expect(sizes, everyElement(predicate<Size>((size) => size.width == size.height, 'is square')));
      // Six tiles across the 700 the host gives it would be 107 each, under the
      // minimum, so the board wraps to four.
      expect(sizes.first.width, closeTo(PairMatchBoard.tileSizeFor(700, 6), 0.5));
    });

    testWidgets('a tap names the tile it landed on, half and all', (tester) async {
      final picks = <PairHalf>[];

      await tester.pumpWidget(board(onPick: picks.add));
      await tester.pumpAndSettle();

      await press(tester, 'hond');
      await press(tester, 'dog');

      // Where a tile stands is the deal's business; what it reports is which
      // half of which pair it is.
      expect(picks, [(pair: 1, cue: true), (pair: 1, cue: false)]);
    });

    testWidgets('a matched tile is done and no longer answers a tap', (tester) async {
      final picks = <PairHalf>[];

      await tester.pumpWidget(board(matched: const {0}, onPick: picks.add));
      await tester.pumpAndSettle();

      await press(tester, 'kat');

      expect(picks, isEmpty);
    });

    testWidgets('a matched pair is drawn as done, both halves of it', (tester) async {
      final tokens = buildAppTheme().appTheme;

      await tester.pumpWidget(board(matched: const {2}));
      await tester.pumpAndSettle();

      expect(fills(tester).where((fill) => fill == tokens.colors.successSurface), hasLength(2));
    });

    testWidgets('a wrong pick shows on both of its tiles and on no others', (tester) async {
      final tokens = buildAppTheme().appTheme;

      await tester.pumpWidget(board(picked: const {(pair: 0, cue: true), (pair: 1, cue: false)}));
      await tester.pumpAndSettle();

      expect(fills(tester).where((fill) => fill == tokens.colors.warningSurface), hasLength(2));
    });

    testWidgets('a pick on its own is not wrong yet', (tester) async {
      final tokens = buildAppTheme().appTheme;

      await tester.pumpWidget(board(picked: const {(pair: 0, cue: true)}));
      await tester.pumpAndSettle();

      expect(fills(tester).where((fill) => fill == tokens.colors.warningSurface), isEmpty);
    });

    testWidgets('the board only says so once every pair is together', (tester) async {
      await tester.pumpWidget(board(matched: const {0, 1}));
      await tester.pumpAndSettle();

      expect(find.text('Goed!'), findsNothing);

      await tester.pumpWidget(board(matched: const {0, 1, 2}));
      await tester.pumpAndSettle();

      expect(find.text('Goed!'), findsOneWidget);
    });
  });
}

int _rgb(Color color) =>
    ((color.r * 255).round() << 16) | ((color.g * 255).round() << 8) | (color.b * 255).round();

extension on FThemeData {

  /// The app's own tokens, without needing a `BuildContext`.
  AppTheme get appTheme => extensions.whereType<AppTheme>().first;

}
