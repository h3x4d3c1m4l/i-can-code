import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/shape_metrics.dart';

/// One component of the licence screen: its name, where it comes from, and
/// every licence text that covers it.
///
/// The texts are set as their authors wrote them, line for line and in the
/// code face. Flutter's `LicensePage` rejoins the lines into paragraphs, which
/// reads better for prose and turns a table or a directory tree in a licence
/// into one run of words.
class LicenseDetail extends StatelessWidget {

  static const double _gutter = 28;

  final String name;

  /// Where the component comes from, as the list's own heading says it.
  final String origin;

  /// MUST NOT be empty.
  final List<String> texts;

  const LicenseDetail({required this.name, required this.origin, required this.texts, super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final tokens = context.appTheme;
    final shape = squircle(kCardCornerRadius, side: BorderSide(color: colors.border, width: 2));

    return DecoratedBox(
      decoration: ShapeDecoration(color: colors.card, shape: shape),
      // The texts scroll inside the card, and a scroll view clips to a plain
      // rectangle: without this they would run over the card's own corners.
      child: ClipPath(
        clipper: ShapeBorderClipper(shape: shape),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(_gutter, 24, _gutter, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(origin.toUpperCase(), style: tokens.text.label),
                  const SizedBox(height: 6),
                  Semantics(header: true, child: Text(name, style: tokens.text.h3)),
                  if (texts.length > 1) ...[
                    const SizedBox(height: 4),
                    Text(
                      context.localizations.licensesScreen_count(texts.length),
                      style: tokens.text.bodySmall.copyWith(fontSize: 16),
                    ),
                  ],
                ],
              ),
            ),
            _buildRule(colors),
            Expanded(
              child: ListView.separated(
                // A new component is a new list, so it opens at its top rather
                // than where the last one was left.
                key: ValueKey(name),
                padding: const EdgeInsets.symmetric(horizontal: _gutter, vertical: 24),
                itemCount: texts.length,
                // Built as they scroll into view: the engine's larger components
                // carry hundreds of texts each.
                itemBuilder: (context, index) => Text(
                  texts[index],
                  style: tokens.text.codeSmall.copyWith(fontSize: 13, height: 1.55, color: colors.foreground),
                ),
                separatorBuilder: (context, index) =>
                    Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: _buildRule(colors)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRule(FColors colors) => SizedBox(height: 2, child: ColoredBox(color: colors.border));

}
