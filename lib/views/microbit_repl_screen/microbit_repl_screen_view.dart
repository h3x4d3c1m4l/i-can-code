import 'package:flutter/widgets.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/views/base/screen_view_base.dart';
import 'package:i_can_code/views/components/app_button.dart';
import 'package:i_can_code/views/components/app_header.dart';
import 'package:i_can_code/views/components/app_header_publisher.dart';
import 'package:i_can_code/views/components/microbit/microbit_board_summary.dart';
import 'package:i_can_code/views/components/microbit/microbit_session_controller.dart';
import 'package:i_can_code/views/components/microbit/microbit_session_view_model.dart';
import 'package:i_can_code/views/components/microbit/microbit_state_panel.dart';
import 'package:i_can_code/views/components/repl_terminal.dart';

/// MicroPython's own prompt, on the board.
///
/// The board's sibling screen writes a program to it; this one talks to the
/// interpreter that is already there. Separate screens because they want
/// opposite things of a board: a prompt interrupts whatever is running, and a
/// program is left alone to run.
class MicrobitReplScreenView extends ScreenViewBase<MicrobitSessionViewModel, MicrobitSessionController> {

  const MicrobitReplScreenView({required super.viewModel, required super.controller, required super.contextAccessor});

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
        AppCrumb(context.localizations.microbitReplScreen_crumb),
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
              Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: MicrobitBoardSummary(device: viewModel.devices.first, info: viewModel.boardInfo),
                    ),
                  ),
                  const SizedBox(width: 16),
                  AppButton(
                    tone: AppButtonTone.neutral,
                    icon: FLucideIcons.rotateCcw,
                    onPress: controller.restart,
                    child: Text(context.localizations.microbitScreen_restart),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                context.localizations.microbitReplScreen_hint,
                style: context.appTheme.text.bodySmall.copyWith(color: context.theme.colors.mutedForeground),
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
              Observer(
                builder: (context) => MicrobitStatePanel(
                  status: viewModel.status,
                  failureKind: viewModel.failureKind,
                  failure: viewModel.failure,
                  onConnect: controller.connect,
                ),
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
        Text(
          context.localizations.microbitReplScreen_title(languageLabel(viewModel.language)),
          style: context.appTheme.text.h1.copyWith(fontSize: 42),
        ),
        const SizedBox(height: 8),
        Text(
          context.localizations.microbitReplScreen_subtitle,
          style: context.appTheme.text.body.copyWith(fontSize: 19, color: context.theme.colors.mutedForeground),
        ),
      ],
    );
  }

}
