import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/shape_metrics.dart';
import 'package:i_can_code/views/components/progress_ring.dart';

/// A card holding a spinner, a message and an optional second line. Covers
/// anything a screen waits on once the app is already running.
class LoadingOverlay extends StatelessWidget {

  /// What is being waited on. Shown next to the spinner.
  final String message;

  /// An optional quieter second line — a retry count, say.
  final String? detail;

  /// How far along the wait is, from 0 to 1, when that is known. The spinner
  /// then stands still and fills. Null, the default, keeps it spinning.
  final double? progress;

  const LoadingOverlay({required this.message, this.detail, this.progress, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final text = context.appTheme.text;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: theme.colors.card,
          shape: squircle(kCardCornerRadius, side: BorderSide(color: theme.colors.border)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ProgressRing(value: progress),
              const SizedBox(width: 22),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(message, style: text.h3.copyWith(fontSize: 20)),
                    if (detail != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          detail!,
                          style: text.bodySmall.copyWith(fontSize: 15, color: theme.colors.mutedForeground),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

}
