import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/shape_metrics.dart';

/// One group of facts on the about screen, under a heading of its own.
class AboutCard extends StatelessWidget {

  final String title;

  /// [AboutRow]s, mostly, set one under the other.
  final List<Widget> children;

  const AboutCard({required this.title, required this.children, super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: context.appTheme.text.h3),
        const SizedBox(height: 12),
        DecoratedBox(
          decoration: ShapeDecoration(
            color: colors.card,
            shape: squircle(kCardCornerRadius, side: BorderSide(color: colors.border, width: 2)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 14,
              children: children,
            ),
          ),
        ),
      ],
    );
  }

}

/// A name and its value beside it, or under it where the two do not fit.
class AboutRow extends StatelessWidget {

  /// Wide enough for the longest name at the body size, "On the micro:bit",
  /// which measures 162px in Lexend.
  static const double _labelWidth = 180;

  static const double _gap = 16;

  final String label;

  final Widget value;

  const AboutRow({required this.label, required this.value, super.key});

  @override
  Widget build(BuildContext context) {
    final text = context.appTheme.text;
    final name = Text(label, style: text.body.copyWith(color: context.theme.colors.mutedForeground));
    final shown = DefaultTextStyle.merge(style: text.body, child: value);

    if (MediaQuery.sizeOf(context).width < context.theme.breakpoints.sm) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [name, shown]);
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        SizedBox(width: _labelWidth, child: name),
        const SizedBox(width: _gap),
        Expanded(child: shown),
      ],
    );
  }

}
