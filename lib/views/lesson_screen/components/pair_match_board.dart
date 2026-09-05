import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/services/lessons/lesson.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/shape_metrics.dart';
import 'package:i_can_code/views/lesson_screen/components/lesson_prose.dart';
import 'package:i_can_code/views/lesson_screen/components/verdict_banner.dart';

/// How a board deals its tiles: every half of every one of [count] pairs, in one
/// order.
///
/// **One pool.** Kept in a block of cues and a block of answers, the board tells
/// the student before they have read a word that a tile from the one goes with a
/// tile from the other — which is half of every pair narrowed down for them, and
/// the half a matching game is for.
///
/// Derived from [seed] rather than taken from a fresh [math.Random], because the
/// board is rebuilt constantly — every pick, every hover, every resize, every
/// change of language — and a shuffle per build would move the tiles under the
/// reader's hand. The seed is the section's id, so the same board comes back
/// after a step away and stands the same in either translation.
///
/// Deliberately **not** [String.hashCode], which Dart promises nothing about
/// between releases.
List<PairHalf> boardOrder(String seed, int count) {
  var hash = 17;
  for (final unit in seed.codeUnits) {
    hash = (hash * 31 + unit) & 0x3FFFFFFF;
  }

  final tiles = <PairHalf>[
    for (var pair = 0; pair < count; pair++) ...[(pair: pair, cue: true), (pair: pair, cue: false)],
  ]..shuffle(math.Random(hash));

  // A deal that comes back in the lesson's own order stands every pair side by
  // side, in the order the file lists them. Rotated rather than dealt again,
  // which could land the same way a second time.
  final givenAway = tiles.indexed.every((entry) => entry.$2 == _asWritten(entry.$1));
  if (givenAway && tiles.length > 1) return [...tiles.skip(1), tiles.first];

  return tiles;
}

/// The tile that would stand at [position] if the board were never dealt at all.
PairHalf _asWritten(int position) => (pair: position ~/ 2, cue: position.isEven);

/// A [SectionKind.matchPairs] step's board: a column of cue tiles and a column
/// of answer tiles, both dealt by [boardOrder].
///
/// One grid holding every half of every pair, dealt together by [boardOrder]:
/// a tile says nothing about which half of its pair it is, and the student picks
/// any two tiles that belong together.
///
/// **Every tile is a square**, [tileSizeFor] wide. A square has no reading
/// direction, so unlike a bar of text it does not have to be as wide as the
/// words in it, and the board can fit as many across as the page allows.
///
/// Stateless: what has been matched and what is picked belong to the step and
/// live in `LessonScreenViewModel`, so stepping away and back finds the board as
/// it was left.
class PairMatchBoard extends StatelessWidget {

  /// Between two tiles, across and down.
  static const double gap = 12;

  /// How small a tile may get before the board takes one off the row.
  ///
  /// Under this the words stop fitting the square they are centred in and start
  /// scrolling inside it, which is a tile that cannot be read at a glance.
  static const double minTileSize = 140;

  /// How large a tile may get.
  ///
  /// A square grows with the room it is given, and past this it is a poster with
  /// three lines of text adrift in the middle. Extra width goes into *more*
  /// tiles per row; when there are no more tiles to place, it is simply left
  /// over and the row sits centred in it.
  static const double maxTileSize = 220;

  /// How wide one tile is on a board [width] across holding [count] of them.
  ///
  /// Fits as many into a row as it can without any falling under [minTileSize],
  /// starting from all of them in one row — so a wider board holds more tiles
  /// rather than bigger ones. The last row of a block may be short; [Wrap]
  /// centres it.
  static double tileSizeFor(double width, int count) {
    for (var columns = count; columns > 1; columns--) {
      final side = (width - gap * (columns - 1)) / columns;
      if (side >= minTileSize) return math.min(side, maxTileSize);
    }

    // Narrower than two tiles can be: one per row, and it may still be under
    // [minTileSize] — a board has to draw itself at whatever width it is given.
    return math.min(width, maxTileSize);
  }

  /// What both columns are dealt by — the section's own id. See [boardOrder].
  final String seed;

  final List<LessonPair> pairs;

  /// Which pairs are already together, as indices into [pairs].
  final Set<int> matched;

  /// The tiles standing picked, at most two.
  final Set<PairHalf> picked;

  final ValueChanged<PairHalf> onPick;

  const PairMatchBoard({
    required this.seed,
    required this.pairs,
    required this.matched,
    required this.picked,
    required this.onPick,
    super.key,
  });

  bool get _solved => matched.length == pairs.length;

  /// Two tiles are picked, which can only mean they do not belong together — a
  /// pair that matched would have cleared them both. They stay showing until the
  /// next tap, which is the only feedback a wrong guess gets.
  bool get _wrong => picked.length == 2;

