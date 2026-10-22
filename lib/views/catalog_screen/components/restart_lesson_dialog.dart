import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/views/components/app_button.dart';

/// Asks whether to forget one lesson's ticks and code, named by [lesson], its
/// title. True only on the confirming button: forgetting cannot be undone.
Future<bool> showRestartLessonDialog(BuildContext context, {required String lesson}) async {
  final confirmed = await showFDialog<bool>(
    context: context,
    // The router's Navigator is below the bar, so its barrier would leave the
    // bar sharp. The outermost one is OverlayHost's, which covers the window,
    // as the cog's reset dialog does.
    useRootNavigator: true,
    builder: (context, style, animation) => FDialog(
      animation: animation,
      builder: (context, style) => Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.localizations.catalogScreen_restartTitle(lesson), style: context.appTheme.text.h3),
            const SizedBox(height: 12),
            Text(
              context.localizations.catalogScreen_restartBody,
              style: context.appTheme.text.bodySmall.copyWith(fontSize: 17),
            ),
            const SizedBox(height: 24),
            // A wrap and not a row: "Opnieuw beginnen" is long enough that the
            // two buttons do not fit side by side in a narrow dialog.
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 12,
              runSpacing: 12,
              children: [
                AppButton(
                  tone: AppButtonTone.neutral,
                  onPress: () => Navigator.of(context).pop(false),
                  child: Text(context.localizations.common_cancel),
                ),
                AppButton(
                  onPress: () => Navigator.of(context).pop(true),
                  child: Text(context.localizations.catalogScreen_restartConfirm),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  return confirmed ?? false;
}
