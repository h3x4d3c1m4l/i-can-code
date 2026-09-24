import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/extensions/color_extension.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/shape_metrics.dart';
import 'package:i_can_code/views/components/completed_badge.dart';

/// One row of a list of things to open: a tile, a title and subtitle, and a
/// count on the right. Shared by the language picker and the lesson catalog.
///
/// An unavailable row is drawn as a half-opacity outline rather than hidden, so
/// the shape of the course stays visible. Only an available row is bevelled.
class CatalogCard extends StatelessWidget {

  /// The card's bevel, the same device as `AppButton`'s at the scale of a card:
  /// a thick edge and a hard, unblurred collar under it that the card rises
  /// off on hover and sinks into on press. Matters of taste, all of them.
  static const double _edgeWidth = 2.5;
  static const double _collarHeight = 6;
  static const double _hoverLift = 2;

  /// How much darker than the `border` token the edge and the collar are, in
  /// [HSLColor] lightness. The token itself is a card's quiet outline and too
  /// faint on the cream page to read as a rim. The edge is darkened in the light
  /// scheme only.
  static const double _edgeDarken = 0.12;
  static const double _collarDarken = 0.28;

  /// The tile is a small copy of a primary `AppButton`: the same darkened
  /// edge, collar and gloss, so the row's one spot of brand colour looks like
  /// the thing to press.
  static const double _tileSize = 58;
  static const double _tileEdgeWidth = 2;
  static const double _tileCollarHeight = 3;
  static const double _tileEdgeDarken = 0.28;
  static const double _tileCollarDarken = 0.18;
  static const Color _glossTop = Color(0x59FFFFFF);
  static const Color _glossBottom = Color(0x00FFFFFF);

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

    final content = Padding(
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
            const CompletedBadge()
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
    );

    // No bevel on a row that cannot be opened: looking pressable is exactly
    // what it must not do.
    if (!available) {
      return Opacity(
        opacity: 0.5,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            shape: squircle(kCardCornerRadius, side: BorderSide(color: theme.colors.border, width: 2)),
          ),
          child: content,
        ),
      );
    }

    // On a dark card the `border` token is already lighter than the card, so
    // darkening it would sink the edge into the fill it is meant to outline.
    final edge = theme.colors.brightness == Brightness.dark
        ? theme.colors.border
        : theme.colors.border.darken(_edgeDarken);

    return FTappable(
      onPress: onTap,
      semanticsButton: true,
      builder: (context, states, child) {
        final lift = switch (states) {
          _ when states.contains(FTappableVariant.pressed) => -_collarHeight,
          _ when states.contains(FTappableVariant.hovered) => _hoverLift,
          _ => 0.0,
        };
        final focused = states.contains(FTappableVariant.focused);

        return TweenAnimationBuilder<double>(
          tween: Tween(end: lift),
          duration: context.motion(const Duration(milliseconds: 120)),
          curve: Curves.easeOut,
          // Moving the face up by as much as the collar grows keeps the
          // collar's own bottom edge still: the card rises off the page rather
          // than the whole thing drifting.
          builder: (context, lift, child) => Transform.translate(
            offset: Offset(0, -lift),
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: theme.colors.card,
                shape: squircle(
                  kCardCornerRadius,
                  side: BorderSide(
                    // The only focus indication a card has, so the ink rather
                    // than a brand fill that may not clear 3:1 on the page.
                    color: focused ? theme.colors.foreground : edge,
                    width: _edgeWidth,
                  ),
                ),
                shadows: [
                  BoxShadow(
                    color: theme.colors.border.darken(_collarDarken),
                    offset: Offset(0, _collarHeight + lift),
                  ),
                ],
              ),
              child: child,
            ),
          ),
          child: child,
        );
      },
      child: content,
    );
  }

  Widget _buildTile(BuildContext context, {required bool available}) {
    final theme = context.theme;
    final fill = available ? theme.colors.primary : theme.colors.border;
    final shape = squircleOf(kControlCornerRadius - 2, size: _tileSize);

    return SizedBox.square(
      dimension: _tileSize,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: fill,
          shape: available
              ? squircleOf(
                  kControlCornerRadius - 2,
                  size: _tileSize,
                  side: BorderSide(color: fill.darken(_tileEdgeDarken), width: _tileEdgeWidth),
                )
              : shape,
          shadows: available
              ? [BoxShadow(color: fill.darken(_tileCollarDarken), offset: const Offset(0, _tileCollarHeight))]
              : null,
        ),
        child: ClipPath(
          clipper: ShapeBorderClipper(shape: shape),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (available)
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [_glossTop, _glossBottom],
                      stops: [0, 0.6],
                    ),
                  ),
                ),
              Center(
                child: emoji != null
                    ? Text(
                        emoji!,
                        style: const TextStyle(fontFamilyFallback: kEmojiFontFallback, fontSize: 30, height: 1),
                      )
                    : Text(
                        label,
                        style: context.appTheme.text.code.copyWith(
                          fontSize: 22,
                          height: 1,
                          color: available ? theme.colors.primaryForeground : theme.colors.foreground,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

}
