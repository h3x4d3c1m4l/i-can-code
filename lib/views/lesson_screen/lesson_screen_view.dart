import 'package:flutter/widgets.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/lessons/lesson.dart';
import 'package:i_can_code/views/base/screen_view_base.dart';
import 'package:i_can_code/views/components/app_button.dart';
import 'package:i_can_code/views/components/app_button_row.dart';
import 'package:i_can_code/views/components/app_header.dart';
import 'package:i_can_code/views/components/app_header_publisher.dart';
import 'package:i_can_code/views/lesson_screen/components/code_editor_card.dart';
import 'package:i_can_code/views/lesson_screen/components/collapsible_prose_group.dart';
import 'package:i_can_code/views/lesson_screen/components/confetti_burst.dart';
import 'package:i_can_code/views/lesson_screen/components/lesson_complete_panel.dart';
import 'package:i_can_code/views/lesson_screen/components/lesson_prose.dart';
import 'package:i_can_code/views/lesson_screen/components/output_panel.dart';
import 'package:i_can_code/views/lesson_screen/components/pair_match_board.dart';
import 'package:i_can_code/views/lesson_screen/components/section_heading.dart';
import 'package:i_can_code/views/lesson_screen/components/step_progress_bar.dart';
import 'package:i_can_code/views/lesson_screen/components/step_transition.dart';
import 'package:i_can_code/views/lesson_screen/lesson_screen_controller.dart';
import 'package:i_can_code/views/lesson_screen/lesson_screen_view_model.dart';
import 'package:re_editor/re_editor.dart';

class LessonScreenView extends ScreenViewBase<LessonScreenViewModel, LessonScreenController> {

  /// The width the prose reserves on its left for a subheading's chevron.
  ///
  /// [LessonProse] indents by it and [CollapsibleProseGroup] fills it, so that
  /// the chevron falls inside the box that is pressed. The page pays for it out
  /// of its own left padding and gets it back on the measure, which is what
  /// keeps the text itself where the design put it — on any width, since a
  /// narrow viewport falls back on the padding and a wide one on the measure.
  static const double _gutter = CollapsibleProseGroup.gutter;

  /// The measure a single column of prose is set to — the design's reading-step
  /// number, roughly 60–70 characters at [_readingProseSize].
  static const double _readingWidth = 660 + _gutter;

  /// The design's reading-step padding, plus the bar.
  ///
  /// The bar is drawn *over* the page rather than above it, so what keeps the
  /// first screenful clear of it is padding inside the scroll view — and what
  /// is scrolled past goes under the bar instead of being cut off at an
  /// invisible edge. The design's own number is the one after it.
  static const EdgeInsets _readingPadding = EdgeInsets.fromLTRB(32 - _gutter, AppHeader.height + 72, 32, 110);

  /// Prose in a single column.
  static const double _readingProseSize = 21;

  /// The design's two-column task step, wider overall than a single column.
  static const double _taskWidth = 1120 + _gutter;

  static const EdgeInsets _taskPadding = EdgeInsets.fromLTRB(32 - _gutter, AppHeader.height + 44, 32, 90);

  /// Puts a widget that is not prose back on the prose's own left edge.
  static Widget _pastGutter(Widget child) =>
      Padding(padding: const EdgeInsets.only(left: _gutter), child: child);

  /// Prose in the narrower of the two columns.
  static const double _taskProseSize = 19;

  /// One editor controller per step, so moving back and forth keeps what was
  /// typed. Held by the view because a [CodeLineEditingController] is a Flutter
  /// object with a lifecycle, not observable state.
  final Map<int, CodeLineEditingController> _editors = {};

  LessonScreenView({required super.viewModel, required super.controller, required super.contextAccessor});

