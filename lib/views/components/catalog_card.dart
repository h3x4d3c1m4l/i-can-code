import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/shape_metrics.dart';

/// One row of a list of things to open: a tile, a title and subtitle, and a
/// count on the right. Shared by the language picker and the lesson catalog.
///
/// An unavailable row is drawn as a half-opacity outline rather than hidden, so
/// the shape of the course stays visible.
class CatalogCard extends StatelessWidget {

  /// What the tile shows when there is no [emoji] — short, because the tile is
  /// 58px square.
  final String label;

  /// The row's own emoji, drawn in the tile in place of [label]. Null falls back
  /// to [label]: a lesson whose file declares none, or a language this app has
  /// no emoji for.
  final String? emoji;

  final String title;

  /// The lesson's one-line subtitle. Null when the file does not give one.
  final String? subtitle;

  /// The count on the right — how many steps, or how far in. Replaced by a tick
  /// once [finished] is set.
  final String meta;

  /// Everything in this row is done.
  final bool finished;

  /// Null while the chapter cannot be opened yet.
  final VoidCallback? onTap;

  const CatalogCard({
    required this.label,
    required this.title,
    required this.meta,
    this.emoji,
    this.finished = false,
    this.subtitle,
    this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final available = onTap != null;

    return MouseRegion(
      cursor: available ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        onTap: onTap,
        child: Opacity(
          opacity: available ? 1 : 0.5,
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: available ? theme.colors.card : const Color(0x00000000),
              shape: squircle(
                kCardCornerRadius,
                side: available ? BorderSide.none : BorderSide(color: theme.colors.border, width: 2),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: Row(
                children: [
                  _buildTile(context, available: available),
                  const SizedBox(width: 22),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(title, style: context.appTheme.text.h3),
                        if (subtitle case final String subtitle)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              subtitle,
                              style: context.appTheme.text.bodySmall.copyWith(
                                fontSize: 16,
                                color: theme.colors.mutedForeground,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  if (finished)
                    Icon(FLucideIcons.check, size: 22, color: context.appTheme.colors.progressComplete)
                  else
                    Text(
                      meta,
                      style: context.appTheme.text.bodySmall.copyWith(
                        fontSize: 16,
                        color: theme.colors.mutedForeground,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTile(BuildContext context, {required bool available}) {
    final theme = context.theme;

    return SizedBox.square(
      dimension: 58,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: available ? theme.colors.primary : theme.colors.border,
          shape: squircleOf(kControlCornerRadius - 2, size: 58),
        ),
        child: Center(
          child: emoji != null
              ? Text(emoji!, style: const TextStyle(fontFamilyFallback: kEmojiFontFallback, fontSize: 30, height: 1))
              : Text(
                  label,
                  style: context.appTheme.text.code.copyWith(
                    fontSize: 22,
                    height: 1,
                    color: available ? theme.colors.primaryForeground : theme.colors.foreground,
                  ),
                ),
        ),
      ),
    );
  }

}
