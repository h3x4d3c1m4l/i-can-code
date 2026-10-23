import 'package:flutter/widgets.dart';
import 'package:i_can_code/views/catalog_screen/components/catalog_tile.dart';
import 'package:i_can_code/views/components/bevelled_card.dart';

/// [CatalogTile]s in rows: as many to a row as fit [width] at [minTileWidth]
/// or wider, and never more than [maxColumns].
///
/// Every tile is built, on screen or not. An address scrolls to a tile by the
/// scroll extent of what is above it, and a lazy grid only estimates the rows
/// it has not laid out. Rows of a set height rather than a `Wrap`, whose tile
/// widths can add up to a hair over [width] and push the last one onto a row
/// of its own.
class TileGrid extends StatelessWidget {

  static const double columnGap = 20;

  /// The collar under a tile takes part of the gap below it.
  static const double rowGap = columnGap + BevelledCard.collarHeight;

  static const double minTileWidth = 240;
  static const int maxColumns = 4;

  /// The width the rows are laid out in. Passed in rather than measured, so the
  /// view decides it from `MediaQuery` during its own build.
  final double width;

  final List<Widget> children;

  const TileGrid({required this.width, required this.children, super.key});

  static int columnsFor(double width) =>
      ((width + columnGap) / (minTileWidth + columnGap)).floor().clamp(1, maxColumns);

  @override
  Widget build(BuildContext context) {
    final columns = columnsFor(width);
    final tileWidth = (width - (columns - 1) * columnGap) / columns;
    final tileHeight = CatalogTile.heightFor(context, tileWidth);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var start = 0; start < children.length; start += columns) ...[
          if (start > 0) const SizedBox(height: rowGap),
          SizedBox(
            height: tileHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var column = 0; column < columns; column++) ...[
                  if (column > 0) const SizedBox(width: columnGap),
                  Expanded(child: start + column < children.length ? children[start + column] : const SizedBox()),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

}
