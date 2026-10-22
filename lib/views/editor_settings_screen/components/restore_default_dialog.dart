import 'package:flutter/widgets.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/views/components/app_button.dart';
import 'package:i_can_code/views/components/app_dialog.dart';

/// Asks before a changed setting goes back to its default. Irreversible.
Future<bool> showRestoreDefaultDialog(BuildContext context) async {
  final confirmed = await showAppDialog<bool>(
    context,
    builder: (context) => AppDialog(
      title: Text(context.localizations.editorSettingsScreen_restoreTitle),
      body: Text(context.localizations.editorSettingsScreen_restoreBody),
      actions: [
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
  );

  return confirmed ?? false;
}
