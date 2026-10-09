import 'package:forui/forui.dart';

/// The press of a bevelled control, one whose face sinks into its own collar:
/// `pressed` is reported at once, and nothing is scaled.
///
/// forui scales every tappable down while it is held. On a face that is also
/// sinking, that is a second kind of press, and it pulls the face's edges away
/// from the collar. forui also holds `pressed` back for 100ms, so a click
/// shorter than that shrank the control and never sank it.
const FTappableStyleDelta kBevelPressStyle = FTappableStyleDelta.delta(
  pressedEnterDuration: Duration.zero,
  motion: FTappableMotion.none,
);