  @override
  Widget build(BuildContext context) {
    final tiles = boardOrder(seed, pairs.length);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          context.localizations.lessonScreen_pairsHint,
          style: context.appTheme.text.bodySmall.copyWith(
            fontSize: 16,
            color: context.theme.colors.mutedForeground,
          ),
        ),
        const SizedBox(height: 18),
        // Reads the width the step gives it and nothing observable: the state
        // and the words both arrived as fields, read inside the lesson screen's
        // `Observer` before they got here. A [LayoutBuilder] that reached for a
        // store instead would read it at layout time, outside the window that
        // `Observer` tracks.
        LayoutBuilder(
          builder: (context, constraints) {
            final side = tileSizeFor(constraints.maxWidth, tiles.length);

            return Wrap(
              spacing: gap,
              runSpacing: gap,
              // A short last row sits under the middle of the one above rather
              // than against an edge, which would read as a column that ran out.
              alignment: WrapAlignment.center,
              children: [
                for (final tile in tiles) SizedBox.square(dimension: side, child: _buildTile(tile, side)),
              ],
            );
          },
        ),
        if (_solved) ...[
          const SizedBox(height: 20),
          VerdictBanner(
            background: context.appTheme.colors.successSurface,
            child: Text(
              context.localizations.lessonScreen_passed,
              style: context.appTheme.text.h3.copyWith(fontSize: 18),
            ),
          ),
        ],
      ],
    );
  }

  /// One tile, in whichever state the picks and the matches leave it.
  Widget _buildTile(PairHalf tile, double side) {
    final standing = picked.contains(tile);

    final state = matched.contains(tile.pair)
        ? _TileState.matched
        : standing && _wrong
        ? _TileState.wrong
        : standing
        ? _TileState.picked
        : _TileState.idle;

    return _Tile(
      text: tile.cue ? pairs[tile.pair].cue : pairs[tile.pair].answer,
      state: state,
      fontSize: _fontSizeFor(side),
      // A matched tile is done: it keeps its place so the board does not
      // reshuffle itself under the reader, but it no longer answers a tap.
      onPress: state == _TileState.matched ? null : () => onPick(tile),
    );
  }

  /// The words, as a share of the tile they sit in.
  ///
  /// Set to the tile rather than to a number, because the tile is set to the
  /// page: one width makes a 220px square and another a 150px one, and a fixed
  /// 16px is adrift in the first and spilling out of the second. Clamped at both
  /// ends, where the share stops reading as text.
  static double _fontSizeFor(double side) => (side * 0.075).clamp(14.0, 22.0);

}

/// What a tile is saying about itself.
enum _TileState { idle, picked, wrong, matched }

class _Tile extends StatelessWidget {

  /// The tile's edge, the same width in every state.
  ///
  /// A [ShapeDecoration] insets its child by the shape's own dimensions, so a
  /// border that thickened on a pick would nudge the words inside it. Only the
  /// colour changes.
  static const double _borderWidth = 2;

  static const Duration _settle = Duration(milliseconds: 150);

  /// Air between the square's edge and the words in it.
  static const EdgeInsets _padding = EdgeInsets.all(18);

  /// Inline markdown, the way a section's prose is — a tile may name a function
  /// in `code` spans.
  final String text;

  final _TileState state;

  /// Set by the board, which is what knows how large a tile came out.
  final double fontSize;

  /// Null on a matched tile, which is done and no longer a control.
  final VoidCallback? onPress;

  const _Tile({required this.text, required this.state, required this.fontSize, this.onPress});

  /// The glyph that says what the colour says, for a reader the colour does not
  /// reach.
  IconData? get _mark => switch (state) {
    _TileState.matched => FLucideIcons.check,
    _TileState.wrong => FLucideIcons.x,
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final tokens = context.appTheme;

    // Every fill here is a surface the page's own ink is legible on, which is
    // what lets the text keep one colour through all four states.
    final (fill, edge) = switch (state) {
      _TileState.idle => (theme.colors.card, theme.colors.border),
      _TileState.picked => (theme.colors.card, theme.colors.foreground),
      _TileState.wrong => (tokens.colors.warningSurface, tokens.colors.warning),
      _TileState.matched => (tokens.colors.successSurface, tokens.colors.success),
    };

    return FTappable(
      onPress: onPress,
      semanticsButton: true,
      builder: (context, states, child) => AnimatedContainer(
        duration: context.motion(_settle),
        curve: Curves.easeOut,
        decoration: ShapeDecoration(
          color: states.contains(FTappableVariant.hovered)
              ? Color.alphaBlend(theme.colors.foreground.withValues(alpha: 0.06), fill)
              : fill,
          shape: squircle(kControlCornerRadius, side: BorderSide(color: edge, width: _borderWidth)),
        ),
        padding: _padding,
        child: child,
      ),
      child: Stack(
        children: [
          Positioned.fill(
            // The words are centred while they fit and scroll once they do not:
            // a square is a box the lesson author cannot see, and text that
            // outgrew it would overflow rather than merely look cramped.
            // [Center] hands the scroll view loose constraints, so it takes its
            // content's height until there is no more room.
            child: Center(
              child: SingleChildScrollView(
                child: LessonProse(
                  markdown: text,
                  fontSize: fontSize,
                  paragraphSpacing: 0,
                  textAlign: WrapAlignment.center,
                ),
              ),
            ),
          ),
          // In the corner rather than beside the words, which in a square would
          // take a column off the middle of the tile and leave the text sitting
          // to one side of its own box.
          if (_mark case final IconData mark)
            Positioned(top: 0, right: 0, child: Icon(mark, size: 18, color: theme.colors.foreground)),
        ],
      ),
    );
  }

}
