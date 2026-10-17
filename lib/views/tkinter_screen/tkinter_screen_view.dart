import 'package:flutter/widgets.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/vm/vm_runtime.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/shape_metrics.dart';
import 'package:i_can_code/views/base/screen_view_base.dart';
import 'package:i_can_code/views/components/app_button.dart';
import 'package:i_can_code/views/components/app_button_row.dart';
import 'package:i_can_code/views/components/app_header.dart';
import 'package:i_can_code/views/components/app_header_publisher.dart';
import 'package:i_can_code/views/components/code_editor_card.dart';
import 'package:i_can_code/views/components/notice_card.dart';
import 'package:i_can_code/views/components/output_card.dart';
import 'package:i_can_code/views/components/run_button.dart';
import 'package:i_can_code/views/tkinter_screen/components/no_window_panel.dart';
import 'package:i_can_code/views/tkinter_screen/components/program_dialog.dart';
import 'package:i_can_code/views/tkinter_screen/components/run_notice.dart';
import 'package:i_can_code/views/tkinter_screen/components/vm_display.dart';
import 'package:i_can_code/views/tkinter_screen/components/vm_load_panel.dart';
import 'package:i_can_code/views/tkinter_screen/components/window_strips.dart';
import 'package:i_can_code/views/tkinter_screen/tkinter_screen_controller.dart';
import 'package:i_can_code/views/tkinter_screen/tkinter_screen_view_model.dart';

/// The Tkinter page: one column with the editor in it, the way the console's
/// page is one column with the terminal in it, and the program's windows in a
/// [ProgramDialog] over it while it runs.
///
/// The windows are a dialog rather than a column beside the editor because a
/// program's window is the size it is: a column wide enough for 800 × 600 left
/// the editor a third of the page and everything on it hard against the left
/// edge, and a column narrow enough to balance the page shrank the program.
///
/// **Nothing on it moves by itself while a program runs.** The emulator shares
/// the page's thread, and the bench measured 6 ms of page work per frame leaving
/// it 3 % of its speed on a slow laptop. So no spinner, no easing and no
/// animated progress here, the dim included; output reaches the card a few times
/// a second rather than on every batch (see
/// [TkinterScreenController.outputInterval]).
class TkinterScreenView extends ScreenViewBase<TkinterScreenViewModel, TkinterScreenController> {

  /// The measure of the page, the other one-column screens' own.
  static const double _pageWidth = 900;

  /// A Tk program is longer than a lesson's answer: the window, the widgets that
  /// go in it and a callback each. So the editor takes the height the window
  /// has, between these bounds, rather than a fixed count that is cramped on a
  /// monitor and taller than the viewport on a small laptop.
  static const int _minEditorLines = 12;
  static const int _maxEditorLines = 26;

  /// What the page spends on everything but the editor: the bar, the heading,
  /// the run row and the page's own padding, plus room to see that something
  /// follows the Run button.
  static const double _chrome = 480;

  /// The dark card the machine's own panel sits on while it loads, which is the
  /// frame's surface without the frame.
  static const double _loadCardHeight = 300;

  /// Builds the platform view the display shows. A widget test passes one of its
  /// own, because `HtmlElementView` cannot be built off the web.
  final VmViewBuilder displayViewBuilder;

  /// Held here so that Run can move the keyboard into the program's window.
  final FocusNode _displayFocus = FocusNode(debugLabel: 'VmDisplay');

  TkinterScreenView({
    required super.viewModel,
    required super.controller,
    required super.contextAccessor,
    this.displayViewBuilder = buildHtmlElementView,
  });

  @override
  Widget get body {
    return AppHeaderPublisher(builder: _buildHeader, child: Builder(builder: _buildContent));
  }

  AppHeaderConfig _buildHeader(BuildContext context) {
    return AppHeaderConfig(
      onTapHome: controller.goHome,
      crumbs: [
        AppCrumb(subjectLabel(viewModel.subject), onTap: controller.goToCatalog),
        AppCrumb(context.localizations.tkinterScreen_crumb),
      ],
    );
  }

