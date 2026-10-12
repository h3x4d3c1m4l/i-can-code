import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/views/components/app_button.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens the MicroPython documentation for the micro:bit in a new tab.
///
/// A glyph with a tip and no word, because a project's column has room for
/// the one beside its two board buttons and not for the other.
class MicrobitDocsButton extends StatelessWidget {

  /// The front page, never the page of one module. A reorganised site breaks a
  /// deep link, and finding the page is left to the student on purpose.
  static const String url = 'https://microbit-micropython.readthedocs.io/';

  const MicrobitDocsButton({super.key});

  @override
  Widget build(BuildContext context) {
    final label = context.localizations.microbitScreen_docs;

    return AppButton.icon(
      icon: FLucideIcons.bookOpen,
      semanticsLabel: label,
      tip: label,
      onPress: () => launchUrl(Uri.parse(url)),
    );
  }

}
