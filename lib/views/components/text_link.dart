import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/theme/app_theme.dart';

/// A link set in running text: to the app's source, or to another screen.
///
/// Underlined as well as coloured, like a link in a lesson's prose: the link
/// colour of a preset is not always far enough from its text colour to say
/// "link" by itself. A tappable and not a span with a recogniser, which is what
/// puts it in the tab order.
class TextLink extends StatelessWidget {

  static const double _fontSize = 17;

  final String label;

  final VoidCallback onPress;

  /// Whether the press opens another tab, which the link then says before the
  /// press. Otherwise it points on to a screen of the app.
  final bool opensTab;

  const TextLink({required this.label, required this.onPress, this.opensTab = false, super.key});

  @override
  Widget build(BuildContext context) {
    final color = context.appTheme.colors.link;

    return Semantics(
      link: true,
      child: FTappable(
        onPress: onPress,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                style: context.appTheme.text.bodySmall.copyWith(
                  fontSize: _fontSize,
                  color: color,
                  decoration: TextDecoration.underline,
                  decorationColor: color,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Icon(opensTab ? FLucideIcons.externalLink : FLucideIcons.chevronRight, size: _fontSize, color: color),
          ],
        ),
      ),
    );
  }

}
