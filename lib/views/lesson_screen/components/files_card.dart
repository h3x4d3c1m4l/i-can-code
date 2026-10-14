import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/services/python/python_attempt_runner.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/shape_metrics.dart';
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
    child: Wrap(spacing: 10, runSpacing: 10, children: [for (final file in files) _FileButton(file: file)]),
  );

}

/// A file's name, drawn as a control in the outlined button's own ink.
class _FileButton extends StatelessWidget {

  /// The height the corners are worked out for: a line of the code face at
  /// 15px and the padding around it.
  static const double _height = 40;

  final ShownFile file;

  const _FileButton({required this.file});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final tokens = context.appTheme;
    final ink = tokens.colors.neutralButton;

    return FTappable(
      onPress: () => unawaited(showFileDialog(context, file)),
      semanticsButton: true,
      semanticsLabel: [
        context.localizations.lessonScreen_openFile(file.path),
        if (file.origin == FileOrigin.changed) context.localizations.lessonScreen_fileChanged,
      ].join(', '),
      builder: (context, states, child) => DecoratedBox(
        decoration: ShapeDecoration(
          // The outlined button's hover, so the two read as one family.
          color: states.contains(FTappableVariant.hovered) || states.contains(FTappableVariant.focused)
              ? ink.withValues(alpha: 0.1)
              : theme.colors.background,
          shape: squircleOf(
            kChipCornerRadius,
            size: _height,
            side: BorderSide(color: ink, width: 1.5),
          ),
        ),
        child: child,
      ),
      // The label above says all of it, so the name is not read out twice.
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(FLucideIcons.fileText, size: 18, color: ink),
              const SizedBox(width: 8),
              Text(file.path, style: tokens.text.code.copyWith(fontSize: 15, color: ink)),
              if (file.origin == FileOrigin.changed) ...[
                const SizedBox(width: 8),
                Text(
                  context.localizations.lessonScreen_fileChanged,
                  style: tokens.text.bodySmall.copyWith(fontSize: 13, color: theme.colors.mutedForeground),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

}
