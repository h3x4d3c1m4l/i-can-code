import 'package:flutter/widgets.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/views/components/app_button.dart';
import 'package:i_can_code/views/components/app_dialog.dart';

/// Asks whether to forget one lesson's ticks and code, named by [lesson], its
/// title. True only on the confirming button: forgetting cannot be undone.
Future<bool> showRestartLessonDialog(BuildContext context, {required String lesson}) async {
  final confirmed = await showAppDialog<bool>(
    context,
    builder: (context) => AppDialog(
      title: Text(context.localizations.catalogScreen_restartTitle(lesson)),
      body: Text(context.localizations.catalogScreen_restartBody),
      actions: [
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
  );

  return confirmed ?? false;
}
