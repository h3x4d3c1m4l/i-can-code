import 'dart:math' as math;

import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/shape_metrics.dart';

/// The order the available lines are laid out in: every line of the pool, once.
///
/// Derived from [seed] rather than from a fresh [math.Random], for the reason
/// `boardOrder` is: the board is rebuilt on every move, every resize and every
/// change of language, and a shuffle per build would move the lines under the
/// reader's hand mid-puzzle.
///
/// **The one deal it refuses is the author's own order**, which is the answer.
/// A board that came back in it would hand the student the solution to read off
/// from top to bottom.
///
/// Deliberately not [String.hashCode], which Dart promises nothing about between
/// releases.
List<int> bankOrder(String seed, int count) {
  var hash = 17;
  for (final unit in seed.codeUnits) {
    hash = (hash * 31 + unit) & 0x3FFFFFFF;
  }

  final order = [for (var index = 0; index < count; index++) index]..shuffle(math.Random(hash));

  // Rotated rather than dealt again, which could land the same way a second
  // time. One line cannot be rotated out of its own order, but a board of one
  // is not a puzzle and the parser refuses it.
  final asWritten = order.indexed.every((entry) => entry.$1 == entry.$2);
  if (asWritten && order.length > 1) return [...order.skip(1), order.first];

  return order;
}

/// A line in flight: which line of the pool it is, and where it was picked up.
///
/// [from] is its position in the assembled program, or null when it came from
/// the available lines. The two are different drops — one moves a line, the
/// other places it — and the target cannot tell them apart from the line alone.
typedef DraggedLine = ({int line, int? from});

/// A [SectionKind.orderLines] step's board: the lines still available above, the
/// program the student has assembled below.
///
/// **Dragged, and tappable as well.** A line is dropped between any two others,
/// which is what ordering actually is; tapping an available line still appends
/// it, because a drag asks for a pointer and a steady hand that not every
/// student brings. Neither path is the only one:
///
/// - Flutter's `ReorderableListView` is a **Material** widget this app does not
///   use, and its widgets-layer cousin wants a viewport of its own — nested
///   inside the step's scroll view it would fight it. So the drag is built here
///   from [LongPressDraggable] and [DragTarget], which are plain widgets.
/// - **A plain [Draggable] loses to the page it sits in.** Its recogniser
///   competes in the gesture arena with the scroll view wrapping every step,
///   and on touch the scroll wins — the page slides and the line stays put. A
///   press-and-hold of [dragDelay] settles the arena first. It is short enough
///   that a mouse, which is not competing for the same gesture, barely notices.
/// - **A drag is not reachable by keyboard or screen reader**, so every placed
///   line carries `customSemanticsActions` for moving it up and down. That is
///   what the two arrow buttons used to be, and it MUST NOT be dropped along
///   with them.
///
/// Stateless: what has been arranged belongs to the step and lives in
/// `LessonScreenViewModel`, so stepping away and back finds the board as it was
/// left.
class LineOrderingBoard extends StatelessWidget {

  /// The gap between two lines, and the height of the drop zone that sits in it.
  static const double gap = 8;

  /// What a drop zone opens to once a line is held over it, so there is
  /// somewhere visible for the line to land.
  static const double openZoneHeight = 44;

  /// The line being carried, so a test can measure it against the row it came
  /// from. See [_LineTile] on why that width has to be handed in.
  static const Key draggedLineKey = ValueKey('line-ordering-dragged');

  /// How long a line is held before it comes off the board.
  ///
  /// Far below `kLongPressTimeout`'s 500ms, which reads as a stall on a mouse,
  /// and far enough above zero that a finger starting to scroll is scrolling
  /// rather than dragging. See the note on the class.
  static const Duration dragDelay = Duration(milliseconds: 150);

  /// What the available lines are dealt by — the section's own id. See
  /// [bankOrder].
  final String seed;

  /// Every line that can be placed: the program's own, then its distractors.
  /// Indices into this list are what [arranged] holds.
  final List<String> pool;

  /// The lines the student has placed, in their order, as indices into [pool].
  final List<int> arranged;

  /// Puts an available line into the program at this position.
  final void Function(int line, int position) onPlace;

  /// Puts the line at this position back among the available ones.
  final ValueChanged<int> onRemove;

  /// Moves the line at one position to another, both counted before the move.
  final void Function(int from, int to) onMove;

