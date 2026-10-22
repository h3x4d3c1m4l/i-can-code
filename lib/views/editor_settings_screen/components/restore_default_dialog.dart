import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/views/components/app_button.dart';
import 'package:i_can_code/views/components/app_button_row.dart';

/// Asks before a changed setting goes back to its default. Irreversible.
Future<bool> showRestoreDefaultDialog(BuildContext context) async {
  final confirmed = await showFDialog<bool>(
    context: context,
    // OverlayHost's Navigator, so the barrier covers the bar as well as the page.
    useRootNavigator: true,
    builder: (context, style, animation) => FDialog(
      animation: animation,
      builder: (context, style) => Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.localizations.editorSettingsScreen_restoreTitle, style: context.appTheme.text.h3),
            const SizedBox(height: 12),
            Text(
              context.localizations.editorSettingsScreen_restoreBody,
              style: context.appTheme.text.bodySmall.copyWith(fontSize: 17),
            ),
            const SizedBox(height: 24),
            Align(
              alignment: Alignment.centerRight,
              child: AppButtonRow(
                children: [
                  AppButton(
                    tone: AppButtonTone.neutral,
                    onPress: () => Navigator.of(context).pop(false),
                    child: Text(context.localizations.common_cancel),
                  ),
                  AppButton(
                    onPress: () => Navigator.of(context).pop(true),
                    child: Text(context.localizations.editorSettingsScreen_restoreConfirm),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  return confirmed ?? false;
}
