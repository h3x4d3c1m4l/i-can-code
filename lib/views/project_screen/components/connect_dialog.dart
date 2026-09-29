import 'package:flutter/widgets.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/views/components/app_button.dart';
import 'package:i_can_code/views/components/microbit/microbit_session_view_model.dart';
import 'package:i_can_code/views/components/microbit/microbit_state_panel.dart';
import 'package:mobx/mobx.dart';

/// Asks for a board, at the moment one turns out to be missing: when the
/// student wants to write their program to one.
///
/// Answers true once a board is open, which closes the dialog by itself, and
/// false when the student closes it first. It follows [board] rather than the
/// connect call, because the board reports being open through its session's
/// events, some time after that call returns.
Future<bool> showConnectDialog(
  BuildContext context, {
  required MicrobitSessionViewModel board,
  required VoidCallback onConnect,
}) async {
  final connected = await showFDialog<bool>(
    context: context,
    builder: (context, style, animation) => FDialog(
      animation: animation,
      builder: (context, style) => _ConnectDialogBody(board: board, onConnect: onConnect),
    ),
  );

  return connected ?? false;
}

class _ConnectDialogBody extends StatefulWidget {

  final MicrobitSessionViewModel board;
  final VoidCallback onConnect;

  const _ConnectDialogBody({required this.board, required this.onConnect});

  @override
  State<_ConnectDialogBody> createState() => _ConnectDialogBodyState();

}

class _ConnectDialogBodyState extends State<_ConnectDialogBody> {

  late final ReactionDisposer _closeOnConnect;

  @override
  void initState() {
    super.initState();
    // A reaction and not a check in `build`: popping a route while building
    // one is an error.
    _closeOnConnect = when(
      (_) => widget.board.status == MicrobitStatus.connected,
      () {
        if (mounted) Navigator.of(context).pop(true);
      },
    );
  }

  @override
  void dispose() {
    _closeOnConnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Observer(
            builder: (context) => MicrobitStatePanel(
              status: widget.board.status,
              failureKind: widget.board.failureKind,
              failure: widget.board.failure,
              onConnect: widget.onConnect,
              framed: false,
            ),
          ),
          const SizedBox(height: 20),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: AppButton(
              tone: AppButtonTone.neutral,
              onPress: () => Navigator.of(context).pop(false),
              child: Text(context.localizations.projectScreen_close),
            ),
          ),
        ],
      ),
    );
  }

}
