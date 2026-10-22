import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/views/components/app_button.dart';
import 'package:i_can_code/views/components/app_dialog.dart';
import 'package:i_can_code/views/components/lesson/code_sample.dart';

/// Shows the program as it stood when a task was said to work, and answers
/// whether the student wants it back.
///
/// The code is a [CodeSample], not an editor: it is a record of what was, and
/// the way to change it is to put it back first. Restoring needs no second
/// question, because the dialog already says what it replaces and the button
/// says what it does.
Future<bool> showSnapshotDialog(
  BuildContext context, {
  required String task,
  required String code,
  required String language,
}) async {
  final restore = await showAppDialog<bool>(
    context,
    wide: true,
    builder: (context) {
      final tokens = context.appTheme;

      return AppDialog(
        title: Text(context.localizations.projectScreen_snapshotTitle(task)),
        body: Text(context.localizations.projectScreen_snapshotBody),
        content: ConstrainedBox(
          // A long program scrolls inside the card rather than pushing the
          // buttons off the screen.
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.5),
          child: SingleChildScrollView(
            child: CodeSample(
              source: code,
              language: language,
              style: tokens.text.code.copyWith(color: tokens.colors.codeForeground),
              labelStyle: tokens.text.codeSmall.copyWith(color: tokens.colors.codeMuted),
              surface: tokens.colors.codeBackground,
            ),
          ),
        ),
        actions: [
          AppButton(
            tone: AppButtonTone.neutral,
            onPress: () => Navigator.of(context).pop(false),
            child: Text(context.localizations.projectScreen_close),
          ),
          AppButton(
            icon: FLucideIcons.history,
            onPress: () => Navigator.of(context).pop(true),
            child: Text(context.localizations.projectScreen_snapshotRestore),
          ),
        ],
      );
    },
  );

  return restore ?? false;
}