  /// The page, and over it the program while one runs. The dialog is built only
  /// then, so the display and its platform view exist for exactly as long as
  /// there is something to show in them.
  ///
  /// The page is left out of the focus tree while the dialog is up, so Tab
  /// leaves the display for the dialog's own cross and then the bar, rather than
  /// for an editor nobody can see or press. It is safe here that the editor is
  /// unfocused by it: the page is rebuilt before the dialog is, so the display's
  /// own request for focus is the last one the frame makes.
  Widget _buildContent(BuildContext context) {
    return Observer(
      builder: (context) {
        final running = viewModel.running;
        return Stack(
          fit: StackFit.expand,
          children: [
            ExcludeFocus(excluding: running, child: _buildPage()),
            if (running) _buildDialog(context),
          ],
        );
      },
    );
  }

  Widget _buildPage() {
    return Builder(
      builder: (context) => SingleChildScrollView(
        // Clear of the bar, which is drawn over the page rather than above it.
        padding: const EdgeInsets.fromLTRB(32, AppHeader.height + 40, 32, 60),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _pageWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeading(context),
                const SizedBox(height: 24),
                _buildEditor(lines: _editorLinesFor(context)),
                const SizedBox(height: 12),
                _buildRunRow(),
                _buildMachine(),
                _buildRunReport(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeading(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(context.localizations.tkinterScreen_title, style: context.appTheme.text.h1.copyWith(fontSize: 42)),
        const SizedBox(height: 8),
        Text(
          context.localizations.tkinterScreen_subtitle,
          style: context.appTheme.text.body.copyWith(fontSize: 19, color: context.theme.colors.mutedForeground),
        ),
      ],
    );
  }

  /// How many lines of editor the window has room for, once [_chrome] logical
  /// pixels are spent on everything else.
  int _editorLinesFor(BuildContext context) {
    // heightForLines carries the card's own padding, so a line on its own is
    // not what a line adds: the difference between two is.
    final lineHeight = CodeEditorCard.heightForLines(2) - CodeEditorCard.heightForLines(1);
    final padding = CodeEditorCard.heightForLines(1) - lineHeight;
    final room = MediaQuery.sizeOf(context).height - _chrome - padding;
    return (room / lineHeight).floor().clamp(_minEditorLines, _maxEditorLines);
  }

  /// Open from the first frame, the download included: writing the program is
  /// what a student does while the machine arrives. It does not take the
  /// keyboard by itself: Tab indents in it, so a keyboard user who starts there
  /// has to leave it before reaching the rest of the page.
  Widget _buildEditor({required int lines}) {
    return Observer(
      builder: (context) => CodeEditorCard(
        controller: viewModel.code,
        status: _statusLabel(context),
        height: CodeEditorCard.heightForLines(lines),
        autofocus: false,
      ),
    );
  }

  Widget _buildRunRow() {
    return Observer(
      builder: (context) => AppButtonRow(
        children: [
          RunButton(
            running: viewModel.running,
            runLabel: context.localizations.tkinterScreen_run,
            stopLabel: context.localizations.tkinterScreen_stop,
            onRun: viewModel.canRun ? _run : null,
            onStop: controller.stop,
          ),
        ],
      ),
    );
  }

  /// Runs, and hands the keyboard to the program's window, which is where the
  /// next thing typed is meant to go. The display is built with the dialog, a
  /// frame later, and a node asked for focus before it is in the tree takes it
  /// as it arrives.
  void _run() {
    controller.run();
    _displayFocus.requestFocus();
  }

  /// The strip over the editor: what the machine is doing, and once it is ready,
  /// what it runs.
  String _statusLabel(BuildContext context) {
    final l10n = context.localizations;
    final machine = viewModel.machine;

    if (viewModel.running) {
      return machine == TkinterMachine.ready ? l10n.tkinterScreen_statusRunning : l10n.tkinterScreen_statusWaiting;
    }

    final progress = viewModel.loadProgress;
    return switch (machine) {
      TkinterMachine.loading when progress != null && progress.downloaded => l10n.tkinterScreen_statusStarting,
      TkinterMachine.loading => l10n.tkinterScreen_statusLoading,
      // The machine names itself; until it has, the subject stands in.
      TkinterMachine.ready => viewModel.interpreterLabel ?? subjectLabel(viewModel.subject),
      TkinterMachine.failed || TkinterMachine.unavailable || TkinterMachine.notIncluded =>
        subjectLabel(viewModel.subject),
    };
  }

  /// What the machine has to say for itself on the page: the download while it
  /// runs, and what broke where it did. Nothing at all once it is ready, and
  /// nothing while a program runs, which the dialog is showing.
  Widget _buildMachine() {
    return Observer(
      builder: (context) {
        if (viewModel.running) return const SizedBox.shrink();

        final Widget? card = switch (viewModel.machine) {
          TkinterMachine.ready => null,
          TkinterMachine.loading => _buildLoadCard(context),
          // Said rather than hidden: a page that silently is not there reads as
          // a broken app.
          TkinterMachine.unavailable => NoticeCard(
            title: context.localizations.tkinterScreen_unavailableTitle,
            body: context.localizations.tkinterScreen_unavailableBody,
          ),
          TkinterMachine.notIncluded => NoticeCard(
            title: context.localizations.tkinterScreen_notIncludedTitle,
            body: context.localizations.tkinterScreen_notIncludedBody,
          ),
          TkinterMachine.failed => _buildFailure(context),
        };
        if (card == null) return const SizedBox.shrink();

        return Padding(padding: const EdgeInsets.only(top: 20), child: card);
      },
    );
  }

  /// The machine's own panel on the surface the frame would have given it, so
  /// the download reads as part of the machine rather than as a page of its own.
  Widget _buildLoadCard(BuildContext context) {
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: context.appTheme.colors.codeBackground,
        shape: squircle(kCardCornerRadius),
      ),
      child: SizedBox(height: _loadCardHeight, child: VmLoadPanel(progress: viewModel.loadProgress)),
    );
  }

