import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/shape_metrics.dart';

/// The card a screen says everything in that is not its own content: a
/// micro:bit screen with no board open, the Tkinter page with no machine.
///
/// One widget rather than near-identical `DecoratedBox`es on every screen, which
/// is what keeps the states from drifting apart visually.
class NoticeCard extends StatelessWidget {

  final String title;
  final String body;

  /// An error the harness reported, untranslated. Set in the code face, because it
  /// is read literally and often pasted.
  final String? detail;

  /// When set, [detail] is folded away behind a toggle with this label: one
  /// press away for whoever helps the reader, and out of the text the reader is
  /// meant to read, which [detail] may not even be in the language of.
  final String? detailLabel;

  final Widget? action;

  const NoticeCard({required this.title, required this.body, this.detail, this.detailLabel, this.action, super.key});

  @override
  Widget build(BuildContext context) {
    final detail = this.detail;
    final detailLabel = this.detailLabel;
    final detailStyle = context.appTheme.text.code.copyWith(color: context.theme.colors.mutedForeground);

    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: squircle(kCardCornerRadius, side: BorderSide(color: context.theme.colors.border, width: 2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: context.appTheme.text.h3),
            const SizedBox(height: 12),
            Text(body, style: context.appTheme.text.body.copyWith(color: context.theme.colors.mutedForeground)),
            if (detail != null && detailLabel == null) ...[
              const SizedBox(height: 16),
              Text(detail, style: detailStyle),
            ],
            if (action != null) ...[const SizedBox(height: 24), action!],
            if (detail != null && detailLabel != null) ...[
              const SizedBox(height: 20),
              _FoldedDetail(label: detailLabel, detail: detail, detailStyle: detailStyle),
            ],
          ],
        ),
      ),
    );
  }

}

/// [NoticeCard.detail] behind a toggle, folded to begin with.
class _FoldedDetail extends StatefulWidget {

  static const double _chevronSize = 16;

  final String label;
  final String detail;
  final TextStyle detailStyle;

  const _FoldedDetail({required this.label, required this.detail, required this.detailStyle});

  @override
  State<_FoldedDetail> createState() => _FoldedDetailState();

}

class _FoldedDetailState extends State<_FoldedDetail> {

  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FTappable(
          semanticsButton: true,
          semanticsExpanded: _open,
          onPress: () => setState(() => _open = !_open),
          builder: (context, states, _) {
            final lit = states.contains(FTappableVariant.hovered) || states.contains(FTappableVariant.focused);
            final color = lit ? colors.foreground : colors.mutedForeground;

            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _open ? FLucideIcons.chevronDown : FLucideIcons.chevronRight,
                  size: _FoldedDetail._chevronSize,
                  color: color,
                ),
                const SizedBox(width: 6),
                Text(widget.label, style: context.appTheme.text.bodySmall.copyWith(color: color)),
              ],
            );
          },
        ),
        if (_open) ...[
          const SizedBox(height: 8),
          Text(widget.detail, style: widget.detailStyle),
        ],
      ],
    );
  }

}
