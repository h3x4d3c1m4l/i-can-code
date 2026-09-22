import 'package:flutter/widgets.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/services/microbit/microbit_link.dart';
import 'package:i_can_code/views/components/app_button.dart';
import 'package:i_can_code/views/components/microbit/microbit_session_view_model.dart';
import 'package:i_can_code/views/components/notice_card.dart';

/// Everything a micro:bit screen shows while no board is open.
///
/// Both screens say the same things here: the browser cannot do it, nothing is
/// plugged in, something else holds the board, or press Connect. What they do
/// with an open board is where they part ways, and that is not this.
class MicrobitStatePanel extends StatelessWidget {

  final MicrobitStatus status;

  /// Which failure, for [MicrobitStatus.failed].
  final MicrobitFailure? failureKind;

  /// The core's own words, untranslated: for whoever is debugging, not for the
  /// student.
  final String? failure;

  /// MUST be reached straight from the button press. WebUSB only opens its
  /// picker inside the gesture that asked for it, and an `await` in between
  /// loses that gesture.
  final VoidCallback onConnect;

  const MicrobitStatePanel({
    required this.status,
    required this.onConnect,
    this.failureKind,
    this.failure,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.localizations;

    return switch (status) {
      MicrobitStatus.unavailable => NoticeCard(
        title: l10n.microbitScreen_unavailableTitle,
        body: l10n.microbitScreen_unavailableBody,
      ),
      MicrobitStatus.failed => _buildFailure(context),
      MicrobitStatus.noDevice => NoticeCard(
        title: l10n.microbitScreen_noDeviceTitle,
        body: l10n.microbitScreen_noDeviceBody,
        action: _buildConnectButton(context),
      ),
      // The screen itself draws the session, outside the scroll view a terminal
      // may not sit in.
      MicrobitStatus.connected || MicrobitStatus.flashing => const SizedBox.shrink(),
      MicrobitStatus.disconnected || MicrobitStatus.connecting => NoticeCard(
        title: l10n.microbitScreen_connectTitle,
        body: l10n.microbitScreen_connectBody,
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

    final (title, body) = switch (failureKind) {
      MicrobitFailure.busy => (l10n.microbitScreen_busyTitle, l10n.microbitScreen_busyBody),
      MicrobitFailure.unsupportedBoard => (l10n.microbitScreen_wrongBoardTitle, l10n.microbitScreen_wrongBoardBody),
      MicrobitFailure.noDevice => (l10n.microbitScreen_noDeviceTitle, l10n.microbitScreen_noDeviceBody),
      MicrobitFailure.protocol || null => (l10n.microbitScreen_failedTitle, l10n.microbitScreen_failedBody),
    };

    return NoticeCard(
      title: title,
      body: body,
      detail: failure,
      // English, and for whoever helps: folded, as the Tkinter page folds its own.
      detailLabel: l10n.microbitScreen_failureDetails,
      action: _buildConnectButton(context),
    );
  }

  Widget _buildConnectButton(BuildContext context) {
    final connecting = status == MicrobitStatus.connecting;

    return AppButton(
      onPress: connecting ? null : onConnect,
      busy: connecting,
      child: Text(context.localizations.microbitScreen_connect),
    );
  }

}