  /// The program while it runs: its windows, the way out of them, and the cross
  /// that ends it.
  ///
  /// The dialog is what a run looks like, so it is up while the machine is
  /// still loading too: a Run pressed during the download waits, and this says
  /// what for.
  Widget _buildDialog(BuildContext context) {
    final l10n = context.localizations;
    final window = viewModel.framedWindow;
    final title = switch (window) {
      null => l10n.tkinterScreen_programTitle,
      VmWindow(title: '') => l10n.tkinterScreen_windowUntitled,
      VmWindow(:final title) => title,
    };
    final focused = viewModel.displayFocused;
    final ready = viewModel.machine == TkinterMachine.ready;
    final region = ready ? viewModel.shownRegion : null;
    // Read here, in the Observer's build: the frame's builder runs at layout.
    final progress = viewModel.loadProgress;
    final background = context.appTheme.colors.codeBackground;
    final noWindow = l10n.tkinterScreen_noWindowBody;
    final labelled = viewModel.labelledWindows;

    return ProgramDialog(
      title: title,
      stopLabel: l10n.tkinterScreen_stopProgram,
      onStop: controller.stop,
      hint: focused ? l10n.tkinterScreen_leaveHint : null,
      focused: focused,
      region: region?.size,
      builder: (context, box, scale) {
        if (!ready) return VmLoadPanel(progress: progress);

        return Stack(
          fit: StackFit.expand,
          children: [
            VmDisplay(
              // Global, so a display that is rebuilt into another place in the
              // tree keeps its platform view rather than building a second one.
              // A retry builds a new machine, and its screen is a new view.
              key: GlobalObjectKey(controller.display),
              binding: controller.display,
              region: region ?? Offset.zero & box,
              scale: scale,
              focusNode: _displayFocus,
              semanticsLabel: title,
              background: background,
              onFocusChange: controller.onDisplayFocusChange,
              viewBuilder: displayViewBuilder,
            ),
            // A press on it still reaches the display beneath and takes the
            // keyboard, as a press on the empty screen did.
            if (region == null) IgnorePointer(child: NoWindowPanel(text: noWindow)),
            if (region != null && labelled.isNotEmpty)
              WindowStrips(
                windows: labelled,
                region: region,
                scale: scale,
                closeLabel: l10n.tkinterScreen_close,
                untitledLabel: l10n.tkinterScreen_windowUntitled,
                onClose: controller.closeWindowById,
              ),
          ],
        );
      },
    );
  }

