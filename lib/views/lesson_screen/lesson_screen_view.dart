import 'package:flutter/widgets.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/lessons/lesson.dart';
import 'package:i_can_code/views/base/screen_view_base.dart';
import 'package:i_can_code/views/components/app_button.dart';
import 'package:i_can_code/views/components/app_header.dart';
import 'package:i_can_code/views/lesson_screen/components/code_editor_card.dart';
import 'package:i_can_code/views/lesson_screen/components/collapsible_prose_group.dart';
import 'package:i_can_code/views/lesson_screen/components/lesson_prose.dart';
import 'package:i_can_code/views/lesson_screen/components/output_panel.dart';
import 'package:i_can_code/views/lesson_screen/components/section_heading.dart';
import 'package:i_can_code/views/lesson_screen/components/step_progress_bar.dart';
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

  /// The design's reading-step padding.
  static const EdgeInsets _readingPadding = EdgeInsets.fromLTRB(32 - _gutter, 72, 32, 110);

  /// Prose in a single column.
  static const double _readingProseSize = 21;

  /// The design's two-column task step, wider overall than a single column.
  static const double _taskWidth = 1120 + _gutter;

  static const EdgeInsets _taskPadding = EdgeInsets.fromLTRB(32 - _gutter, 44, 32, 90);

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Observer(
          builder: (context) {
            final lesson = viewModel.lesson.forLocale(Localizations.localeOf(context).languageCode);
            return AppHeader(
              onTapHome: controller.leave,
              crumbs: [
                AppCrumb(
                  languageLabel(viewModel.lesson.entry.language),
                  onTap: () => controller.openLanguage(viewModel.lesson.entry.language),
                ),
                // The step is deliberately not a crumb: it is already the
                // page heading and the progress bar, and a third showing made
                // the trail change length as the student moved.
                AppCrumb(lesson.title, onTap: viewModel.step == 0 ? null : () => controller.goTo(0)),
              ],
              trailing: StepProgressBar(
                stepCount: lesson.stepCount,
                current: viewModel.step,
                passed: viewModel.passed,
                onTap: controller.goTo,
              ),
            );
          },
        ),
        Expanded(
          child: Observer(
            builder: (context) {
              final lesson = viewModel.lesson.forLocale(Localizations.localeOf(context).languageCode);
              final section = lesson.sections[viewModel.step];

              return SingleChildScrollView(
                child: switch (section.kind) {
                  SectionKind.info => _buildInfo(context, lesson, section),
                  SectionKind.quickExercise => _buildQuickExercise(context, lesson, section),
                  SectionKind.exercise => _buildExercise(context, lesson, section),
                },
              );
            },
          ),
        ),
      ],
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
          const SizedBox(height: 10),
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

    return _Page(
      maxWidth: _taskWidth,
      padding: _taskPadding,
      child: stacked
          // Stacked, the workspace sits under the prose and has to line up with
          // it. Side by side it starts its own column, where the gutter would
          // only push it away from the divide.
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [prose, const SizedBox(height: 30), _pastGutter(workspace)],
            )
          // Even halves. `Expanded.flex` is an integer ratio against a default
          // of 1, so `flex: 11` would be an 11:1 split, not 1:1.1.
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Padding(padding: const EdgeInsets.only(top: 6), child: prose)),
                const SizedBox(width: 36),
                Expanded(child: workspace),
              ],
            ),
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
      Row(
        children: [
          AppButton(
            tone: AppButtonTone.neutral,
            busy: viewModel.running,
            onPress: viewModel.running ? null : () => controller.run(section, editor.text),
            child: Text(context.localizations.lessonScreen_run),
          ),
          if (viewModel.passed.contains(viewModel.step)) ...[
            const SizedBox(width: 16),
            AppButton(
              onPress: () => controller.next(lesson.stepCount),
              child: Text(_nextLabel(context, lesson)),
            ),
          ],
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
    return Row(
      children: [
        AppButton(
          onPress: () => controller.next(lesson.stepCount),
          child: Text(_nextLabel(context, lesson)),
        ),
      ],
    );
  }

  /// The last step names where it lands rather than saying "overzicht", which
  /// reads as the language picker — the screen above the one it actually opens.
  String _nextLabel(BuildContext context, Lesson lesson) => viewModel.step + 1 < lesson.stepCount
      ? context.localizations.lessonScreen_next
      : context.localizations.lessonScreen_finish(languageLabel(viewModel.lesson.entry.language));

  String _statusLabel(BuildContext context) =>
      viewModel.running ? context.localizations.lessonScreen_running : 'python';

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

/// The centred, width-capped column every step is laid out in.
class _Page extends StatelessWidget {

  final double maxWidth;
  final EdgeInsets padding;
  final Widget child;

  const _Page({required this.maxWidth, required this.padding, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Center(
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
      ),
    );
  }

}
