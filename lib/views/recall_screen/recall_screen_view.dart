import 'package:flutter/widgets.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/lessons/lesson.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/views/base/screen_view_base.dart';
import 'package:i_can_code/views/components/app_button.dart';
import 'package:i_can_code/views/components/app_button_row.dart';
import 'package:i_can_code/views/components/app_header.dart';
import 'package:i_can_code/views/components/app_header_publisher.dart';
import 'package:i_can_code/views/lesson_screen/components/code_editor_card.dart';
import 'package:i_can_code/views/lesson_screen/components/code_sample.dart';
import 'package:i_can_code/views/lesson_screen/components/lesson_prose.dart';
import 'package:i_can_code/views/lesson_screen/components/output_panel.dart';
import 'package:i_can_code/views/lesson_screen/components/prediction_field.dart';
import 'package:i_can_code/views/lesson_screen/components/prediction_verdict.dart';
import 'package:i_can_code/views/lesson_screen/components/run_button.dart';
import 'package:i_can_code/views/lesson_screen/components/step_progress_bar.dart';
import 'package:i_can_code/views/lesson_screen/components/step_transition.dart';
import 'package:i_can_code/views/recall_screen/recall_screen_controller.dart';
import 'package:i_can_code/views/recall_screen/recall_screen_view_model.dart';
import 'package:re_editor/re_editor.dart';

/// A refresher: a handful of steps from finished lessons, asked again a day or
/// more later.
///
/// The step is drawn the way a reading step is — one centred column — rather
/// than in the lesson's two-column task layout. There is nothing to look up
/// beside the editor here: the student has read this prose before, and what is
/// being measured is what they kept.
class RecallScreenView extends ScreenViewBase<RecallScreenViewModel, RecallScreenController> {

  static const double _width = 660;

  static const EdgeInsets _padding = EdgeInsets.fromLTRB(32, AppHeader.height + 72, 32, 110);

  /// **Empty, never the section's starter block.** Taking the scaffolding away
  /// is the whole point: the first time through, the starter said half the
  /// answer. One controller per item, so stepping back and forth keeps what was
  /// typed.
  final Map<int, CodeLineEditingController> _editors = {};

  /// One prediction box per item, for the reason [_editors] is one per item.
  final Map<int, TextEditingController> _predictions = {};

  RecallScreenView({required super.viewModel, required super.controller, required super.contextAccessor});

  @override
  Widget get body {
    return AppHeaderPublisher(
      builder: _buildHeader,
      child: Observer(
        builder: (context) {
          if (!viewModel.hasItems) return _page(_buildEmpty(context));

          return StepTransition(
            forward: true,
            child: KeyedSubtree(
              key: ValueKey(viewModel.completed ? viewModel.items.length : viewModel.index),
              child: viewModel.completed ? _page(_buildDone(context)) : _page(_buildItem(context)),
            ),
          );
        },
      ),
    );
  }

  AppHeaderConfig _buildHeader(BuildContext context) => AppHeaderConfig(
    onTapHome: controller.goHome,
    crumbs: [
      AppCrumb(languageLabel(viewModel.language), onTap: controller.leave),
      AppCrumb(context.localizations.recallScreen_title),
    ],
    trailing: viewModel.hasItems
        ? StepProgressBar(
            stepCount: viewModel.items.length,
            current: viewModel.index,
            passed: viewModel.passed,
            // No onTap: a refresher is walked forward, and there is nothing
            // behind to go back to.
          )
        : null,
    // A refresher is read and worked the way a lesson is.
    offersZen: true,
  );

