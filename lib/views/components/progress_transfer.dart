import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:i_can_code/app_info.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/l10n/generated/app_localizations.dart';
import 'package:i_can_code/services/feature_toggles.dart';
import 'package:i_can_code/services/file_download/file_download.dart';
import 'package:i_can_code/services/file_open/file_open.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/progress/progress_file.dart';
import 'package:i_can_code/services/progress/progress_store.dart';
import 'package:i_can_code/views/components/app_button.dart';
import 'package:i_can_code/views/components/app_dialog.dart';

/// Completes with the text of the file the reader picked, or null when they
/// cancelled. Throws a [FormatException] for a file that cannot be read as text.
typedef TextFileOpener = Future<String?> Function();

/// Taking a student's ticks to another browser and back, from the cog.
abstract final class ProgressTransfer {

  /// Far above what any course's progress comes to, and far below a video
  /// picked by mistake, which would otherwise be read into memory whole.
  static const int maxBytes = 1024 * 1024;

  /// Offers the progress of every lesson the student is shown as a file to
  /// save, started or not. Does nothing where [canDownloadFiles] is false.
  static void exportFile(BuildContext context, {DateTime? now}) {
    final exportedAt = now ?? DateTime.now();
    final text = ProgressFile.write(
      GetIt.I<Course>(),
      GetIt.I<ProgressStore>(),
      isOn: GetIt.I<FeatureToggles>().isOn,
      exportedAt: exportedAt,
      appVersion: appVersion,
    );
    downloadTextFile(context.localizations.progressFile_name(_dateOf(exportedAt)), text);
  }

  /// Reads a file the reader picks into their progress, asking first whether it
  /// goes beside what is there or in its place. Changes nothing unless the
  /// whole file holds.
  static Future<void> importFile(BuildContext context, {TextFileOpener? open}) async {
    String? source;
    var unreadable = false;
    try {
      source = await (open ?? _openJson)();
    } on FormatException {
      unreadable = true;
    }
    if (!context.mounted) return;
    if (unreadable) return _refuse(context, ProgressFileProblem.notProgress);
    if (source == null) return;

    final ProgressImport found;
    try {
      found = ProgressFile.parse(source).matchTo(GetIt.I<Course>());
    } on ProgressFileException catch (error) {
      return _refuse(context, error.problem);
    }

    final localizations = context.localizations;
    if (found.finished.isEmpty) {
      await _tell(
        context,
        title: localizations.importProgress_nothingTitle,
        body: found.skipped == 0 ? localizations.importProgress_noSteps : localizations.importProgress_unknownSteps,
      );
      return;
    }

    final progress = GetIt.I<ProgressStore>();
    // With nothing here, merging and replacing come to the same thing.
    final replace = progress.hasProgress ? await _askReplace(context) : false;
    if (replace == null) return;

    await progress.restore(found.finished, replace: replace);
    if (!context.mounted) return;

    await _tell(
      context,
      title: localizations.importProgress_doneTitle,
      body: [
        localizations.importProgress_done(found.steps, found.finished.length),
        if (found.skipped > 0) localizations.importProgress_skipped(found.skipped),
      ].join(' '),
    );
  }

  static Future<String?> _openJson() => openTextFile(extensions: const ['json'], maxBytes: maxBytes);

  /// The local date as `yyyy-mm-dd`, which sorts the way it reads.
  static String _dateOf(DateTime time) => [
    time.year.toString().padLeft(4, '0'),
    time.month.toString().padLeft(2, '0'),
    time.day.toString().padLeft(2, '0'),
  ].join('-');

  /// Whether to replace what is there. Null when the reader cancels.
  static Future<bool?> _askReplace(BuildContext context) => showAppDialog<bool>(
    context,
    builder: (context) => AppDialog(
      title: Text(context.localizations.importProgress_modeTitle),
      body: Text(context.localizations.importProgress_modeBody),
      actions: [
        AppButton(
          tone: AppButtonTone.outline,
          onPress: () => Navigator.of(context).pop(),
          child: Text(context.localizations.common_cancel),
        ),
        AppButton(
          tone: AppButtonTone.neutral,
          onPress: () => Navigator.of(context).pop(true),
          child: Text(context.localizations.importProgress_replace),
        ),
        AppButton(
          onPress: () => Navigator.of(context).pop(false),
          child: Text(context.localizations.importProgress_merge),
        ),
      ],
    ),
  );

  static Future<void> _refuse(BuildContext context, ProgressFileProblem problem) {
    final localizations = context.localizations;
    return _tell(
      context,
      title: localizations.importProgress_failedTitle,
      body: _problemText(localizations, problem),
    );
  }

  static String _problemText(AppLocalizations localizations, ProgressFileProblem problem) => switch (problem) {
    ProgressFileProblem.notProgress => localizations.importProgress_notProgress,
    ProgressFileProblem.newer => localizations.importProgress_newer,
    ProgressFileProblem.damaged => localizations.importProgress_damaged,
  };

  static Future<void> _tell(BuildContext context, {required String title, required String body}) =>
      showAppDialog<void>(
        context,
        builder: (context) => AppDialog(
          title: Text(title),
          body: Text(body),
          actions: [
            AppButton(
              onPress: () => Navigator.of(context).pop(),
              child: Text(context.localizations.importProgress_close),
            ),
          ],
        ),
      );

}
