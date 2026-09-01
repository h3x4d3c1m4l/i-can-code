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

  /// [red] at the handbook's 50% tint — the destructive colour of the dark
  /// scheme. Takes [corporateGrey] text at 6.10:1.
  ///
  /// [red] itself reaches only 2.70:1 on a [corporateGrey] page and cannot be
  /// used there. 50% rather than a darker tint because the message also lands
  /// on a [greyDark] card, where 60% would fall to 3.84:1.
  static const Color redTint50 = Color(0xFFE4A19E);

  /// [corporateGreen] at the handbook's 60% tint — prose links on a dark page,
  /// at 7.40:1 (5.51:1 on a [greyDark] card).
  ///
  /// The green itself is a fill and cannot be text; see [corporateGreen].
  static const Color greenTint60 = Color(0xFFC5CA66);

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

  /// White at 65% over [corporateGrey] — the muted text of the dark scheme.
  ///
  /// [greyOn55] cannot serve there: the dark scheme's card is [greyDark], not
  /// [corporateGrey], and 55% reaches only 3.77:1 on it. This one is 4.81:1 on
  /// the card and 6.46:1 on the page.
  static const Color greyOn65 = Color(0xFFB2B8BD);

  /// [corporateGrey] darkened one step — the code surface of the dark scheme,
  /// so the editor still reads as a card against a [corporateGrey] page.
  static const Color greyDeep = Color(0xFF1A2833);

  // ------------------------------------------------------- secondary surfaces

  /// [corporateGreen] at 20%. Takes [corporateGrey] text at 10.82:1.
  static const Color greenSurface = Color(0xFFECEDCC);

  /// [red] at 15%.
  static const Color redSurface = Color(0xFFF7E3E2);

  /// [yellow] at 15%.
  static const Color yellowSurface = Color(0xFFFFF5D9);

  // -------------------------------------------- secondary surfaces, dark mode

  /// A white tint cannot make a dark surface, so the dark scheme's quiet fills
  /// are derived the other way: the brand colour at **30% over
  /// [corporateGrey]**, the page it sits on. Same discipline as the tints above
  /// — a blend at a stated percentage, never a colour picked by eye.
  ///
  /// [corporateGreen] over the page. Takes [grey08] text at 6.90:1.
  static const Color greenSurfaceDark = Color(0xFF47562F);

  /// [red] over the page. Takes [grey08] text at 9.02:1.
  static const Color redSurfaceDark = Color(0xFF543841);

  /// [yellow] over the page. Takes [grey08] text at 5.85:1.
  static const Color yellowSurfaceDark = Color(0xFF645C2F);

}
