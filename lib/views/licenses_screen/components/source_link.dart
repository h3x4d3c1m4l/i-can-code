import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/theme/app_theme.dart';

/// The link from the licence screen to the app's source.
///
/// Underlined as well as coloured, like a link in a lesson's prose: the link
/// colour of a preset is not always far enough from its text colour to say
/// "link" by itself. A tappable and not a span with a recogniser, which is what
/// puts it in the tab order.
class SourceLink extends StatelessWidget {

  static const double _fontSize = 17;

  final String label;

  final VoidCallback onPress;

  const SourceLink({required this.label, required this.onPress, super.key});

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
            // It opens another tab, and says so before the press.
            Icon(FLucideIcons.externalLink, size: _fontSize, color: color),
          ],
        ),
      ),
    );
  }

}
