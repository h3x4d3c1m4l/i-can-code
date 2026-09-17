import 'package:flutter/widgets.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/views/base/screen_view_base.dart';
import 'package:i_can_code/views/components/app_button.dart';
import 'package:i_can_code/views/components/app_button_row.dart';
import 'package:i_can_code/views/components/app_header.dart';
import 'package:i_can_code/views/components/app_header_publisher.dart';
import 'package:i_can_code/views/components/code_editor_card.dart';
import 'package:i_can_code/views/components/microbit/microbit_board_summary.dart';
import 'package:i_can_code/views/components/microbit/microbit_session_controller.dart';
import 'package:i_can_code/views/components/microbit/microbit_session_view_model.dart';
import 'package:i_can_code/views/components/microbit/microbit_state_panel.dart';
import 'package:i_can_code/views/components/repl_terminal.dart';

class MicrobitProgramScreenView extends ScreenViewBase<MicrobitSessionViewModel, MicrobitSessionController> {

  const MicrobitProgramScreenView({required super.viewModel, required super.controller, required super.contextAccessor});

  @override
  Widget get body {
    return AppHeaderPublisher(builder: _buildHeader, child: _buildContent());
  }

  AppHeaderConfig _buildHeader(BuildContext context) {
    return AppHeaderConfig(
      onTapHome: controller.goHome,
      crumbs: [
        AppCrumb(languageLabel(viewModel.language), onTap: controller.goToCatalog),
        // The short form: the crumb beside it already names the language.
        AppCrumb(context.localizations.microbitProgramScreen_crumb),
      ],
    );
  }

  Widget _buildContent() {
    return Builder(
      builder: (context) => Observer(
        builder: (context) => switch (viewModel.status) {
          MicrobitStatus.connected || MicrobitStatus.flashing => _buildSession(context),
          _ => _buildNotice(context),
        },
      ),
    );
  }

  /// A board is open, so the terminal gets the screen.
  ///
  /// **Not inside a scroll view**, which is not a layout preference: a terminal
  /// nested in one never sees the space bar, because the scrollable takes it
  /// first and pages down instead. The browser console is laid out the same way
  /// and for the same reason.
  Widget _buildSession(BuildContext context) {
    if (viewModel.devices.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, AppHeader.height + 40, 32, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeading(context),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerLeft,
                child: MicrobitBoardSummary(device: viewModel.devices.first, info: viewModel.boardInfo),
              ),
              const SizedBox(height: 8),
              Text(
                context.localizations.microbitProgramScreen_hint,
                style: context.appTheme.text.bodySmall.copyWith(color: context.theme.colors.mutedForeground),
              ),
              const SizedBox(height: 16),
              CodeEditorCard(
                controller: viewModel.code,
                status: _editorStatus(context),
                height: CodeEditorCard.heightForLines(6),
              ),
              const SizedBox(height: 12),
              AppButtonRow(
                children: [
                  _buildFlashButton(context),
                  _buildRestartButton(context),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(child: ReplTerminal(terminal: viewModel.terminal)),
            ],
          ),
        ),
      ),
    );
  }

  /// Everything that is not a live session: an explanation and a button.
  Widget _buildNotice(BuildContext context) {
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
              Observer(builder: _buildState),
            ],
          ),
        ),
      ),
    );
  }

  /// Writes the editor to the board, and fills with how far that has got.
  ///
  /// The spinner covers the stretch before the first measurement: the board is
  /// asked which pages differ before anything is written, and a bar sitting at
  /// zero for a second reads as a button that did not respond.
  Widget _buildFlashButton(BuildContext context) {
    final flashing = viewModel.status == MicrobitStatus.flashing;
    final measured = flashing && viewModel.flashProgress > 0;

    return AppButton(
      icon: FLucideIcons.zap,
      busy: flashing && !measured,
      progress: measured ? viewModel.flashProgress : null,
      onPress: flashing ? null : controller.flash,
      child: Text(context.localizations.microbitScreen_flash),
    );
  }

  /// Runs what is already on the board again, from the top.
  ///
  /// Beside the flash button rather than up by the board, because both are
  /// things done to the program: one puts a new one there, the other starts the
  /// one that is there over.
  Widget _buildRestartButton(BuildContext context) {
    return AppButton(
      tone: AppButtonTone.neutral,
      icon: FLucideIcons.rotateCcw,
      // A restart in the middle of a write would reset the board out from under
      // the pages still being written.
      onPress: viewModel.status == MicrobitStatus.flashing ? null : controller.restart,
      child: Text(context.localizations.microbitScreen_restart),
    );
  }

  /// The strip over the editor, which says what the board is doing rather than
  /// what the editor is.
  String _editorStatus(BuildContext context) {
    final l10n = context.localizations;

    final percent = (viewModel.flashProgress * 100).round();
    final plan = viewModel.flashPlan;

    return switch (viewModel.status) {
      MicrobitStatus.flashing when plan != null =>
        l10n.microbitScreen_flashingPages(percent, plan.changed, plan.total),
      MicrobitStatus.flashing when viewModel.flashPlanFailure != null =>
        l10n.microbitScreen_flashingPagesUnknown(percent),
      MicrobitStatus.flashing => l10n.microbitScreen_flashing(percent),
      _ => l10n.microbitScreen_flashHint,
    };
  }

  Widget _buildHeading(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.localizations.microbitProgramScreen_title,
          style: context.appTheme.text.h1.copyWith(fontSize: 42),
        ),
        const SizedBox(height: 8),
        Text(
          context.localizations.microbitProgramScreen_subtitle,
          style: context.appTheme.text.body.copyWith(fontSize: 19, color: context.theme.colors.mutedForeground),
        ),
      ],
    );
  }

  Widget _buildState(BuildContext context) {
    return MicrobitStatePanel(
      status: viewModel.status,
      failureKind: viewModel.failureKind,
      failure: viewModel.failure,
      onConnect: controller.connect,
    );
  }

}
