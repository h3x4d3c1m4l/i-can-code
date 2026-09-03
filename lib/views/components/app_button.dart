import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/shape_metrics.dart';

/// What a button means, which decides how it is filled.
enum AppButtonTone {

  /// Moving on: Verder, Volgende, "Terug naar Python". The brand fill.
  ///
  /// **Every button that carries the reader forward is this tone**, on every
  /// kind of step, so the same word never changes colour between one step and
  /// the next.
  primary,

  /// The quieter one beside it — "Draai code & controleer", "Annuleren".
  ///
  /// Filled with the page's *foreground*, so it inverts with the mode: near
  /// black on the light page, off white on the dark one. Quiet next to the
  /// brand fill either way, but never quiet in the sense of low contrast.
  neutral,

  /// Quieter still: an outline and no fill, for a step *back*.
  ///
  /// Drawn in the page's own ink, the colour [neutral] is *filled* with, so the
  /// two read as the same button with and without its fill. Ink rather than the
  /// quiet `border` a card is outlined with, which against the cream page is
  /// too faint to say "this is a control"; and ink rather than literal black,
  /// so the edge inverts with the mode instead of disappearing into the dark
  /// page.
  ///
  /// Not the neobrutalist thick outline the preset leaves out — that one goes
  /// round everything and would live in the shared metrics. This is one
  /// button's own edge.
  outline,
}

/// Which side of the label a button's icon sits on.
enum AppButtonIconSide {

  /// Before the label. What an icon naming the *action* takes — the play mark
  /// on "Draai code".
  leading,

  /// After the label. What an icon naming the *destination* takes, so the
  /// chevron on "Volgende" points out of the button the way the reader is
  /// about to go.
  trailing,
}

/// The app's button.
///
/// Not forui's [FButton]: its padding is `10 × 11` against the design's
/// `38 × 19`, and it fills with a [BoxDecoration], which cannot draw a squircle.
/// Still built on [FTappable], so hover, focus, keyboard activation and button
/// semantics come from the framework.
class AppButton extends StatelessWidget {

  /// The glyph's size, and the gap between it and the label.
  static const double _iconSize = 20;
  static const double _iconGap = 10;

  static const EdgeInsets _labelPadding = EdgeInsets.symmetric(horizontal: 38, vertical: 19);

  /// Square-ish, for a button with nothing to read in it.
  static const EdgeInsets _iconPadding = EdgeInsets.symmetric(horizontal: 19, vertical: 19);

  /// [AppButtonTone.outline]'s edge. Public because it is a matter of taste:
  /// thinner than the 2 an outlined card takes, so the button reads as a
  /// control rather than as a panel.
  static const double outlineWidth = 1;

  static const Color _transparent = Color(0x00000000);

  /// The label. Null on an icon-only button — see [AppButton.icon].
  final Widget? child;

  /// A Lucide glyph beside the label, or the whole button when [child] is null.
  final IconData? icon;

  final AppButtonIconSide iconSide;

  /// Null disables the button, which dims it and stops it responding.
  final VoidCallback? onPress;

  final AppButtonTone tone;

  /// Swaps the label for a spinner **without resizing the button**: the label
  /// stays laid out and merely turns invisible.
  final bool busy;

  /// What a screen reader announces. Null on a labelled button, which reads its
  /// own label.
  final String? semanticsLabel;

  const AppButton({
    required this.child,
    required this.onPress,
    this.icon,
    this.iconSide = AppButtonIconSide.leading,
    this.tone = AppButtonTone.primary,
    this.busy = false,
    super.key,
  }) : semanticsLabel = null;

