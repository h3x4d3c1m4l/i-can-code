import 'dart:math';

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
import 'package:i_can_code/views/components/notice_card.dart';
import 'package:i_can_code/views/components/repl_terminal.dart';
import 'package:i_can_code/views/components/run_button.dart';
import 'package:i_can_code/views/program_screen/program_screen_controller.dart';
import 'package:i_can_code/views/program_screen/program_screen_view_model.dart';

/// The micro:bit program page without the board: the editor, Run, and a
/// terminal under them that the program prints to and reads from.
///
/// **The terminal is not inside a scroll view**, for the reason the micro:bit
/// page gives: a scrollable takes the space bar before the terminal sees it. So
/// the page fits the window, and the editor and the terminal share what the
/// heading leaves: side by side from `lg`, as a lesson's two-column step is,
/// and one above the other below it. Stacked on a 13-inch laptop the terminal
/// kept four lines.
class ProgramScreenView extends ScreenViewBase<ProgramScreenViewModel, ProgramScreenController> {

  static const double _pageWidth = 1100;

  static const int _minEditorLines = 4;

  /// Stacked, the editor's part of the height under the heading. The rest is
  /// the run row and the terminal, which is where the program's answers appear.
  static const double _stackedEditorShare = 0.45;

  /// Side by side, what the editor's column keeps under the editing area: the
  /// strip over it, the gap and the run row, measured at 103 with the app's
  /// fonts, and room for a larger text size.
  static const double _besideEditor = 140;

  /// Held here so that Run can hand the keyboard to the terminal, which is where
  /// the answer to an `input()` is typed.
  final FocusNode _terminalFocus = FocusNode(debugLabel: 'ProgramTerminal');

  ProgramScreenView({required super.viewModel, required super.controller, required super.contextAccessor});

  @override
  Widget get body {
    return AppHeaderPublisher(builder: _buildHeader, child: Builder(builder: _buildContent));
  }

  AppHeaderConfig _buildHeader(BuildContext context) {
    return AppHeaderConfig(
      onTapHome: controller.goHome,
      crumbs: [
        AppCrumb(subjectLabel(viewModel.subject), onTap: controller.goToCatalog),
        AppCrumb(context.localizations.programScreen_crumb),
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    return Observer(
      builder: (context) => switch (viewModel.status) {
        ProgramStatus.unavailable => _buildUnavailable(context),
        _ => _buildSession(context),
      },
    );
  }

  Widget _buildSession(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, AppHeader.height + 40, 32, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _pageWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeading(context),
              const SizedBox(height: 20),
              Text(
                context.localizations.programScreen_hint,
                style: context.appTheme.text.bodySmall.copyWith(color: context.theme.colors.mutedForeground),
              ),
              const SizedBox(height: 16),
              // Measured rather than estimated from the window, because the
              // heading and the hint wrap at a width and text size of their own.
              // Nothing in the builder reads an observable; the parts that do
              // are Observers of their own.
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => MediaQuery.sizeOf(context).width < context.theme.breakpoints.lg
                      ? _buildStacked(constraints.maxHeight)
                      : _buildSideBySide(constraints.maxHeight),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStacked(double height) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildEditor(lines: _linesFor(height * _stackedEditorShare)),
        const SizedBox(height: 12),
        _buildRunRow(),
        const SizedBox(height: 16),
        Expanded(child: _buildTerminal()),
      ],
    );
  }

  Widget _buildSideBySide(double height) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildEditor(lines: _linesFor(height - _besideEditor)),
              const SizedBox(height: 12),
              _buildRunRow(),
            ],
          ),
        ),
        const SizedBox(width: 24),
        Expanded(child: _buildTerminal()),
      ],
    );
  }

  Widget _buildTerminal() {
    return ReplTerminal(
      terminal: viewModel.terminal,
      focusNode: _terminalFocus,
      // The editor has the keyboard when the page opens.
      autofocus: false,
      // The line editor takes Ctrl+A to the start of the line.
      passesCtrlA: true,
    );
  }

  /// Everything there is to say where no program can run here.
  Widget _buildUnavailable(BuildContext context) {
    return SingleChildScrollView(
      // Clear of the bar on the first screenful, and under it after that.
      padding: const EdgeInsets.fromLTRB(32, AppHeader.height + 40, 32, 60),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeading(context),
              const SizedBox(height: 28),
              NoticeCard(
                title: context.localizations.programScreen_unavailableTitle,
                body: context.localizations.programScreen_unavailableBody,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeading(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(context.localizations.programScreen_title, style: context.appTheme.text.h1.copyWith(fontSize: 42)),
        const SizedBox(height: 8),
        Text(
          context.localizations.programScreen_subtitle,
          style: context.appTheme.text.body.copyWith(fontSize: 19, color: context.theme.colors.mutedForeground),
        ),
      ],
    );
  }

  /// How many lines of editor fit in an editing area of [height].
  int _linesFor(double height) {
    // heightForLines carries the card's own padding, so a line on its own is
    // not what a line adds: the difference between two is.
    final lineHeight = CodeEditorCard.heightForLines(2) - CodeEditorCard.heightForLines(1);
    final padding = CodeEditorCard.heightForLines(1) - lineHeight;
    return max(_minEditorLines, ((height - padding) / lineHeight).floor());
  }

  Widget _buildEditor({required int lines}) {
    return Observer(
      builder: (context) => CodeEditorCard(
        controller: viewModel.code,
        status: _editorStatus(context),
        height: CodeEditorCard.heightForLines(lines),
      ),
    );
  }

  /// The strip over the editor: what the interpreter is doing, or its name.
  String _editorStatus(BuildContext context) {
    return switch (viewModel.status) {
      ProgramStatus.starting => context.localizations.programScreen_statusStarting,
      ProgramStatus.running => context.localizations.programScreen_statusRunning,
      _ => viewModel.runtimeVersion ?? subjectLabel(viewModel.subject),
    };
  }

  Widget _buildRunRow() {
    return Observer(
      builder: (context) => AppButtonRow(
        children: [
          RunButton(
            running: viewModel.busy,
            runLabel: context.localizations.programScreen_run,
            stopLabel: context.localizations.programScreen_stop,
            onRun: _run,
            onStop: controller.stop,
          ),
        ],
      ),
    );
  }

  /// Runs, and hands the keyboard to the terminal, where the next thing typed
  /// is meant to go.
  void _run() {
    controller.run();
    _terminalFocus.requestFocus();
  }

  @override
  void dispose() {
    _terminalFocus.dispose();
    super.dispose();
  }

}
