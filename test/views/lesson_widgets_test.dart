import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/l10n/generated/app_localizations.dart';
import 'package:i_can_code/services/lessons/lesson.dart';
import 'package:i_can_code/services/python/python_attempt_runner.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/theme.dart';
import 'package:i_can_code/views/components/app_button.dart';
import 'package:i_can_code/views/components/catalog_card.dart';
import 'package:i_can_code/views/lesson_screen/components/code_editor_card.dart';
import 'package:i_can_code/views/lesson_screen/components/lesson_prose.dart';
import 'package:i_can_code/views/lesson_screen/components/output_panel.dart';
import 'package:i_can_code/views/lesson_screen/components/section_heading.dart';
import 'package:i_can_code/views/lesson_screen/components/step_progress_bar.dart';
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

      // 18 paragraph spacing + 8 sheet blockSpacing + 8 of the block's own.
      // A paragraph carries its spacing below itself, so without the builder's
      // trailing space the gap under a block would be 8px against 26 above.
      expect(card.top - above.bottom, 34);
      expect(below.top - card.bottom, 34);
      // The card's own padding. Its top gap is larger because the language
      // label sits above the code inside the card.
      expect(card.bottom - inside.bottom, CodeEditorCard.codePadding.bottom);
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

        expect(
          tester.widget<Text>(find.text(section.title)).style?.fontSize,
          SectionHeading.titleSize,
        );
      });
    }
  });

  group('CatalogCard', () {
    testWidgets('the tile label is legible on its own fill', (tester) async {
      await tester.pumpWidget(
        _host(CatalogCard(label: '1', title: 'Invoer en uitvoer', meta: '3 stappen', onTap: () {})),
      );
      await tester.pumpAndSettle();

      // The page's `foreground` is near-black, and so is the `primary` the tile
      // is filled with.
      final colors = buildAppTheme().colors;
      expect(tester.widget<Text>(find.text('1')).style?.color, colors.primaryForeground);
      expect(tester.widget<Text>(find.text('1')).style?.color, isNot(colors.primary));
    });

    testWidgets('an unavailable tile keeps the page colour on its grey fill', (tester) async {
      await tester.pumpWidget(
        _host(const CatalogCard(label: '2', title: 'Condities', meta: 'binnenkort', onTap: null)),
      );
      await tester.pumpAndSettle();

      expect(tester.widget<Text>(find.text('2')).style?.color, buildAppTheme().colors.foreground);
    });
  });

  group('AppButton', () {
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
}