  /// Worded for what broke. None of it is the student's doing, and every one of
  /// them says so. The machine's own message is English and for whoever helps,
  /// so it stays folded under the card.
  Widget _buildFailure(BuildContext context) {
    final l10n = context.localizations;
    final message = viewModel.failureMessage;

    final (title, body) = switch (viewModel.failure) {
      VmFailure.network || VmFailure.fetch => (
        l10n.tkinterScreen_downloadFailedTitle,
        l10n.tkinterScreen_downloadFailedBody,
      ),
      VmFailure.incompatible => (l10n.tkinterScreen_incompatibleTitle, l10n.tkinterScreen_incompatibleBody),
      VmFailure.replaced => (l10n.tkinterScreen_replacedTitle, l10n.tkinterScreen_replacedBody),
      VmFailure.unresponsive || VmFailure.broken || null => (
        l10n.tkinterScreen_brokenTitle,
        l10n.tkinterScreen_brokenBody,
      ),
    };

    return NoticeCard(
      title: title,
      body: body,
      detail: message == null || message.isEmpty ? null : message,
      detailLabel: l10n.tkinterScreen_failureDetails,
      action: AppButton(
        tone: AppButtonTone.neutral,
        onPress: controller.retry,
        child: Text(l10n.tkinterScreen_retry),
      ),
    );
  }

  /// What to know about the last run, then what it printed.
  Widget _buildRunReport() {
    return Observer(
      builder: (context) {
        final notices = viewModel.notices;
        final output = viewModel.visibleOutput;
        final incomplete = viewModel.outputIncomplete;
        // Only the end fits on the card; the ellipsis says the start is missing.
        final clipped = output.length < viewModel.output.length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final notice in notices) ...[
              const SizedBox(height: 16),
              RunNotice(text: _noticeText(context, notice), aboutTheProgram: notice.aboutTheProgram),
            ],
            if (output.trim().isNotEmpty) ...[
              const SizedBox(height: 16),
              OutputCard(
                label: context.localizations.tkinterScreen_output,
                // print() ends every line with a newline, which would otherwise
                // leave a blank line inside the card.
                text: '${clipped ? '…\n' : ''}${output.trimRight()}',
                note: incomplete ? context.localizations.tkinterScreen_truncated : null,
              ),
            ],
          ],
        );
      },
    );
  }

  static String _noticeText(BuildContext context, TkinterNotice notice) {
    final l10n = context.localizations;

    return switch (notice) {
      TkinterNotice.noMainloop => l10n.tkinterScreen_noMainloop,
      TkinterNotice.noInput => l10n.tkinterScreen_noInput,
      TkinterNotice.crashed => l10n.tkinterScreen_crashed,
      TkinterNotice.outOfMemory => l10n.tkinterScreen_outOfMemory,
      TkinterNotice.tooLarge => l10n.tkinterScreen_tooLarge(vmScreenSize.width.toInt(), vmScreenSize.height.toInt()),
      TkinterNotice.harnessBroken => l10n.tkinterScreen_harnessBroken,
      TkinterNotice.harnessFetch => l10n.tkinterScreen_harnessFetch,
      TkinterNotice.harnessUnresponsive => l10n.tkinterScreen_harnessUnresponsive,
    };
  }

  @override
  void dispose() {
    _displayFocus.dispose();
    super.dispose();
  }

}
