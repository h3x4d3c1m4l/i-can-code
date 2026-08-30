import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

// The corner radii the design uses, in one place. The numbers are the design
// canvas's own, unscaled; [kSquircleScale] carries the conversion.

/// A segment of the lesson progress bar.
const double kProgressCornerRadius = 5;

/// A tab, a chip or a badge — the language toggle, the "Opdracht" label.
const double kChipCornerRadius = 12;

/// The app mark tile in the header.
const double kLogoTileCornerRadius = 13;

/// Buttons and status pills: "Run & controleer", "Volgende", "Verder".
const double kControlCornerRadius = 21;

/// A card: a course in the catalog, the output panel, the code editor.
const double kCardCornerRadius = 26;

/// The oversized app mark and ✓ tiles on the login and completion screens.
const double kHeroTileCornerRadius = 40;

/// The height of one progress bar segment.
const double kProgressHeight = 8;

/// The design's radii as forui's own token scale.
///
/// forui styles itself with [BorderRadius], which cannot take a [ShapeBorder],
/// so a forui widget gets the right *radius* but not the squircle curve. forui
/// names these by size, so the mapping lands the sizes the design uses on the
/// tokens its widgets reach for most: `xl` for controls, `xl2` for cards.
final FBorderRadius kBorderRadius = FBorderRadius(
  xs2: BorderRadius.all(Radius.circular(kProgressCornerRadius * kSquircleScale)),
  xs: BorderRadius.all(Radius.circular(8 * kSquircleScale)),
  sm: BorderRadius.all(Radius.circular(kChipCornerRadius * kSquircleScale)),
  md: BorderRadius.all(Radius.circular(kLogoTileCornerRadius * kSquircleScale)),
  lg: BorderRadius.all(Radius.circular(18 * kSquircleScale)),
  xl: BorderRadius.all(Radius.circular(kControlCornerRadius * kSquircleScale)),
  xl2: BorderRadius.all(Radius.circular(kCardCornerRadius * kSquircleScale)),
  xl3: BorderRadius.all(Radius.circular(kHeroTileCornerRadius * kSquircleScale)),
);

/// How much larger a [ContinuousRectangleBorder]'s radius has to be to look like
/// the CSS `corner-shape: squircle` the design was drawn with.
///
/// Eyeballed, not derived: the two curves differ, and at an equal radius Flutter's
/// reads tighter. Turn this one number if the corners look wrong.
const double kSquircleScale = 1.5;

/// The app's corner, at a radius stated in the design's own numbers. Every
/// rounded corner in the app goes through this.
///
/// MUST be used with a [ShapeDecoration]; `BoxDecoration.borderRadius` can only
/// draw a plain rounded rectangle.
///
/// A [ContinuousRectangleBorder] does **not** clamp an over-large radius — past
/// half the shortest side it bows inward — so callers MUST keep
/// `radius * kSquircleScale` under that. [squircleOf] does it for a known size.
ShapeBorder squircle(double radius, {BorderSide side = BorderSide.none}) =>
    ContinuousRectangleBorder(borderRadius: BorderRadius.circular(radius * kSquircleScale), side: side);

/// [squircle] clamped to what a box of [size] can take. For small square tiles,
/// where the scaled radius would otherwise deform the shape.
ShapeBorder squircleOf(double radius, {required double size, BorderSide side = BorderSide.none}) =>
    ContinuousRectangleBorder(
      borderRadius: BorderRadius.circular((radius * kSquircleScale).clamp(0, size / 2)),
      side: side,
    );