  @override
  Widget get body {
    return Stack(
      // The body used to be the SafeArea's only child, which sized it. Expand
      // hands it the same tight constraints.
      fit: StackFit.expand,
      children: [
        _buildBody(),
        // A layer over the whole screen rather than part of the end page: that
        // page scrolls, and particles that scrolled with it — or were clipped at
        // its edge — would read as a rendering fault.
        Positioned.fill(
          child: IgnorePointer(
            child: Observer(
              builder: (context) => viewModel.completed && viewModel.earnedCelebration
                  ? const ConfettiBurst()
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ],
    );
  }

  /// The lesson, and the header it puts in the app's bar.
  ///
  /// The bar is resolved by the shell, so everything read in [_buildHeader] is
  /// observed there: the trail and the progress bar follow the step without the
  /// screen pushing anything at them.
  Widget _buildBody() {
    return AppHeaderPublisher(
      builder: _buildHeader,
      child: Observer(
        builder: (context) {
          final lesson = viewModel.lesson.forLocale(Localizations.localeOf(context).languageCode);
          final section = lesson.sections[viewModel.step];

          return StepTransition(
            forward: viewModel.forward,
            child: KeyedSubtree(
              // The end page is not a step and has no index, so it takes the
              // one past the last — which is also where it sits.
              key: ValueKey(viewModel.completed ? lesson.stepCount : viewModel.step),
              // The scroll view belongs to the page rather than to the screen:
              // the two-column task step does not scroll as one. See [_Page]
              // and [_SplitPage].
              child: viewModel.completed
                  ? _buildComplete(context, lesson)
                  : switch (section.kind) {
                      SectionKind.info => _buildInfo(context, lesson, section),
                      SectionKind.quickExercise => _buildQuickExercise(context, lesson, section),
                      SectionKind.exercise => _buildExercise(context, lesson, section),
                      SectionKind.matchPairs => _buildMatchPairs(context, lesson, section),
                    },
            ),
          );
        },
      ),
    );
  }

  AppHeaderConfig _buildHeader(BuildContext context) {
    final lesson = viewModel.lesson.forLocale(Localizations.localeOf(context).languageCode);

    return AppHeaderConfig(
      onTapHome: controller.leave,
      crumbs: [
        AppCrumb(
          languageLabel(viewModel.lesson.entry.language),
          onTap: () => controller.openLanguage(viewModel.lesson.entry.language),
        ),
        // The step is deliberately not a crumb: it is already the page heading
        // and the progress bar, and a third showing made the trail change
        // length as the student moved.
        AppCrumb(lesson.title, onTap: viewModel.step == 0 ? null : () => controller.goTo(0)),
      ],
      trailing: StepProgressBar(
        stepCount: lesson.stepCount,
        current: viewModel.step,
        passed: viewModel.passed,
        onTap: controller.goTo,
      ),
      // A lesson is read. This is the one screen the bar gets out of the way of.
      offersZen: true,
    );
  }

  /// The lesson's end page, after the last step. Set to the reading measure, so
  /// it sits where the prose the student just read did.
  Widget _buildComplete(BuildContext context, Lesson lesson) {
    return _Page(
      maxWidth: _readingWidth,
      padding: _readingPadding,
      child: _pastGutter(
        LessonCompletePanel(
          emoji: lesson.emoji,
          title: lesson.title,
          // Read off the view model rather than the store, so a step passed a
          // moment ago is already counted.
          completedSteps: viewModel.passed.length,
          stepCount: lesson.stepCount,
          onNextLesson: viewModel.hasNextLesson ? controller.openNextLesson : null,
          onBack: () => controller.previous(lesson.stepCount),
          backLabel: context.localizations.lessonScreen_back,
          onLeave: () => controller.openLanguage(viewModel.lesson.entry.language),
          leaveLabel: context.localizations.lessonScreen_finish(
            languageLabel(viewModel.lesson.entry.language),
          ),
        ),
      ),
    );
  }

  /// A reading step: one centred column, ending in "Verder".
  Widget _buildInfo(BuildContext context, Lesson lesson, LessonSection section) {
    return _Page(
      maxWidth: _readingWidth,
      padding: _readingPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _pastGutter(_buildHeading(lesson, section)),
          const SizedBox(height: 30),
          LessonProse(markdown: section.prose, fontSize: _readingProseSize, hangingGutter: true),
          // Wider than any gap inside the prose. The row under it is the way
          // *out* of the step rather than another block of it, and set to the
          // prose's own rhythm it read as one more paragraph.
          const SizedBox(height: 36),
          _pastGutter(_buildContinue(context, lesson)),
        ],
      ),
    );
  }

  /// A quick exercise: a reading step that ends in an editor — the same
  /// measure, prose size and padding.
  Widget _buildQuickExercise(BuildContext context, Lesson lesson, LessonSection section) {
    return _Page(
      maxWidth: _readingWidth,
      padding: _readingPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _pastGutter(_buildHeading(lesson, section)),
          const SizedBox(height: 30),
          LessonProse(markdown: section.prose, fontSize: _readingProseSize, hangingGutter: true),
          const SizedBox(height: 20),
          // A quick exercise's answer is one line, so the editor is sized to
          // exactly that. Longer code scrolls inside it.
          ..._buildWorkspace(
            context,
            lesson,
            section,
            editorHeight: CodeEditorCard.heightForLines(1),
            singleLine: true,
          ).map(_pastGutter),
        ],
      ),
    );
  }

  /// A match-pairs step: a reading step whose prose ends in a board instead of
  /// an editor.
  ///
  /// The reading measure rather than the task's two columns: there is nothing
  /// to type here, so the step is read the way an [SectionKind.info] one is and
  /// the board takes the prose's own width.
  Widget _buildMatchPairs(BuildContext context, Lesson lesson, LessonSection section) {
    return _Page(
      maxWidth: _readingWidth,
      padding: _readingPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _pastGutter(_buildHeading(lesson, section)),
          const SizedBox(height: 30),
          LessonProse(markdown: section.prose, fontSize: _readingProseSize, hangingGutter: true),
          const SizedBox(height: 24),
          _pastGutter(
            PairMatchBoard(
              // The section's id, not its position: the board has to come back
              // the same way after a step away, and the same way in either
              // translation.
              seed: section.id,
              pairs: section.pairs,
              matched: viewModel.matched,
              picked: viewModel.picked,
              onPick: (tile) => controller.pick(section, tile),
            ),
          ),
          const SizedBox(height: 36),
          // The way on appears once the board is solved, the same rule an
          // exercise's does — and, like an exercise, it is already there on a
          // step that passed on an earlier visit.
          _pastGutter(
            AppButtonRow(
              children: [
                ..._buildBack(context, lesson),
                if (viewModel.passed.contains(viewModel.step)) _buildNext(context, lesson),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The design's two-column task step: prose left, editor and output right.
  ///
  /// MUST NOT be wrapped in a [LayoutBuilder]: its builder runs at layout time,
  /// so MobX cannot see the observables read inside it and the [Observer] above
  /// would never re-run. [MediaQuery.sizeOf] answers during build instead.
  Widget _buildExercise(BuildContext context, Lesson lesson, LessonSection section) {
    final prose = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _pastGutter(_buildHeading(lesson, section)),
        const SizedBox(height: 20),
        LessonProse(markdown: section.prose, fontSize: _taskProseSize, hangingGutter: true),
      ],
    );
    final workspace = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _buildWorkspace(context, lesson, section, editorHeight: 276),
    );

    // forui's breakpoints are Tailwind's. Below `lg` (1024) each half is too
    // narrow to read a paragraph in, so the two stack.
    final stacked = MediaQuery.sizeOf(context).width < context.theme.breakpoints.lg;

    // Stacked, the workspace sits under the prose and has to line up with it,
    // and the two scroll as one page. Side by side it starts its own column,
    // where the gutter would only push it away from the divide.
    if (stacked) {
      return _Page(
        maxWidth: _taskWidth,
        padding: _taskPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [prose, const SizedBox(height: 30), _pastGutter(workspace)],
        ),
      );
    }

    return _SplitPage(
      maxWidth: _taskWidth,
      padding: _taskPadding,
      gap: 36,
      // Nudged down onto the editor card's own top edge: the prose starts with
      // a heading, which sits a little higher than the card's first line.
      left: Padding(padding: const EdgeInsets.only(top: 6), child: prose),
      right: workspace,
    );
  }

  /// Editor, Run button and output — everything the student interacts with.
  List<Widget> _buildWorkspace(
    BuildContext context,
    Lesson lesson,
    LessonSection section, {
    required double editorHeight,
    bool singleLine = false,
  }) {
    final editor = _editorFor(viewModel.step, section);
    final attempt = viewModel.attempt;

    return [
      CodeEditorCard(
        controller: editor,
        status: _statusLabel(context),
        height: editorHeight,
        singleLine: singleLine,
      ),
      const SizedBox(height: 16),
      AppButtonRow(
        children: [
          ..._buildBack(context, lesson),
          AppButton(
            tone: AppButtonTone.neutral,
            icon: FLucideIcons.play,
            busy: viewModel.running,
            onPress: viewModel.running ? null : () => controller.run(section, editor.text),
            child: Text(context.localizations.lessonScreen_run),
          ),
          if (viewModel.passed.contains(viewModel.step)) _buildNext(context, lesson),
        ],
      ),
      if (attempt != null) ...[
        const SizedBox(height: 16),
        OutputPanel(result: attempt),
      ],
    ];
  }

  /// The step's title, with the "Verdieping" banner above it when the section
  /// may be skipped.
  Widget _buildHeading(Lesson lesson, LessonSection section) => SectionHeading(
    section: section,
    onSkip: section.optional ? () => controller.skip(lesson.stepCount) : null,
  );

  Widget _buildContinue(BuildContext context, Lesson lesson) {
    return AppButtonRow(
      children: [..._buildBack(context, lesson), _buildNext(context, lesson)],
    );
  }

  /// The way back, or nothing at all on the first step — a control that cannot
  /// do anything is worse than no control.
  ///
  /// A list rather than a nullable widget so a caller can spread it into a row
  /// without a `if (back != null)` at every one.
  List<Widget> _buildBack(BuildContext context, Lesson lesson) => [
    if (controller.canGoBack)
      AppButton.icon(
        icon: FLucideIcons.chevronLeft,
        semanticsLabel: context.localizations.lessonScreen_back,
        onPress: () => controller.previous(lesson.stepCount),
      ),
  ];

  /// The way on. The chevron is trailing, so it points out of the button in the
  /// direction it goes; the last step ends in a tick instead, because it opens
  /// the lesson's end page rather than another step.
  Widget _buildNext(BuildContext context, Lesson lesson) {
    final last = viewModel.step + 1 == lesson.stepCount;

    return AppButton(
      icon: last ? FLucideIcons.check : FLucideIcons.chevronRight,
      iconSide: AppButtonIconSide.trailing,
      onPress: () => controller.next(lesson.stepCount),
      child: Text(
        // The last step says "Afronden": it opens the lesson's end page, which
        // is still inside the lesson. Naming the catalog here would promise a
        // screen that is one press further on.
        last ? context.localizations.lessonScreen_complete : context.localizations.lessonScreen_next,
      ),
    );
  }

  /// What the editor's strip says over the code: a run in progress, or else the
  /// interpreter the code will run on.
  ///
  /// The version is the runtime's own answer, so the strip cannot claim a build
  /// the app is not shipping. Where there is none to ask — every non-web build,
  /// and so every widget test — the lesson's own language stands in, which is
  /// the same name without the number.
  String _statusLabel(BuildContext context) {
    if (viewModel.running) return context.localizations.lessonScreen_running;

    return controller.runtimeVersion ?? languageLabel(viewModel.lesson.entry.language);
  }

  /// The editor for [step], created from the section's starter block the first
  /// time it is shown and kept afterwards.
  CodeLineEditingController _editorFor(int step, LessonSection section) =>
      _editors[step] ??= CodeLineEditingController.fromText(viewModel.code[step] ?? section.starter ?? '');

  @override
  void dispose() {
    for (final editor in _editors.values) {
      editor.dispose();
    }
    super.dispose();
  }

}

