import 'package:flutter/widgets.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:get_it/get_it.dart';
import 'package:i_can_code/services/feature_toggles.dart';

/// Builds [child] only while [feature] is on, and follows a switch in the debug
/// menu at once.
///
/// For a part of the app that is not ready to be shown, such as a card, a
/// button or a section. Off, it builds [fallback], which is nothing unless
/// given, so whatever is gated is not built at all.
class FeatureGate extends StatelessWidget {

  final StaticFeatureToggle feature;

  final Widget child;

  final Widget fallback;

  const FeatureGate({required this.feature, required this.child, this.fallback = const SizedBox.shrink(), super.key});

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (context) => GetIt.I<FeatureToggles>().isOn(feature.name) ? child : fallback);
  }

}
