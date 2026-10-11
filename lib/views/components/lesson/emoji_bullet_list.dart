import 'package:flutter/widgets.dart';

/// A list whose items each carry an emoji of their own where a bullet would be.
///
/// The emoji sits in a gutter and the item's prose starts after it, so a line
/// that wraps stays clear of the emoji the way it stays clear of a bullet.
class EmojiBulletList extends StatelessWidget {

  /// The gutter's width in ems of [style]. Noto Color Emoji advances 1.245 em,
  /// which leaves a little over half an em between the emoji and the prose.
  static const double _gutterEms = 1.8;

  /// Each item's emoji, and its prose already rendered.
  final List<({String emoji, Widget child})> items;

  /// What the emoji is drawn in. SHOULD be the prose's own body style, so the
  /// emoji is the size of the text beside it.
  final TextStyle style;

  /// Space between two items.
  final double spacing;

  const EmojiBulletList({required this.items, required this.style, this.spacing = 0, super.key});

  @override
  Widget build(BuildContext context) {
    final gutter = (style.fontSize ?? 16) * _gutterEms;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (index, item) in items.indexed) ...[
          if (index > 0) SizedBox(height: spacing),
          Row(
            // On the first line of the prose, not centred on an item that
            // wrapped.
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              SizedBox(
                width: gutter,
                child: Text(item.emoji, style: style, softWrap: false, overflow: TextOverflow.visible),
              ),
              Expanded(child: item.child),
            ],
          ),
        ],
      ],
    );
  }

}
