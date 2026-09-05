import 'package:flutter/painting.dart';

/// The unbranded preset's colours.
///
/// Neobrutalism **as a palette only** — the loud flat accent, the cream page,
/// the near-black ink. None of the movement's other devices are borrowed: no
/// thick outlines, no hard offset shadows. The app's squircles, its type scale
/// and its button metrics are unchanged.
///
/// Every fill states its contrast against the foreground it is paired with.
/// Those pairings are asserted in `test/theme/theme_test.dart`; a value changed
/// here MUST keep them clearing WCAG AA.
abstract final class NeobrutalismPalette {

  // ------------------------------------------------------------------ accent

  /// The main accent, in both modes. Fills the catalog's number tiles and every
  /// primary button.
  ///
  /// A fill only: 1.2:1 on [pageLight], so it can never carry text. Anything
  /// drawn on it MUST use [inkLight], which reaches 14.74:1. Prose links use
  /// [linkLight] / [linkDark] instead, which is why `link` exists as a role.
  static const Color accent = Color(0xFFFFDC58);

  /// A step already finished, in both modes: the progress bar's filled segments
  /// and the badge on a completed row.
  ///
  /// Brighter and more saturated than [successLight], which it used to borrow.
  /// The two mean different things — "your check passed" against "this is
  /// done" — and this one is lit: it carries a glow, and a deeper green went
  /// muddy under one. A fill only, like [accent]; [inkLight] takes 11.86:1 on
  /// it and white would reach 1.8:1.
  static const Color complete = Color(0xFF00E676);

  // ------------------------------------------------------------------- light

  /// The page. Cream rather than white, so a white card reads against it.
  static const Color pageLight = Color(0xFFFFF4E0);

  /// A card, and the surface the prose sits on.
  static const Color cardLight = Color(0xFFFFFFFF);

  /// Body text. 18.17:1 on [pageLight], 19.80:1 on [cardLight].
  static const Color inkLight = Color(0xFF0A0A0A);

  /// The quietest text that still clears AA on [pageLight], at 5.52:1. A warm
  /// grey, so it belongs to the cream rather than sitting on it.
  static const Color inkMutedLight = Color(0xFF6B6250);

  /// The quieter button beside the accent — what `AppButtonTone.neutral` is
  /// filled with, and what `AppButtonTone.outline` draws its edge and its label
  /// in.
  ///
  /// **Not [inkLight].** Body text is near black because prose has to be read;
  /// a button is a slab of its colour, and at that size near black stops
  /// reading as a control on the cream and starts reading as a hole punched in
  /// it. This is the darkest step of the warm grey [inkMutedLight] belongs to,
  /// so the two are the same colour at two weights rather than a brown beside a
  /// black. It carries [pageLight] at 9.68:1 as a fill, and clears AA as the
  /// outlined button's own text on [pageLight] (9.68:1) and [cardLight]
  /// (10.55:1).
  ///
  /// The dark scheme has no equivalent: an off-white slab on a dark page is
  /// already quiet, so `neutralButton` is [inkDark] there.
  static const Color controlLight = Color(0xFF453E33);

  /// A quiet fill: the blockquote, a hovered menu row. A tint of [accent].
  static const Color secondaryLight = Color(0xFFFFE9A8);

  /// The quietest fill, a shade off [pageLight].
  static const Color mutedLight = Color(0xFFF4EADB);

  /// Borders and hairlines.
  static const Color borderLight = Color(0xFFE0D6C2);

  /// Destructive and error. Carries white text at 4.70:1 — the tightest pair in
  /// the palette.
  static const Color dangerLight = Color(0xFFE11D48);

  /// Prose links. 6.75:1 on [pageLight], 7.35:1 on [cardLight]. [accent] cannot
  /// serve here; see its own doc.
  static const Color linkLight = Color(0xFF2D3DE0);

  /// A passed assignment. Takes [inkLight] at 6.01:1.
  static const Color successLight = Color(0xFF16A34A);

  /// The quiet fill behind a "Goed!" message.
  static const Color successSurfaceLight = Color(0xFFC4F0C0);

  /// A check that has not passed yet. Takes [inkLight] at 12.04:1.
  static const Color warningLight = Color(0xFFFFBF3F);

  /// The quiet fill behind a "Nog niet" message.
  static const Color warningSurfaceLight = Color(0xFFFFE9A8);

  /// The quiet fill behind an error message.
  static const Color errorSurfaceLight = Color(0xFFFFD4D9);

  // -------------------------------------------------------------------- dark

  /// The page.
  static const Color pageDark = Color(0xFF232332);

  /// A card, a shade above [pageDark].
  static const Color cardDark = Color(0xFF2E2F42);

  /// Body text. 13.37:1 on [pageDark], 11.34:1 on [cardDark]. Off-white rather
  /// than white, which is what keeps a dark page from glaring.
  static const Color inkDark = Color(0xFFEEEFE9);

  /// The quietest text that still clears AA on [cardDark], at 5.69:1 (6.71:1 on
  /// [pageDark]). Measured against the card, which is the tighter of the two.
  static const Color inkMutedDark = Color(0xFFA8AAB8);

  /// A quiet fill: the blockquote, a hovered menu row.
  static const Color secondaryDark = Color(0xFF3A3B50);

  /// The quietest fill, between [pageDark] and [secondaryDark].
  static const Color mutedDark = Color(0xFF33344A);

  /// Borders and hairlines.
  static const Color borderDark = Color(0xFF43445C);

  /// Destructive and error. Too light for white text (1.6:1); it takes
  /// [inkLight] at 7.95:1.
  static const Color dangerDark = Color(0xFFFF7A8F);

  /// Prose links. 7.18:1 on [pageDark], 6.09:1 on [cardDark].
  static const Color linkDark = Color(0xFF8BB0FF);

  /// A passed assignment. Takes [inkLight] at 11.21:1.
  static const Color successDark = Color(0xFF69D98A);

  /// The quiet fill behind a "Goed!" message. Takes [inkDark] at 10.79:1.
  static const Color successSurfaceDark = Color(0xFF1B3A28);

  /// The quiet fill behind a "Nog niet" message. Takes [inkDark] at 11.37:1.
  static const Color warningSurfaceDark = Color(0xFF3D2E10);

  /// The quiet fill behind an error message. Takes [inkDark] at 13.00:1.
  static const Color errorSurfaceDark = Color(0xFF3E1C24);

  // ------------------------------------------------------------------- code

  /// The editor and the sample snippets, in **both** modes: the code surface is
  /// a dark card either way, and the syntax theme drawn on it
  /// (`re_highlight`'s atom-one-dark) is fixed.
  static const Color codeSurface = Color(0xFF171717);

  /// Code on [codeSurface], at 16.44:1.
  static const Color codeInk = Color(0xFFF5F5F5);

  /// The editor's chrome — the `main.py` label, the runtime status. 7.11:1.
  static const Color codeInkMuted = Color(0xFFA3A3A3);

}
