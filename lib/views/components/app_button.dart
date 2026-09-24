import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/extensions/color_extension.dart';
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
  /// Filled with `AppSemanticColors.neutralButton`, which inverts with the
  /// mode: a warm charcoal on the light page, off white on the dark one. Quiet
  /// next to the brand fill either way, but never quiet in the sense of low
  /// contrast.
  ///
  /// **Not the page's `foreground`**, which it used to be. Body text is as dark
  /// as a preset gets because prose has to be read, and a button is a slab of
  /// its colour rather than a line of it: the neutral preset's near-black ink
  /// read as a hole punched in the cream at that size. See the token's own doc.
  neutral,

  /// Quieter still: an outline around the page's own colour, for a step *back*.
  ///
  /// Drawn in the same `neutralButton` colour [neutral] is *filled* with, so
  /// the two read as the same button with and without its fill — which is why
  /// softening that fill moves this edge with it. That colour rather than the
  /// quiet `border` a card is outlined with, which against the cream page is
  /// too faint to say "this is a control"; and a token rather than literal
  /// black, so the edge inverts with the mode instead of disappearing into the
  /// dark page.
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

  static const EdgeInsets _labelPadding = EdgeInsets.symmetric(horizontal: 38, vertical: 16);

  /// Square-ish, for a button with nothing to read in it.
  static const EdgeInsets _iconPadding = EdgeInsets.symmetric(horizontal: 19, vertical: 16);

  /// Every tone's edge. Thick and playful on purpose: this ring is what gives
  /// a button its toy-block look, the same job the collar and the gloss below
  /// do.
  static const double _bevelOutlineWidth = 3;

  /// How far the collar shows beneath a button, and how far it sinks
  /// when pressed. A [BoxShadow] with no blur rather than a second widget: a
  /// [ShapeDecoration]'s shadows are already clipped to its own shape, so one
  /// solid, unblurred, downward shadow reads as a hard-edged rim instead of a
  /// soft drop shadow.
  static const double _collarHeight = 4;

  /// How much darker the outline and the collar are than the fill they sit
  /// on, in [HSLColor] lightness. Two different amounts, not one: an edge and
  /// a shadow drawn in the same shade would fuse into one ring under the
  /// button's own corner curve.
  static const double _outlineDarken = 0.28;
  static const double _collarDarken = 0.18;

  /// The gloss along a button's top, front to back. A flat highlight
  /// gradient rather than a lit-from-above shader: cheap, and it is what
  /// turns a flat fill into something that reads as a rounded, pressable cap.
  static const Color _glossTop = Color(0x59FFFFFF);
  static const Color _glossBottom = Color(0x00FFFFFF);

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

  /// How far the work has got, between 0 and 1, drawn as a fill that grows
  /// across the button. Null when the button is not working.
  ///
  /// The label stays readable, unlike under [busy]: a measured wait says how
  /// much longer, so there is no reason to take the words away as well.
  final double? progress;

  /// What a screen reader announces. Null on a labelled button, which reads its
  /// own label.
  final String? semanticsLabel;

  /// Takes the keyboard when first built, unless something else in its focus
  /// scope already has it.
  final bool autofocus;

  const AppButton({
    required this.child,
    required this.onPress,
    this.icon,
    this.iconSide = AppButtonIconSide.leading,
    this.tone = AppButtonTone.primary,
    this.busy = false,
    this.progress,
    this.autofocus = false,
    super.key,
  }) : semanticsLabel = null,
       assert(progress == null || !busy, 'a button says how far it has got, or that it is working, not both');

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
    this.autofocus = false,
    super.key,
  }) : child = null,
       busy = false,
       progress = null,
       iconSide = AppButtonIconSide.leading;

  /// What the button is filled with in [states].
  ///
  /// A filled tone fades its own colour. An outlined one has no colour to fade
  /// — its face *is* the page — so it tints with the ink instead, which is the
  /// only thing that gives it a hover and a press at all.
  ///
  /// The outlined face is opaque, blended onto [background], because the collar
  /// is a shadow drawn under the whole shape and would show through a
  /// transparent face.
  Color _fillFor(
    Set<FTappableVariant> states, {
    required Color background,
    required Color foreground,
  }) {
    if (tone == AppButtonTone.outline) {
      return switch (states) {
        _ when states.contains(FTappableVariant.disabled) => background,
        _ when states.contains(FTappableVariant.pressed) =>
          Color.alphaBlend(foreground.withValues(alpha: 0.16), background),
        _ when states.contains(FTappableVariant.hovered) =>
          Color.alphaBlend(foreground.withValues(alpha: 0.08), background),
        _ => background,
      };
    }

    return switch (states) {
      _ when states.contains(FTappableVariant.disabled) => background.withValues(alpha: 0.4),
      _ when states.contains(FTappableVariant.pressed) => background.withValues(alpha: 0.75),
      _ when states.contains(FTappableVariant.hovered) => background.withValues(alpha: 0.86),
      _ => background,
    };
  }

  /// The label, the glyph, or both — and **always at the same height**.
  ///
  /// A button's height must not depend on what is in it: a row puts a back
  /// chevron beside a word, and [AppButtonRow] wraps, so there is nothing above
  /// to equalise them afterwards the way an `IntrinsicHeight` once did. The two
  /// invisible children settle it — the label face's own line height, and the
  /// glyph's box — and neither is a measurement guessed at here: the first is
  /// asked of the font through the ambient [DefaultTextStyle], the second is
  /// [_iconSize] itself. Both are zero-wide, so neither can widen the button.
  ///
  /// Centred, so a button next to a taller neighbour keeps its content in the
  /// middle.
  Widget _buildContent(Color foreground, {required bool enabled}) {
    final glyph = icon == null
        ? null
        : Icon(icon, size: _iconSize, color: foreground.withValues(alpha: enabled ? 1 : 0.6));

    return Stack(
      alignment: Alignment.center,
      children: [
        const Text(''),
        const SizedBox(height: _iconSize),
        if (child == null)
          glyph!
        else if (glyph == null)
          child!
        else
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (iconSide == AppButtonIconSide.leading) ...[glyph, const SizedBox(width: _iconGap)],
              child!,
              if (iconSide == AppButtonIconSide.trailing) ...[const SizedBox(width: _iconGap), glyph],
            ],
          ),
      ],
    );
  }

  /// The fill that says how far [progress] has got.
  ///
  /// Clipped to the button's own shape, so a full bar has the button's corners
  /// rather than square ones. Tinted with the foreground rather than given a
  /// colour of its own, which is what lets one rule cover all three tones,
  /// including the outlined one that has no fill to darken.
  ///
  /// It grows into each new value instead of jumping: a partial flash reports
  /// five times in two seconds, and five steps read as a stutter. Short enough
  /// that the fill has arrived before the next report does, or it lags behind
  /// what the button is saying.
  Widget _buildProgress(BuildContext context, Color foreground) {
    return ClipPath(
      clipper: ShapeBorderClipper(shape: squircle(kControlCornerRadius)),
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: progress!.clamp(0, 1)),
        duration: context.motion(const Duration(milliseconds: 180)),
        curve: Curves.easeOut,
        builder: (context, fraction, _) => Align(
          alignment: AlignmentDirectional.centerStart,
          child: FractionallySizedBox(
            widthFactor: fraction,
            heightFactor: 1,
            child: ColoredBox(color: foreground.withValues(alpha: 0.22)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final semantic = context.appTheme.colors;
    final enabled = onPress != null;

    // An outlined button MUST sit on the page: its face is the page's colour.
    final (background, foreground) = switch (tone) {
      AppButtonTone.primary => (theme.colors.primary, theme.colors.primaryForeground),
      AppButtonTone.neutral => (semantic.neutralButton, semantic.neutralButtonForeground),
      AppButtonTone.outline => (theme.colors.background, semantic.neutralButton),
    };

    // The outlined tone's edge and collar are its ink: a darker shade of the
    // page would be as faint as a card's border.
    final (edge, collar) = tone == AppButtonTone.outline
        ? (semantic.neutralButton, semantic.neutralButton)
        : (background.darken(_outlineDarken), background.darken(_collarDarken));
    final outlineColor = edge.withValues(alpha: enabled ? 1 : 0.4);
    final collarColor = collar.withValues(alpha: enabled ? 1 : 0.4);

    return FTappable(
      onPress: onPress,
      autofocus: autofocus,
      semanticsButton: true,
      semanticsLabel: semanticsLabel,
      builder: (context, states, child) {
        // Pressed sinks the face into the collar instead of just losing its
        // shadow: the shadow's own bottom edge is where the translated face
        // lands, so the button's bottom edge does not appear to move.
        final pressed = states.contains(FTappableVariant.pressed);

        final decorated = DecoratedBox(
          decoration: ShapeDecoration(
            color: _fillFor(states, background: background, foreground: foreground),
            shape: squircle(
              kControlCornerRadius,
              side: BorderSide(color: outlineColor, width: _bevelOutlineWidth),
            ),
            shadows: !pressed
                ? [BoxShadow(color: collarColor, offset: const Offset(0, _collarHeight))]
                : null,
          ),
          child: ClipPath(
            clipper: ShapeBorderClipper(shape: squircle(kControlCornerRadius)),
            child: Stack(
              children: [
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [_glossTop, _glossBottom],
                        stops: [0, 0.6],
                      ),
                    ),
                  ),
                ),
                if (progress != null) Positioned.fill(child: _buildProgress(context, foreground)),
                Padding(
                  // The design's own measurements: 38 across, 19 down.
                  padding: this.child == null ? _iconPadding : _labelPadding,
                  child: child,
                ),
              ],
            ),
          ),
        );

        // Transform, not a resize: the same reason `busy` keeps the label's
        // own box laid out. A button that grew or shrank on press would also
        // shift whatever sits below it in an [AppButtonRow].
        return Transform.translate(offset: Offset(0, pressed ? _collarHeight : 0), child: decorated);
      },
      child: DefaultTextStyle(
        // The heading face, so a button reads as part of the same playful set
        // as the titles rather than as a label in the body face.
        style: context.appTheme.text.label.copyWith(
          fontFamily: kDisplayFontFamily,
          fontSize: 19,
          fontWeight: FontWeight.w600,
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
