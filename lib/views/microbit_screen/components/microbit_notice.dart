import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/shape_metrics.dart';

/// The card this screen says everything in that is not a board.
///
/// One widget rather than five near-identical `DecoratedBox`es, which is what
/// keeps the states from drifting apart visually.
class MicrobitNotice extends StatelessWidget {

  final String title;
  final String body;

  /// An error the core reported, untranslated. Set in the code face, because it
  /// is read literally and often pasted.
  final String? detail;

  final Widget? action;

  const MicrobitNotice({required this.title, required this.body, this.detail, this.action, super.key});

  @override
  Widget build(BuildContext context) {
    final detail = this.detail;

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
            if (detail != null) ...[
              const SizedBox(height: 16),
              Text(detail, style: context.appTheme.text.code.copyWith(color: context.theme.colors.mutedForeground)),
            ],
            if (action != null) ...[const SizedBox(height: 24), action!],
          ],
        ),
      ),
    );
  }

}
