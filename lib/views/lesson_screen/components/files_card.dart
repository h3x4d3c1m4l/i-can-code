import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/services/python/python_attempt_runner.dart';
import 'package:i_can_code/views/components/files/file_button.dart';
import 'package:i_can_code/views/components/output_card.dart';
import 'package:i_can_code/views/lesson_screen/components/file_dialog.dart';

/// The files beside a step's program, or the ones it wrote, as one button each.
///
/// The card names them and nothing more: what a file holds opens in a dialog,
/// so a long one cannot push the step's own controls out of view.
class FilesCard extends StatelessWidget {

  final String label;
  final List<ShownFile> files;

  /// A line under the buttons, in the warning colour.
  final String? note;

  const FilesCard({required this.label, required this.files, this.note, super.key});

  /// What [result]'s program wrote, or null when it wrote nothing.
  static Widget? writtenBy(BuildContext context, AttemptResult result) {
    if (result.writtenFiles.isEmpty && !result.filesCut) return null;

    return FilesCard(
      label: context.localizations.lessonScreen_writtenFiles,
      files: [for (final file in result.writtenFiles) ShownFile.written(file)],
      note: result.filesCut ? context.localizations.lessonScreen_filesCut : null,
    );
  }

  @override
  Widget build(BuildContext context) => OutputCard.holding(
    label: label,
    note: note,
    child: Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final file in files)
          FileButton(
            label: file.path,
            note: file.origin == FileOrigin.changed ? context.localizations.lessonScreen_fileChanged : null,
            semanticsLabel: [
              context.localizations.lessonScreen_openFile(file.path),
              if (file.origin == FileOrigin.changed) context.localizations.lessonScreen_fileChanged,
            ].join(', '),
            onPress: () => unawaited(showFileDialog(context, file)),
          ),
      ],
    ),
  );

}