  const LineOrderingBoard({
    required this.seed,
    required this.pool,
    required this.arranged,
    required this.onPlace,
    required this.onRemove,
    required this.onMove,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final placed = arranged.toSet();
    final available = bankOrder(seed, pool.length).where((index) => !placed.contains(index)).toList();

    // The one measurement the board needs, taken once and handed down. A
    // [LayoutBuilder] runs its builder at *layout* time, which is outside the
    // window an `Observer` tracks — safe only because everything below reads
    // plain values this widget was given, and no observable at all.
    return LayoutBuilder(
      builder: (context, constraints) => _build(context, available, constraints.maxWidth),
    );
  }

  Widget _build(BuildContext context, List<int> available, double width) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Heading(context.localizations.lessonScreen_orderBank),
        const SizedBox(height: 10),
        // The whole block takes a line dropped back out of the program, so
        // putting one back is a drag as well as a button.
        DragTarget<DraggedLine>(
          onWillAcceptWithDetails: (details) => details.data.from != null,
          onAcceptWithDetails: (details) => onRemove(details.data.from!),
          builder: (context, candidate, _) => _Bank(
            lines: [for (final index in available) (index: index, text: pool[index])],
            onPlace: (line) => onPlace(line, arranged.length),
            highlighted: candidate.isNotEmpty,
            width: width,
          ),
        ),
        const SizedBox(height: 18),
        _Heading(context.localizations.lessonScreen_orderProgram),
        const SizedBox(height: 10),
        if (arranged.isEmpty)
          _DropZone(
            position: 0,
            onPlace: onPlace,
            onMove: onMove,
            child: _EmptyProgram(context.localizations.lessonScreen_orderEmpty),
          )
        else
          for (final (position, index) in arranged.indexed) ...[
            // One zone above every line, and one more below the last, so a line
            // can be dropped at either end as well as between any two.
            _DropZone(position: position, onPlace: onPlace, onMove: onMove),
            _LineTile(
              text: pool[index],
              dragged: (line: index, from: position),
              width: width,
              onRemove: () => onRemove(position),
              onMoveUp: position == 0 ? null : () => onMove(position, position - 1),
              onMoveDown: position == arranged.length - 1 ? null : () => onMove(position, position + 1),
            ),
          ],
        if (arranged.isNotEmpty) _DropZone(position: arranged.length, onPlace: onPlace, onMove: onMove),
      ],
    );
  }

}

/// The lines still to be placed. Draggable, and tappable to append.
class _Bank extends StatelessWidget {

  final List<({int index, String text})> lines;
  final ValueChanged<int> onPlace;

  /// A line from the program is being held over the bank, which would put it
  /// back.
  final bool highlighted;

  /// How wide a row is, for the tile that comes off the board. See [_LineTile].
  final double width;

  const _Bank({required this.lines, required this.onPlace, required this.highlighted, required this.width});

  @override
  Widget build(BuildContext context) {
    final colors = context.appTheme.colors;

    return AnimatedContainer(
      duration: context.motion(const Duration(milliseconds: 120)),
      decoration: ShapeDecoration(
        color: highlighted ? colors.warningSurface : const Color(0x00000000),
        shape: squircle(kCardCornerRadius),
      ),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final line in lines) ...[
            _LineTile(
              text: line.text,
              dragged: (line: line.index, from: null),
              width: width,
              onTap: () => onPlace(line.index),
            ),
            const SizedBox(height: LineOrderingBoard.gap),
          ],
        ],
      ),
    );
  }

}

/// The gap between two placed lines, and the place a dragged one lands.
///
/// Closed it is just the gap; with a line held over it, it opens to a dashed
/// slot the height of a line, so there is somewhere visible for the drop to go.
class _DropZone extends StatelessWidget {

  /// Where a line dropped here ends up, counted before the move.
  final int position;

  final void Function(int line, int position) onPlace;
  final void Function(int from, int to) onMove;

  /// Drawn instead of the slot when the program is still empty — the invitation
  /// stands in for the gap.
  final Widget? child;

  const _DropZone({required this.position, required this.onPlace, required this.onMove, this.child});

  @override
  Widget build(BuildContext context) {
    final colors = context.appTheme.colors;

    return DragTarget<DraggedLine>(
      // A line dropped back where it already is changes nothing, and lighting
      // up the two zones it already touches would promise a move that does not
      // happen.
      onWillAcceptWithDetails: (details) =>
          details.data.from == null || (details.data.from != position && details.data.from != position - 1),
      onAcceptWithDetails: (details) {
        final data = details.data;
        if (data.from case final int from) {
          onMove(from, position);
        } else {
          onPlace(data.line, position);
        }
      },
      builder: (context, candidate, _) {
        final open = candidate.isNotEmpty;

        if (child case final Widget child) {
          return DecoratedBox(
            decoration: ShapeDecoration(
              color: open ? colors.successSurface : const Color(0x00000000),
              shape: squircle(kCardCornerRadius),
            ),
            child: child,
          );
        }

        return AnimatedContainer(
          duration: context.motion(const Duration(milliseconds: 120)),
          height: open ? LineOrderingBoard.openZoneHeight : LineOrderingBoard.gap,
          margin: const EdgeInsets.symmetric(vertical: LineOrderingBoard.gap / 2),
          decoration: ShapeDecoration(
            color: open ? colors.successSurface : const Color(0x00000000),
            shape: squircle(kChipCornerRadius),
          ),
        );
      },
    );
  }

}

class _Heading extends StatelessWidget {

  final String text;

  const _Heading(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: context.appTheme.text.label.copyWith(fontSize: 12, color: context.theme.colors.mutedForeground),
  );

}

class _EmptyProgram extends StatelessWidget {

