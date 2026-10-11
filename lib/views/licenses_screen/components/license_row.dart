import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/shape_metrics.dart';

/// One component in the licence screen's list.
class LicenseRow extends StatelessWidget {

  static const EdgeInsets _padding = EdgeInsets.symmetric(horizontal: 14, vertical: 8);

  final String name;

  /// The one whose licence is showing.
  final bool selected;

  final VoidCallback onPress;

  const LicenseRow({required this.name, required this.selected, required this.onPress, super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;

    return FTappable(
      selected: selected,
      onPress: onPress,
      semanticsButton: true,
      builder: (context, states, child) {
        final lit = selected || states.contains(FTappableVariant.hovered);

        return DecoratedBox(
          decoration: ShapeDecoration(
            color: lit ? colors.secondary : const Color(0x00000000),
            shape: squircle(kChipCornerRadius),
          ),
          child: Padding(
            padding: _padding,
            child: DefaultTextStyle(
              style: context.appTheme.text.bodySmall.copyWith(
                fontSize: 16,
                height: 1.5,
                // Colour is not the only thing that says which one is open.
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                color: lit ? colors.secondaryForeground : colors.foreground,
              ),
              child: child!,
            ),
          ),
        );
      },
      // One line: a package name has no place to break.
      child: Text(name, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis),
    );
  }

}
