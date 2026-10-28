import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/theme/app_theme.dart';

/// Where a [TextLink] goes, which its glyph says before the press.
enum TextLinkTarget {

  /// Another screen of the app.
  screen,

  /// Another tab, such as the app's source.
  tab,

  /// An explanation in a dialog over this screen. A button to a screen reader,
  /// since nothing navigates.
  help,

}

/// A link set in running text: to the app's source, to another screen, or to an
/// explanation.
///
/// Underlined as well as coloured, like a link in a lesson's prose: the link
/// colour of a preset is not always far enough from its text colour to say
/// "link" by itself. A tappable and not a span with a recogniser, which is what
/// puts it in the tab order.
class TextLink extends StatelessWidget {

  static const double _fontSize = 17;

  final String label;

  final VoidCallback onPress;

  final TextLinkTarget target;

  const TextLink({required this.label, required this.onPress, this.target = TextLinkTarget.screen, super.key});

  @override
  Widget build(BuildContext context) {
    final color = context.appTheme.colors.link;

    return Semantics(
      link: target != TextLinkTarget.help,
      button: target == TextLinkTarget.help,
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
            Icon(switch (target) {
              TextLinkTarget.screen => FLucideIcons.chevronRight,
              TextLinkTarget.tab => FLucideIcons.externalLink,
              TextLinkTarget.help => FLucideIcons.circleQuestionMark,
            }, size: _fontSize, color: color),
          ],
        ),
      ),
    );
  }

}