  final String text;

  const _EmptyProgram(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;

    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: squircle(kCardCornerRadius, side: BorderSide(color: theme.colors.border, width: 2)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: context.appTheme.text.bodySmall.copyWith(fontSize: 15, color: theme.colors.mutedForeground),
        ),
      ),
    );
  }

}

/// One line, on the code card's own dark surface — it is code, and it is read
/// before it is moved.
///
/// Available, tapping it appends it to the program. Placed, it carries the
/// button that puts it back. Either way it can be picked up and dropped
/// somewhere else.
class _LineTile extends StatelessWidget {

  final String text;

  /// What this tile puts on the clipboard of the drag.
  final DraggedLine dragged;

  /// How wide the row is, handed in by the board.
  ///
  /// A [LongPressDraggable]'s `feedback` is mounted in an [Overlay] under
  /// **loose** constraints, so it shrink-wraps its text and the line shrinks to
  /// a stub the moment it is picked up. Nothing in the overlay knows how wide
  /// the row it came from was, so the board measures it once and passes it
  /// down.
  final double width;

  /// Appends the line. Null on a placed line, where a tap would have to mean
  /// two things.
  final VoidCallback? onTap;

  final VoidCallback? onRemove;

  /// The keyboard and screen-reader path to what a drag does with a pointer.
  /// Null at the end of the program it would move past.
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  const _LineTile({
    required this.text,
    required this.dragged,
    required this.width,
    this.onTap,
    this.onRemove,
    this.onMoveUp,
    this.onMoveDown,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTheme;
    final style = tokens.text.code.copyWith(fontSize: 15, height: 1.5, color: tokens.colors.codeForeground);
    final placed = dragged.from != null;

    Widget card({required bool ghost}) => DecoratedBox(
      decoration: ShapeDecoration(
        color: ghost ? tokens.colors.codeBackground.withValues(alpha: 0.3) : tokens.colors.codeBackground,
        shape: squircle(kChipCornerRadius),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(18, 12, placed ? 4 : 18, 12),
        child: Row(
          children: [
            Expanded(
              // A long line scrolls rather than wrapping, which would read as
              // two statements — the same rule a worked example follows.
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Text(text, style: ghost ? style.copyWith(color: tokens.colors.codeMuted) : style),
              ),
            ),
            if (placed && !ghost)
              _TileButton(
                icon: FLucideIcons.x,
                label: context.localizations.lessonScreen_orderRemove,
                onPress: onRemove,
              ),
          ],
        ),
      ),
    );

    // Built here rather than inside `feedback`, which is mounted in an Overlay
    // and so cannot be relied on to find this subtree's theme. Everything it
    // draws with is already resolved.
    final flying = SizedBox(
      key: LineOrderingBoard.draggedLineKey,
      width: width,
      child: DecoratedBox(
        decoration: ShapeDecoration(color: tokens.colors.codeBackground, shape: squircle(kChipCornerRadius)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Text(text, style: style, softWrap: false, overflow: TextOverflow.fade),
        ),
      ),
    );

    final tile = MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: LongPressDraggable<DraggedLine>(
        data: dragged,
        delay: LineOrderingBoard.dragDelay,
        feedback: flying,
        childWhenDragging: card(ghost: true),
        child: onTap == null ? card(ghost: false) : FTappable(onPress: onTap, child: card(ghost: false)),
      ),
    );

    if (!placed) return tile;

    // A drag reaches no keyboard and no screen reader. These are the two arrow
    // buttons that used to stand in the row, kept as actions after the buttons
    // themselves were dropped for the drag.
    return Semantics(
      customSemanticsActions: {
        if (onMoveUp case final VoidCallback move)
          CustomSemanticsAction(label: context.localizations.lessonScreen_orderUp): move,
        if (onMoveDown case final VoidCallback move)
          CustomSemanticsAction(label: context.localizations.lessonScreen_orderDown): move,
      },
      child: tile,
    );
  }

}

/// A small icon button, sized to sit inside a code line rather than beside a
/// paragraph.
///
/// Its hit area is 36px square while the glyph is 16, so it still clears the
/// touch target a 16px mark would not.
class _TileButton extends StatelessWidget {

  static const double _hitSize = 36;

  /// Smaller than `AppButton`'s 20, which is set to stand beside a line of prose
  /// rather than inside a 26px code line.
  static const double _glyphSize = 16;

  final IconData icon;

  /// Required: there is no text in here for a screen reader to fall back on.
  final String label;

  /// Null disables it, which dims the glyph and stops it responding.
  final VoidCallback? onPress;

  const _TileButton({required this.icon, required this.label, required this.onPress});

  @override
  Widget build(BuildContext context) {
    final colors = context.appTheme.colors;

    return FTappable(
      onPress: onPress,
      semanticsLabel: label,
      child: SizedBox(
        width: _hitSize,
        height: _hitSize,
        child: Icon(
          icon,
          size: _glyphSize,
          color: onPress == null ? colors.codeMuted : colors.codeForeground,
        ),
      ),
    );
  }

}