  Widget _page(Widget child) => SingleChildScrollView(
    padding: _padding,
    child: Center(
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: _width), child: child),
    ),
  );

  /// One item: where it came from, what it asked, and an empty editor.
  Widget _buildItem(BuildContext context) {
    final tokens = context.appTheme;
    final item = viewModel.item;
    final locale = Localizations.localeOf(context).languageCode;
    final lesson = item.lesson.forLocale(locale);
    // The section as this locale words it. Read by id rather than by position,
    // the way progress is, so a reordered lesson still finds the right one.
    final section = lesson.sections.firstWhere((s) => s.id == item.section.id, orElse: () => item.section);
    final predicting = section.kind == SectionKind.predictOutput;
    final editor = _editors[viewModel.index] ??= CodeLineEditingController();
    final prediction = _predictions[viewModel.index] ??= TextEditingController(text: viewModel.typedPrediction);
    final attempt = viewModel.attempt;
    final asked = viewModel.prediction;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${lesson.title} · ${context.localizations.recallScreen_step(viewModel.index + 1, viewModel.items.length)}',
          style: tokens.text.label.copyWith(fontSize: 13, color: context.theme.colors.mutedForeground),
        ),
        const SizedBox(height: 10),
        Text(
          section.emoji == null ? section.title : '${section.emoji} ${section.title}',
          style: tokens.text.h2,
        ),
        const SizedBox(height: 12),
        Text(
          predicting
              ? context.localizations.recallScreen_introPredict
              : context.localizations.recallScreen_intro,
          style: tokens.text.bodySmall.copyWith(fontSize: 16, color: context.theme.colors.mutedForeground),
        ),
        const SizedBox(height: 24),
        LessonProse(markdown: section.prose, fontSize: 19),
        const SizedBox(height: 20),
        if (predicting) ...[
          CodeSample(
            source: section.program ?? '',
            language: viewModel.language,
            label: _status(context),
            style: tokens.text.code.copyWith(color: tokens.colors.codeForeground),
            labelStyle: tokens.text.codeSmall.copyWith(color: tokens.colors.codeMuted),
            surface: tokens.colors.codeBackground,
          ),
          const SizedBox(height: 20),
          PredictionField(
            controller: prediction,
            onChange: viewModel.setPrediction,
            enabled: attempt == null,
          ),
        ] else
          CodeEditorCard(
            controller: editor,
            status: _status(context),
            height: CodeEditorCard.heightForLines(section.kind == SectionKind.quickExercise ? 1 : 6),
            singleLine: section.kind == SectionKind.quickExercise,
          ),
        const SizedBox(height: 16),
        AppButtonRow(
          children: [
            RunButton(
              running: viewModel.running,
              runLabel: predicting
                  ? context.localizations.lessonScreen_predictCheck
                  : context.localizations.lessonScreen_run,
              stopLabel: context.localizations.lessonScreen_stop,
              onRun: predicting
                  ? (viewModel.typedPrediction.trim().isEmpty || attempt != null
                        ? null
                        : () => controller.predict(section, prediction.text))
                  : () => controller.run(section, editor.text),
              onStop: controller.stop,
            ),
            // Always offered, not only once it passes: a refresher measures what
            // was kept and must never become a door the student cannot get
            // through. A miss only brings the lesson round again sooner.
            AppButton(
              tone: AppButtonTone.outline,
              icon: FLucideIcons.chevronRight,
              iconSide: AppButtonIconSide.trailing,
              onPress: controller.next,
              child: Text(context.localizations.lessonScreen_next),
            ),
          ],
        ),
        if (attempt != null) ...[
          const SizedBox(height: 16),
          // The prediction's own verdict, explanation and all: being wrong here
          // costs a rung, never the answer.
          if (predicting && asked != null)
            PredictionVerdict(result: attempt, prediction: asked, explanation: section.explanation)
          else
            OutputPanel(result: attempt),
        ],
      ],
    );
  }

  /// What the card's strip says over the code: a run in progress, or else the
  /// interpreter it will run on.
  String _status(BuildContext context) => viewModel.running
      ? context.localizations.lessonScreen_running
      : controller.runtimeVersion ?? languageLabel(viewModel.language);

  Widget _buildDone(BuildContext context) {
    final tokens = context.appTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('🔁', style: tokens.text.display.copyWith(fontSize: 56)),
        const SizedBox(height: 16),
        Text(context.localizations.recallScreen_done, style: tokens.text.h1),
        const SizedBox(height: 12),
        Text(
          context.localizations.recallScreen_score(viewModel.passed.length, viewModel.items.length),
          style: tokens.text.body.copyWith(fontSize: 18, color: context.theme.colors.mutedForeground),
        ),
        const SizedBox(height: 32),
        AppButtonRow(
          children: [
            AppButton(
              onPress: controller.leave,
              child: Text(context.localizations.lessonScreen_finish(languageLabel(viewModel.language))),
            ),
          ],
        ),
      ],
    );
  }

  /// Opened with nothing due — an old link, or everything already settled.
  Widget _buildEmpty(BuildContext context) {
    final tokens = context.appTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(context.localizations.recallScreen_title, style: tokens.text.h1),
        const SizedBox(height: 12),
        Text(
          context.localizations.recallScreen_empty,
          style: tokens.text.body.copyWith(fontSize: 18, color: context.theme.colors.mutedForeground),
        ),
        const SizedBox(height: 32),
        AppButtonRow(
          children: [
            AppButton(
              onPress: controller.leave,
              child: Text(context.localizations.lessonScreen_finish(languageLabel(viewModel.language))),
            ),
          ],
        ),
      ],
    );
  }

  @override
  void dispose() {
    for (final editor in _editors.values) {
      editor.dispose();
    }
    for (final prediction in _predictions.values) {
      prediction.dispose();
    }
    super.dispose();
  }

}
