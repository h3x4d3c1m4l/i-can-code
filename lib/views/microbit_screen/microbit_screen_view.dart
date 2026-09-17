import 'package:flutter/widgets.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/microbit/microbit_link.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/views/base/screen_view_base.dart';
import 'package:i_can_code/views/components/app_button.dart';
import 'package:i_can_code/views/components/app_header.dart';
import 'package:i_can_code/views/components/app_header_publisher.dart';
import 'package:i_can_code/views/components/repl_terminal.dart';
import 'package:i_can_code/views/microbit_screen/components/microbit_board_summary.dart';
import 'package:i_can_code/views/microbit_screen/components/microbit_notice.dart';
import 'package:i_can_code/views/microbit_screen/microbit_screen_controller.dart';
import 'package:i_can_code/views/microbit_screen/microbit_screen_view_model.dart';

class MicrobitScreenView extends ScreenViewBase<MicrobitScreenViewModel, MicrobitScreenController> {

  const MicrobitScreenView({required super.viewModel, required super.controller, required super.contextAccessor});

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
        AppCrumb(context.localizations.microbitScreen_crumb),
      ],
    );
  }

  Widget _buildContent() {
    return Builder(
      builder: (context) => Observer(
        builder: (context) => viewModel.status == MicrobitStatus.connected
            ? _buildSession(context)
            : _buildNotice(context),
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
                      child: MicrobitBoardSummary(
                        device: viewModel.devices.first,
                        info: viewModel.boardInfo,
                      ),
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
                context.localizations.microbitScreen_replHint,
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
              Observer(builder: _buildState),
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
          context.localizations.microbitScreen_title(languageLabel(viewModel.language)),
          style: context.appTheme.text.h1.copyWith(fontSize: 42),
        ),
        const SizedBox(height: 8),
        Text(
          context.localizations.microbitScreen_subtitle,
          style: context.appTheme.text.body.copyWith(fontSize: 19, color: context.theme.colors.mutedForeground),
        ),
      ],
    );
  }

  Widget _buildState(BuildContext context) {
    return switch (viewModel.status) {
      MicrobitStatus.unavailable => MicrobitNotice(
        title: context.localizations.microbitScreen_unavailableTitle,
        body: context.localizations.microbitScreen_unavailableBody,
      ),
      MicrobitStatus.failed => _buildFailure(context),
      MicrobitStatus.noDevice => MicrobitNotice(
        title: context.localizations.microbitScreen_noDeviceTitle,
        body: context.localizations.microbitScreen_noDeviceBody,
        action: _buildConnectButton(context),
      ),
      // Handled by _buildSession, which is not inside a scroll view.
      MicrobitStatus.connected => const SizedBox.shrink(),
      MicrobitStatus.disconnected || MicrobitStatus.connecting => MicrobitNotice(
        title: context.localizations.microbitScreen_connectTitle,
        body: context.localizations.microbitScreen_connectBody,
        action: _buildConnectButton(context),
      ),
    };
  }

  /// The failure card, worded for the failure that actually happened.
  ///
  /// "Something else has it" and "that is not a V2" need different things from
  /// the reader, and a single "could not connect" would tell them neither.
  Widget _buildFailure(BuildContext context) {
    final l10n = context.localizations;

    final (title, body) = switch (viewModel.failureKind) {
      MicrobitFailure.busy => (l10n.microbitScreen_busyTitle, l10n.microbitScreen_busyBody),
      MicrobitFailure.unsupportedBoard => (
        l10n.microbitScreen_wrongBoardTitle,
        l10n.microbitScreen_wrongBoardBody,
      ),
      MicrobitFailure.noDevice => (l10n.microbitScreen_noDeviceTitle, l10n.microbitScreen_noDeviceBody),
      MicrobitFailure.protocol || null => (l10n.microbitScreen_failedTitle, l10n.microbitScreen_failedBody),
    };

    return MicrobitNotice(
      title: title,
      body: body,
      // The core's own words, under the explanation. Untranslated on purpose:
      // it is for whoever is debugging, not for the student.
      detail: viewModel.failure,
      action: _buildConnectButton(context),
    );
  }

  Widget _buildConnectButton(BuildContext context) {
    final connecting = viewModel.status == MicrobitStatus.connecting;

    return AppButton(
      // Straight to the controller, with nothing awaited in between: WebUSB only
      // opens its picker inside the gesture that reached it.
      onPress: connecting ? null : controller.connect,
      busy: connecting,
      child: Text(context.localizations.microbitScreen_connect),
    );
  }

}
