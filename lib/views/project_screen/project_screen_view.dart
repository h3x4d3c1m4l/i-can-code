import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/rendering.dart';
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
import 'package:i_can_code/views/components/code_editor_card.dart';
import 'package:i_can_code/views/components/lesson/collapsible_prose_group.dart';
import 'package:i_can_code/views/components/lesson/confetti_burst.dart';
import 'package:i_can_code/views/components/lesson/lesson_complete_panel.dart';
import 'package:i_can_code/views/components/lesson/lesson_prose.dart';
import 'package:i_can_code/views/components/lesson/optional_step_banner.dart';
import 'package:i_can_code/views/components/lesson/step_progress_bar.dart';
import 'package:i_can_code/views/components/microbit/microbit_board_summary.dart';
import 'package:i_can_code/views/components/microbit/microbit_session_view_model.dart';
import 'package:i_can_code/views/components/repl_terminal.dart';
import 'package:i_can_code/views/project_screen/components/connect_dialog.dart';
import 'package:i_can_code/views/project_screen/components/done_when_card.dart';
import 'package:i_can_code/views/project_screen/components/project_block.dart';
import 'package:i_can_code/views/project_screen/components/requirements_row.dart';
import 'package:i_can_code/views/project_screen/components/snapshot_dialog.dart';
import 'package:i_can_code/views/project_screen/project_screen_controller.dart';
import 'package:i_can_code/views/project_screen/project_screen_view_model.dart';

class ProjectScreenView extends ScreenViewBase<ProjectScreenViewModel, ProjectScreenController> {

  /// The width the prose reserves for a subheading's chevron. See
  /// `LessonScreenView._gutter`, which this follows.
  static const double _gutter = CollapsibleProseGroup.gutter;

  /// Wider than a lesson's task step: the editor holds a whole program here,
  /// not an answer of a few lines.
  static const double _pageWidth = 1320 + _gutter;

  static const EdgeInsets _padding = EdgeInsets.fromLTRB(32 - _gutter, AppHeader.height + 44, 32, 40);

  static const double _proseSize = 19;


  /// Below this height the editor, the buttons and the output no longer fit
  /// one window side by side with the prose, so the page stacks.
  static const double _minSplitHeight = 640;

  /// How far below the top of the window a revealed block's top lands: clear
  /// of the bar, with room to breathe.
  static const double _revealTop = AppHeader.height + 24;

  /// The room left under a revealed block.
  static const double _revealBottom = 24;

  static Widget _pastGutter(Widget child) => Padding(padding: const EdgeInsets.only(left: _gutter), child: child);

  /// One per section, for scrolling to it. A [GlobalKey] is safe here: unlike
  /// the lesson screen, nothing keeps an outgoing copy of the page mounted.
  final Map<int, GlobalKey> _blockKeys = {};

  /// The end of the project, for scrolling to it once it appears.
  final GlobalKey _completeKey = GlobalKey();

  ProjectScreenView({required super.viewModel, required super.controller, required super.contextAccessor});