  /// A button that is only a glyph — the back chevron beside "Volgende".
  ///
  /// [semanticsLabel] is required rather than optional: there is no text in
  /// here for a screen reader to fall back on, so a missing one leaves an
  /// unnamed button.
  ///
  /// **Shorter than a labelled button** unless something makes them agree: its
  /// content is a 20px glyph where the other's is a line of text, whose height
  /// is the font's business and not a number this app can state. Put the two in
  /// an [AppButtonRow], which is what settles it.
  const AppButton.icon({
    required IconData this.icon,
    required String this.semanticsLabel,
    required this.onPress,
    this.tone = AppButtonTone.outline,
    super.key,
  }) : child = null,
       busy = false,
       iconSide = AppButtonIconSide.leading;

  /// What the button is filled with in [states].
  ///
  /// A filled tone fades its own colour. An outlined one has no colour to fade
  /// — the fill *is* the page — so it tints with the ink instead, which is the
  /// only thing that gives it a hover and a press at all.
  Color _fillFor(
    Set<FTappableVariant> states, {
    required Color background,
    required Color foreground,
  }) {
    if (tone == AppButtonTone.outline) {
      return switch (states) {
        _ when states.contains(FTappableVariant.disabled) => _transparent,
        _ when states.contains(FTappableVariant.pressed) => foreground.withValues(alpha: 0.16),
        _ when states.contains(FTappableVariant.hovered) => foreground.withValues(alpha: 0.08),
        _ => _transparent,
      };
    }

    return switch (states) {
      _ when states.contains(FTappableVariant.disabled) => background.withValues(alpha: 0.4),
      _ when states.contains(FTappableVariant.pressed) => background.withValues(alpha: 0.75),
      _ when states.contains(FTappableVariant.hovered) => background.withValues(alpha: 0.86),
      _ => background,
    };
  }

  /// The label with its glyph, or the glyph alone. Centred either way, so an
  /// icon-only button stretched to a taller sibling keeps its glyph in the
  /// middle.
  Widget _buildContent(Color foreground, {required bool enabled}) {
    final glyph = icon == null
        ? null
        : Icon(icon, size: _iconSize, color: foreground.withValues(alpha: enabled ? 1 : 0.6));

    if (child == null) return Center(child: glyph);
    if (glyph == null) return child!;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (iconSide == AppButtonIconSide.leading) ...[glyph, const SizedBox(width: _iconGap)],
        child!,
        if (iconSide == AppButtonIconSide.trailing) ...[const SizedBox(width: _iconGap), glyph],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final enabled = onPress != null;

    final (background, foreground) = switch (tone) {
      AppButtonTone.primary => (theme.colors.primary, theme.colors.primaryForeground),
      AppButtonTone.neutral => (theme.colors.foreground, theme.colors.background),
      AppButtonTone.outline => (_transparent, theme.colors.foreground),
    };

    return FTappable(
      onPress: onPress,
      semanticsButton: true,
      semanticsLabel: semanticsLabel,
      builder: (context, states, child) => DecoratedBox(
        decoration: ShapeDecoration(
          color: _fillFor(states, background: background, foreground: foreground),
          shape: squircle(
            kControlCornerRadius,
            side: tone == AppButtonTone.outline
                ? BorderSide(
                    color: theme.colors.foreground.withValues(alpha: enabled ? 1 : 0.4),
                    width: outlineWidth,
                  )
                : BorderSide.none,
          ),
        ),
        child: Padding(
          // The design's own measurements: 38 across, 19 down.
          padding: this.child == null ? _iconPadding : _labelPadding,
          child: child,
        ),
      ),
      child: DefaultTextStyle(
        style: context.appTheme.text.label.copyWith(
          fontSize: 18,
          letterSpacing: 0,
          color: foreground.withValues(alpha: enabled ? 1 : 0.6),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Still laid out, so it keeps holding the button's width open.
            Visibility.maintain(visible: !busy, child: _buildContent(foreground, enabled: enabled)),
            // Positioned, so the spinner cannot contribute to the Stack's
            // size — a taller spinner than label would otherwise grow it.
            if (busy)
              Positioned.fill(
                child: Center(
                  child: FCircularProgress(
                    style: FCircularProgressStyleDelta.delta(
                      iconStyle: IconThemeDataDelta.delta(color: foreground, size: 16),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

}
