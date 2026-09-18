import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/theme/app_theme.dart';

/// The small heading over a run of lessons that belong together — a week of a
/// course, say. The words come from the lessons themselves; see
/// `Lesson.group`.
///
/// Small and set in capitals, in the style the output card names its blocks
/// in, rather than as another `h2`: it names the cards under it without
/// competing with them, and the page's real headings — the language, the
/// *Verdieping* and *Extra* sections — stay the only large type on it.
class CatalogGroupHeading extends StatelessWidget {

  final String label;

  const CatalogGroupHeading(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(
        label.toUpperCase(),
        style: context.appTheme.text.label.copyWith(
          fontSize: 13,
          color: context.theme.colors.mutedForeground,
        ),
      ),
    );
  }

}
