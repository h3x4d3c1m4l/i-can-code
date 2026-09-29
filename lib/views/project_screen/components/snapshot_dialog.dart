import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/views/components/app_button.dart';
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
  final restore = await showFDialog<bool>(
    context: context,
    builder: (context, style, animation) => FDialog(
      animation: animation,
      // Wider than a question: this one holds a program.
      constraints: const BoxConstraints(maxWidth: 760),
      builder: (context, style) {
        final tokens = context.appTheme;
        final height = MediaQuery.sizeOf(context).height;

        return Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(context.localizations.projectScreen_snapshotTitle(task), style: tokens.text.h3),
              const SizedBox(height: 12),
              Text(
                context.localizations.projectScreen_snapshotBody,
                style: tokens.text.bodySmall.copyWith(fontSize: 17),
              ),
              const SizedBox(height: 20),
              ConstrainedBox(
                // A long program scrolls inside the card rather than pushing
                // the buttons off the screen.
                constraints: BoxConstraints(maxHeight: height * 0.5),
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
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppButton(
                    tone: AppButtonTone.neutral,
                    onPress: () => Navigator.of(context).pop(false),
                    child: Text(context.localizations.projectScreen_close),
                  ),
                  const SizedBox(width: 12),
                  AppButton(
                    icon: FLucideIcons.history,
                    onPress: () => Navigator.of(context).pop(true),
                    child: Text(context.localizations.projectScreen_snapshotRestore),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    ),
  );

  return restore ?? false;
}
