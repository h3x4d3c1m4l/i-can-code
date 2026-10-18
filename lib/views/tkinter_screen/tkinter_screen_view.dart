import 'package:flutter/widgets.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/views/base/screen_view_base.dart';
import 'package:i_can_code/views/components/app_button_row.dart';
import 'package:i_can_code/views/components/app_header.dart';
import 'package:i_can_code/views/components/app_header_publisher.dart';
import 'package:i_can_code/views/components/code_editor_card.dart';
import 'package:i_can_code/views/components/run_button.dart';
import 'package:i_can_code/views/components/vm/vm_display.dart';
import 'package:i_can_code/views/components/vm/vm_machine_card.dart';
import 'package:i_can_code/views/components/vm/vm_run_dialog.dart';
import 'package:i_can_code/views/components/vm/vm_run_report.dart';
import 'package:i_can_code/views/components/vm/vm_session_controller.dart';
import 'package:i_can_code/views/components/vm/vm_status_label.dart';
import 'package:i_can_code/views/tkinter_screen/tkinter_screen_controller.dart';
import 'package:i_can_code/views/tkinter_screen/tkinter_screen_view_model.dart';

/// The Tkinter page: one column with the editor in it, the way the console's
/// page is one column with the terminal in it, and the program's windows in a
/// [VmRunDialog] over it while it runs.
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
/// [VmSessionController.outputInterval]).
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
        final running = viewModel.machine.running;
        return Stack(
          fit: StackFit.expand,
          children: [
            ExcludeFocus(excluding: running, child: _buildPage()),
            if (running)
              VmRunDialog(
                session: viewModel.machine,
                controller: controller.machine,
                focusNode: _displayFocus,
                viewBuilder: displayViewBuilder,
              ),
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
                VmMachineCard(
                  session: viewModel.machine,
                  onRetry: controller.machine.retry,
                  notIncludedBody: context.localizations.tkinterScreen_notIncludedBody,
                  unavailableBody: context.localizations.tkinterScreen_unavailableBody,
                ),
                VmRunReport(session: viewModel.machine),
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
        controller: viewModel.machine.code,
        status: vmStatusLabel(context.localizations, viewModel.machine),
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
            running: viewModel.machine.running,
            runLabel: context.localizations.tkinterScreen_run,
            stopLabel: context.localizations.tkinterScreen_stop,
            onRun: viewModel.machine.canRun ? _run : null,
            onStop: controller.machine.stop,
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

  @override
  void dispose() {
    _displayFocus.dispose();
    super.dispose();
  }

}