/// The centred, width-capped column a step that scrolls as one is laid out in.
class _Page extends StatelessWidget {

  final double maxWidth;
  final EdgeInsets padding;
  final Widget child;

  const _Page({required this.maxWidth, required this.padding, required this.child});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      // Inside the scroll rather than around it, which is what lets the top
      // keep the first screenful clear of the bar while everything scrolled
      // past passes *under* the bar.
      padding: padding,
      child: Center(
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
      ),
    );
  }

}

/// The two-column task step: the prose scrolls on its own, and the editor and
/// its output stand still beside it.
///
/// The two columns scroll apart because they are read differently — the prose
/// is read top to bottom while the editor is worked in, and a shared scroll
/// pushed the editor off screen the moment the student looked something up.
/// Below `lg` there is only one column and the step is a [_Page] again.
///
/// The [padding]'s **vertical** halves belong to the columns and not to the
/// page, for the reason [_Page] states: they have to be inside the scroll. The
/// horizontal halves and [maxWidth] stay outside, so the two columns are
/// measured against one page rather than each against its own.
class _SplitPage extends StatelessWidget {

  final double maxWidth;
  final EdgeInsets padding;

  /// What separates the two columns.
  final double gap;

  final Widget left;
  final Widget right;

  const _SplitPage({
    required this.maxWidth,
    required this.padding,
    required this.gap,
    required this.left,
    required this.right,
  });

  @override
  Widget build(BuildContext context) {
    final vertical = EdgeInsets.only(top: padding.top, bottom: padding.bottom);

    return Padding(
      padding: EdgeInsets.only(left: padding.left, right: padding.right),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          // Both columns take the window's full height, which is what gives
          // each one a viewport to scroll inside. The height is there to take:
          // `StepTransition` lays every step out to the full size of the
          // screen.
          //
          // Even halves. `Expanded.flex` is an integer ratio against a default
          // of 1, so `flex: 11` would be an 11:1 split, not 1:1.1.
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: SingleChildScrollView(padding: vertical, child: left)),
              SizedBox(width: gap),
              // A scroll view as well, though this column is meant to stand
              // still: it fits the window and so does not scroll, but a long
              // enough run of output would otherwise overflow it with no way
              // to reach the end.
              Expanded(child: SingleChildScrollView(padding: vertical, child: right)),
            ],
          ),
        ),
      ),
    );
  }

}