  @override
  Widget get body {
    return Stack(
      fit: StackFit.expand,
      children: [
        AppHeaderPublisher(builder: _buildHeader, child: Builder(builder: _buildPage)),
        Positioned.fill(
          child: IgnorePointer(
            child: Observer(
              builder: (context) => Stack(
                fit: StackFit.expand,
                children: [
                  if (viewModel.passBursts > 0) ConfettiBurst.small(key: ValueKey(('pass', viewModel.passBursts))),
                  if (viewModel.current == null && viewModel.earnedCelebration) const ConfettiBurst(),
                  for (var i = math.max(1, viewModel.extraBursts - 2); i <= viewModel.extraBursts; i++)
                    ConfettiBurst(key: ValueKey(('extra', i))),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// The trail and nothing more. The sections on the page already say where the
  /// student is, so a progress bar here would say it twice.
  AppHeaderConfig _buildHeader(BuildContext context) {
    final lesson = viewModel.lesson.forLocale(Localizations.localeOf(context).languageCode);

    return AppHeaderConfig(
      onTapHome: controller.leave,
      crumbs: [
        AppCrumb(subjectLabel(viewModel.lesson.entry.subject), onTap: controller.openSubject),
        if (lesson.group case final String group) AppCrumb(group),
        AppCrumb(lesson.title),
      ],
      offersZen: true,
    );
  }

  /// MUST NOT be wrapped in a [LayoutBuilder], for the reason
  /// `LessonScreenView._buildExercise` gives.
  Widget _buildPage(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final stacked = size.width < context.theme.breakpoints.lg || size.height < _minSplitHeight;

    if (stacked) {
      return SingleChildScrollView(
        padding: _padding,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _pageWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Observer(builder: _buildTasks),
                const SizedBox(height: 36),
                // Inside the page's scroll view, where a terminal never sees the
                // space bar. Nothing in a project types into the board, so that
                // is a cost worth paying on a narrow window.
                _pastGutter(_buildWorkspace(context, editorHeight: 340, outputHeight: 240)),
              ],
            ),
          ),
        ),
      );
    }

    final vertical = EdgeInsets.only(top: _padding.top, bottom: _padding.bottom);
    // Half the window for the program, and never so much that the buttons and
    // the output are pushed off it.
    final editorHeight = math.min(size.height * 0.5, math.max(200, size.height - 460)).toDouble();

    return Padding(
      padding: EdgeInsets.only(left: _padding.left, right: _padding.right),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _pageWidth),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The tasks scroll; the program stands still beside them.
              Expanded(
                child: SingleChildScrollView(padding: vertical, child: Observer(builder: _buildTasks)),
              ),
              const SizedBox(width: 36),
              Expanded(
                child: Padding(
                  padding: vertical,
                  child: _buildWorkspace(context, editorHeight: editorHeight),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Everything on the left: the project, and every section of it as a block.
  Widget _buildTasks(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    final lesson = viewModel.lesson.forLocale(locale);
    final sections = lesson.sections;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _pastGutter(_buildTitle(context, lesson)),
        const SizedBox(height: 40),
        for (final (index, section) in sections.indexed) ...[
          if (index > 0) const SizedBox(height: 12),
          _pastGutter(_buildBlock(context, section, index, locale)),
        ],
        if (viewModel.current == null) ...[
          const SizedBox(height: 56),
          _pastGutter(KeyedSubtree(key: _completeKey, child: _buildComplete(context, lesson))),
        ],
      ],
    );
  }

  Widget _buildTitle(BuildContext context, Lesson lesson) {
    final subtitle = lesson.subtitle;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          [?lesson.emoji, lesson.title].join(' '),
          style: context.appTheme.text.h1.copyWith(fontSize: 42),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: context.appTheme.text.body.copyWith(fontSize: 19, color: context.theme.colors.mutedForeground),
          ),
        ],
      ],
    );
  }

  Widget _buildBlock(BuildContext context, LessonSection section, int index, String locale) {
    final current = viewModel.current;
    final state = switch (index) {
      _ when viewModel.passed.contains(index) => BlockState.finished,
      _ when index == current => BlockState.current,
      _ when current == null || index < current => BlockState.skipped,
      _ => BlockState.upcoming,
    };
    final open = viewModel.open == index;
    final snapshot = state == BlockState.finished && section.kind == SectionKind.task
        ? controller.snapshotOf(section)
        : null;

    return ProjectBlock(
      key: _blockKeys[index] ??= GlobalKey(),
      number: index + 1,
      title: section.title,
      state: state,
      open: open,
      onToggle: state == BlockState.upcoming ? null : () => _toggle(index),
      trailing: snapshot == null ? null : _buildViewCode(context, section, snapshot),
      // Built for every block that can open, so one that is closing still has
      // something to fold away. It only reaches the tree while it shows.
      child: state == BlockState.upcoming
          ? const SizedBox.shrink()
          : _buildBlockContent(context, section, index, locale, state),
    );
  }

  /// A section, opened. Only the one in front of the student carries the
  /// button that finishes it.
  Widget _buildBlockContent(BuildContext context, LessonSection section, int index, String locale, BlockState state) {
    final requirements = controller.requirementsOf(section, locale);
    final doneWhen = section.doneWhen;
    final current = state == BlockState.current;
    // The prose hangs a subheading's chevron into the gutter left of the text,
    // so it starts that much short of the title; everything else lines up with
    // the title itself.
    Widget inset(Widget child) => Padding(padding: const EdgeInsets.only(left: ProjectBlock.titleInset), child: child);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (current && section.optional) ...[
          inset(OptionalStepBanner(onSkip: () => _skip(index))),
          const SizedBox(height: 16),
        ],
        if (requirements.isNotEmpty) ...[
          inset(RequirementsRow(requirements: requirements, onOpen: controller.openRequirement)),
          const SizedBox(height: 18),
        ],
        Padding(
          padding: const EdgeInsets.only(left: ProjectBlock.titleInset - _gutter),
          child: LessonProse(markdown: section.prose, fontSize: _proseSize, hangingGutter: true),
        ),
        if (doneWhen != null) ...[
          const SizedBox(height: 24),
          inset(DoneWhenCard(text: doneWhen, action: current ? _buildWorks(context, index) : null)),
        ] else if (current) ...[
          const SizedBox(height: 24),
          inset(
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: AppButton(
                icon: FLucideIcons.check,
                onPress: () => _finish(index),
                child: Text(context.localizations.projectScreen_read),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildViewCode(BuildContext context, LessonSection section, String snapshot) {
    return FTappable(
      semanticsButton: true,
      onPress: () => _openSnapshot(context, section, snapshot),
      builder: (context, states, _) => Text(
        context.localizations.projectScreen_viewCode,
        style: context.appTheme.text.bodySmall.copyWith(
          color: context.appTheme.colors.link,
          decoration: states.contains(FTappableVariant.hovered) ? TextDecoration.underline : null,
        ),
      ),
    );
  }

  /// "Het werkt!", waiting for the program to have been on the board while
  /// this task was open.
  Widget _buildWorks(BuildContext context, int task) {
    final ready = viewModel.flashedHere;

    return Wrap(
      spacing: 16,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        AppButton(
          icon: FLucideIcons.check,
          onPress: ready ? () => _finish(task) : null,
          child: Text(context.localizations.projectScreen_done),
        ),
        if (!ready)
          Text(
            context.localizations.projectScreen_flashFirst,
            style: context.appTheme.text.bodySmall.copyWith(color: context.theme.colors.mutedForeground),
          ),
      ],
    );
  }

  Widget _buildComplete(BuildContext context, Lesson lesson) {
    final next = viewModel.nextLesson?.forLocale(Localizations.localeOf(context).languageCode);

    return LessonCompletePanel(
      emoji: lesson.emoji,
      title: lesson.title,
      completedSteps: viewModel.passed.length,
      stepCount: lesson.stepCount,
      nextLesson: next,
      onNextLesson: next == null ? null : controller.openNextLesson,
      onMoreConfetti: viewModel.earnedCelebration ? controller.moreConfetti : null,
      onBack: () => _openAndReveal(lesson.stepCount - 1),
      backLabel: context.localizations.lessonScreen_back,
      backTip: StepProgressBar.tipFor(lesson.stepCount - 1, lesson.sections.last.title),
      onLeave: controller.openSubject,
      leaveLabel: context.localizations.lessonScreen_finish(subjectLabel(viewModel.lesson.entry.subject)),
    );
  }

  /// The right-hand column: the program, the buttons that put it on the board,
  /// and what the board says back.
  ///
  /// [outputHeight] null lets the output take what is left of the column,
  /// which is only possible where the column is not inside a scroll view.
  Widget _buildWorkspace(BuildContext context, {required double editorHeight, double? outputHeight}) {
    final output = Observer(builder: _buildOutput);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Observer(
          builder: (context) => CodeEditorCard(
            controller: viewModel.board.code,
            status: _editorStatus(context),
            height: editorHeight,
            autofocus: false,
            // No reset: the program is every task's work so far, and a
            // finished task's snapshot is the way back.
          ),
        ),
        const SizedBox(height: 12),
        Observer(builder: _buildBoardButtons),
        const SizedBox(height: 16),
        if (outputHeight == null) Expanded(child: output) else SizedBox(height: outputHeight, child: output),
      ],
    );
  }

  /// Writing to the board is always offered. Without one it asks for one
  /// first, which is when a missing board matters, rather than holding a
  /// panel about it on the page the whole time.
  Widget _buildBoardButtons(BuildContext context) {
    final board = viewModel.board;
    final flashing = board.status == MicrobitStatus.flashing;
    final connected = board.status == MicrobitStatus.connected;
    final measured = flashing && board.flashProgress > 0;

    return AppButtonRow(
      children: [
        AppButton(
          icon: FLucideIcons.zap,
          busy: flashing && !measured,
          progress: measured ? board.flashProgress : null,
          onPress: flashing ? null : (connected ? controller.board.flash : () => _connectThenFlash(context)),
          child: Text(context.localizations.microbitScreen_flash),
        ),
        AppButton(
          tone: AppButtonTone.neutral,
          icon: FLucideIcons.rotateCcw,
          onPress: connected ? controller.board.restart : null,
          child: Text(context.localizations.microbitScreen_restart),
        ),
      ],
    );
  }

  /// What the board prints, under a line saying which board that is.
  Widget _buildOutput(BuildContext context) {
    final board = viewModel.board;
    final device = board.devices.firstOrNull;
    final open = board.status == MicrobitStatus.connected || board.status == MicrobitStatus.flashing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(context.localizations.projectScreen_output, style: context.appTheme.text.label)),
            if (open && device != null)
              MicrobitBoardSummary(device: device, info: board.boardInfo)
            else
              Text(
                context.localizations.projectScreen_notConnected,
                style: context.appTheme.text.bodySmall.copyWith(color: context.theme.colors.mutedForeground),
              ),
          ],
        ),
        const SizedBox(height: 8),
        // The editor has the keyboard in a project; the output is read.
        Expanded(child: ReplTerminal(terminal: board.terminal, autofocus: false)),
      ],
    );
  }

  /// The strip over the editor, which says what the board is doing.
  String _editorStatus(BuildContext context) {
    final l10n = context.localizations;
    final board = viewModel.board;
    final percent = (board.flashProgress * 100).round();
    final plan = board.flashPlan;

    return switch (board.status) {
      MicrobitStatus.flashing when plan != null => l10n.microbitScreen_flashingPages(percent, plan.changed, plan.total),
      MicrobitStatus.flashing when board.flashPlanFailure != null => l10n.microbitScreen_flashingPagesUnknown(percent),
      MicrobitStatus.flashing => l10n.microbitScreen_flashing(percent),
      _ => l10n.microbitScreen_flashHint,
    };
  }

  /// Asks for a board, and writes the program to it once there is one.
  Future<void> _connectThenFlash(BuildContext context) async {
    final connected = await showConnectDialog(
      context,
      board: viewModel.board,
      onConnect: controller.board.connect,
    );
    if (connected) await controller.board.flash();
  }

  Future<void> _finish(int index) async {
    await controller.finish(index);
    _revealAfterFold();
  }

  void _skip(int index) {
    controller.skip(index);
    _revealAfterFold();
  }

  void _toggle(int index) {
    viewModel.toggle(index);
    _revealAfterFold();
  }

  /// Opens the block at [index], unless it already is, and brings it into view.
  void _openAndReveal(int index) {
    if (viewModel.open == index) {
      _revealAfterFold();
    } else {
      _toggle(index);
    }
  }

  /// Brings the block that is open, or the end of the project, into view once
  /// the blocks have finished folding.
  ///
  /// Not straight away: a block that is still opening is only as tall as it has
  /// got so far, so revealing it then leaves the rest of it below the window.
  void _revealAfterFold() {
    final context = contextAccessor.buildContext;
    if (!context.mounted) return;

    unawaited(
      Future<void>.delayed(context.motion(ProjectBlock.duration), () async {
        // After the frame that finished the fold, which this also asks for:
        // a post-frame callback alone waits for a frame nobody may schedule.
        await WidgetsBinding.instance.endOfFrame;

        final open = viewModel.open;
        final key = open != null ? _blockKeys[open] : (viewModel.current == null ? _completeKey : null);
        if (key != null) _reveal(key);
      }),
    );
  }

  /// Scrolls just far enough to show all of [key]'s widget, or, when it is
  /// taller than the window, its top.
  ///
  /// Its top counts as shown only below the bar, which may be drawn over the
  /// top of the page.
  void _reveal(GlobalKey key) {
    final context = key.currentContext;
    final object = context?.findRenderObject();
    if (context == null || !context.mounted || object == null) return;

    final viewport = RenderAbstractViewport.maybeOf(object);
    final position = Scrollable.maybeOf(context)?.position;
    if (viewport == null || position == null) return;

    final top = viewport.getOffsetToReveal(object, 0).offset - _revealTop;
    final bottom = viewport.getOffsetToReveal(object, 1).offset + _revealBottom;
    final now = position.pixels;
    // Up to its top when that is out of view; otherwise down until its bottom
    // shows, but never so far that its top goes under the bar.
    final target = (top < now ? top : math.min(math.max(now, bottom), top)).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((target - now).abs() < 1) return;

    unawaited(
      position.animateTo(
        target,
        duration: context.motion(const Duration(milliseconds: 350)),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  Future<void> _openSnapshot(BuildContext context, LessonSection section, String code) async {
    final restore = await showSnapshotDialog(
      context,
      task: section.title,
      code: code,
      language: viewModel.lesson.entry.subject,
    );
    if (restore) controller.restore(code);
  }

}
