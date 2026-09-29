import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/shape_metrics.dart';

/// Where a section of a project stands for the student.
enum BlockState {

  /// Read, or said to work.
  finished,

  /// Passed over, or left behind when a later section was finished.
  skipped,

  /// The section in front of the student.
  current,

  /// Not reached yet. Its title is shown, so the student sees how far there is
  /// to go, and it does not open, so they do not read ahead.
  upcoming,

}

/// One section of a project: a line with its number and title, which opens
/// onto the section itself.
///
/// Every section is one of these, whatever it holds, so a project reads as one
/// list. Which one is open is the screen's to say: only one is at a time.
///
/// Opening and closing are animated, the way a `###` group folds, and
/// [child] is only in the tree while any of it shows.
class ProjectBlock extends StatefulWidget {

  /// How long opening or closing takes. The screen waits this long before it
  /// scrolls, so it scrolls to a block at its full height.
  static const Duration duration = Duration(milliseconds: 220);

  /// The space before the title in the line: the mark and the gap after it.
  /// Content that should line up with the title is indented by this much.
  static const double titleInset = 18 + 20 + 12;

  final int number;
  final String title;
  final BlockState state;
  final bool open;

  /// Opens or closes the block. Null for a block that cannot be opened.
  final VoidCallback? onToggle;

  /// Drawn before the chevron, such as the link to a task's snapshot.
  final Widget? trailing;

  /// The section itself, shown while [open].
  ///
  /// Built by the caller rather than handed over as a builder: the caller's
  /// `Observer` only sees what is read during its own build, and this block
  /// builds later.
  final Widget child;

  const ProjectBlock({
    required this.number,
    required this.title,
    required this.state,
    required this.open,
    required this.child,
    this.onToggle,
    this.trailing,
    super.key,
  });

  @override
  State<ProjectBlock> createState() => _ProjectBlockState();

}

class _ProjectBlockState extends State<ProjectBlock> with SingleTickerProviderStateMixin {

  /// Set outright on arrival, so the open block does not unfold itself when
  /// the page opens.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: ProjectBlock.duration,
    value: widget.open ? 1 : 0,
  );

  late final Animation<double> _fold = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Zero under reduced motion, which still ends where it was going.
    _controller.duration = context.motion(ProjectBlock.duration);
  }

  @override
  void didUpdateWidget(ProjectBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open == oldWidget.open) return;

    if (widget.open) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme.colors;
    final colors = context.appTheme.colors;
    final text = context.appTheme.text;
    final state = widget.state;
    final upcoming = state == BlockState.upcoming;
    final trailing = widget.trailing;
    final onToggle = widget.onToggle;

    final (icon, color) = switch (state) {
      BlockState.finished => (FLucideIcons.circleCheck, colors.success),
      BlockState.skipped => (FLucideIcons.skipForward, theme.mutedForeground),
      BlockState.current => (FLucideIcons.circleDot, theme.primary),
      BlockState.upcoming => (FLucideIcons.circle, theme.mutedForeground),
    };

    final line = Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '${widget.number}. ', style: TextStyle(color: theme.mutedForeground)),
                TextSpan(text: widget.title),
                if (state == BlockState.skipped)
                  TextSpan(
                    text: '  ${context.localizations.projectScreen_skipped}',
                    style: text.bodySmall.copyWith(color: theme.mutedForeground),
                  ),
              ],
            ),
            style: text.body.copyWith(fontSize: 18, color: upcoming ? theme.mutedForeground : null),
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 12), trailing],
      ],
    );

    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: squircle(
          kCardCornerRadius,
          side: state == BlockState.current
              ? BorderSide(color: theme.primary, width: 2)
              : BorderSide(color: theme.border, width: 1.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (onToggle == null)
            Padding(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14), child: line)
          else
            FTappable(
              semanticsButton: true,
              onPress: onToggle,
              builder: (context, states, _) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                child: Row(
                  children: [
                    Expanded(child: line),
                    const SizedBox(width: 12),
                    AnimatedBuilder(
                      animation: _fold,
                      builder: (context, _) => Transform.rotate(
                        // Down when open, right when closed.
                        angle: (_fold.value - 1) * math.pi / 2,
                        child: Icon(
                          FLucideIcons.chevronDown,
                          size: 18,
                          color: states.contains(FTappableVariant.hovered) ? theme.foreground : theme.mutedForeground,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // [FCollapsible] clips rather than shrinking the child, so the text
          // keeps its width while it folds and does not reflow on the way.
          // Out of the tree once fully closed, which also keeps a closed
          // block's buttons out of the tab order.
          AnimatedBuilder(
            animation: _fold,
            builder: (context, child) =>
                _fold.value == 0 ? const SizedBox.shrink() : FCollapsible(value: _fold.value, child: child!),
            child: Padding(padding: const EdgeInsets.fromLTRB(0, 4, 22, 24), child: widget.child),
          ),
        ],
      ),
    );
  }

}
