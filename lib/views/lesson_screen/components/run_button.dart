import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/views/components/app_button.dart';

/// The one button that starts the student's program and the one that stops it
/// again.
///
/// One button and not two: while a program is running, starting it is the only
/// thing that cannot be asked for and stopping it is the only thing that can, so
/// a second control would be dead half the time. It is also the way out of a run
/// that will not end on its own — a `while True:`, or the `sleep(3000)` a
/// student meant as milliseconds.
///
/// **It MUST NOT change size when it swaps.** Both labels stay laid out and only
/// one of them is painted, so the button is as wide as the longer of the two in
/// either state. A button that resizes the moment it is pressed reads as the
/// layout breaking, which is the same reason [AppButton.busy] keeps its label.
///
/// No spinner: the strip over the editor already says a run is in flight, and a
/// spinner drawn over the label would cover the one word that says what pressing
/// this now does.
class RunButton extends StatelessWidget {

  /// Whether a run is in flight, which is what decides which of the two this is.
  final bool running;

  final String runLabel;
  final String stopLabel;

  /// Null while there is nothing to run yet, which dims the button and stops it
  /// responding — a predict-output step with an empty box. Never null while
  /// [running]: stopping is always available.
  final VoidCallback? onRun;

  final VoidCallback onStop;

  const RunButton({
    required this.running,
    required this.runLabel,
    required this.stopLabel,
    required this.onRun,
    required this.onStop,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return AppButton(
      tone: AppButtonTone.neutral,
      // The square against the play mark: the pairing every transport control
      // uses, so neither needs reading to be recognised.
      icon: running ? FLucideIcons.square : FLucideIcons.play,
      onPress: running ? onStop : onRun,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _label(runLabel, visible: !running),
          _label(stopLabel, visible: running),
        ],
      ),
    );
  }

  /// Laid out either way, so it keeps the button's width open; read out only
  /// while it is the one showing, so a screen reader is not handed both at once.
  /// [Visibility] excludes the semantics of what it hides, which
  /// `Visibility.maintain` would keep.
  static Widget _label(String text, {required bool visible}) => Visibility(
    visible: visible,
    maintainSize: true,
    maintainAnimation: true,
    maintainState: true,
    child: Text(text),
  );

}
