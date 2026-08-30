import 'package:flutter/painting.dart';

/// The De Haagse Hogeschool house style, transcribed from the huisstijlhandboek
/// (page 46, `ONZE KLEUREN`).
///
/// Nothing here is invented: every value is a handbook colour or a tint at a
/// percentage it sanctions (5–80%). A missing colour MUST be derived the same
/// way — blend the brand colour with white at the tint percentage — never picked
/// by eye.
abstract final class ThuasPalette {

  // ---------------------------------------------------------------- primaries

  /// Corporate groen — PMS 2305, CMYK 25/0/100/32, RGB 158/167/0.
  ///
  /// A fill only: 2.63:1 on white, and it cannot carry white text either.
  /// Anything drawn on it MUST use [corporateGrey], which reaches 4.92:1.
  static const Color corporateGreen = Color(0xFF9EA700);

  /// Corporate grijs — PMS 432, CMYK 67/45/27/70, RGB 34/51/67. The app's text
  /// colour, its dark surface, and what sits on top of every fill.
  static const Color corporateGrey = Color(0xFF223343);

  // ----------------------------------------------------- handbook variants

  /// CMYK 25/0/100/38 — the handbook's darker corporate green.
  static const Color greenDark = Color(0xFF909806);

  /// CMYK 25/0/100/26 — the handbook's lighter corporate green.
  static const Color greenLight = Color(0xFFA8AD00);

  /// CMYK 81/64/41/38 — the handbook's darker corporate grey.
  static const Color greyDark = Color(0xFF3B4559);

  /// CMYK 71/55/33/23 — the handbook's mid corporate grey.
  static const Color greyMid = Color(0xFF4E5B73);

  // -------------------------------------------------------------- secondaries

  /// PMS 711, CMYK 15/88/82/4, RGB 202/67/60. Carries white text at 4.80:1.
  static const Color red = Color(0xFFCA433C);

  /// PMS 7408, CMYK 0/29/100/0, RGB 255/186/0.
  ///
  /// Far too light for white text (1.71:1); pair it with [corporateGrey], which
  /// reaches 7.57:1.
  static const Color yellow = Color(0xFFFFBA00);

  /// PMS 3125, CMYK 89/0/20/0, RGB 0/178/205. The house colour for bachelor
  /// programmes. Unused so far.
  static const Color cyan = Color(0xFF00B2CD);

  // --------------------------------------------------------------- grey tints

  /// [corporateGrey] at 5% — the page behind the cards.
  static const Color grey05 = Color(0xFFF4F5F6);

  /// [corporateGrey] at 8%. Doubles as the foreground on a [corporateGrey]
  /// surface — white at 92% over it lands on this same value.
  static const Color grey08 = Color(0xFFEDEFF0);

  /// [corporateGrey] at 10%.
  static const Color grey10 = Color(0xFFE9EBEC);

  /// [corporateGrey] at 15% — borders and hairlines.
  static const Color grey15 = Color(0xFFDEE0E3);

  /// [corporateGrey] at 70% — the quietest text that still clears AA on white,
  /// at 5.07:1.
  static const Color grey70 = Color(0xFF64707B);

  /// White at 55% over [corporateGrey] — the quietest text that still clears AA
  /// *on* the corporate grey, at 5.07:1.
  static const Color greyOn55 = Color(0xFF9CA3AA);

  // ------------------------------------------------------- secondary surfaces

  /// [corporateGreen] at 20%. Takes [corporateGrey] text at 10.82:1.
  static const Color greenSurface = Color(0xFFECEDCC);

  /// [red] at 15%.
  static const Color redSurface = Color(0xFFF7E3E2);

  /// [yellow] at 15%.
  static const Color yellowSurface = Color(0xFFFFF5D9);

}
