import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/l10n/generated/app_localizations.dart';
import 'package:i_can_code/services/file_download/file_download.dart';
import 'package:i_can_code/services/folder_store.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/shape_metrics.dart';
import 'package:i_can_code/theme/squircle_input_border.dart';
import 'package:i_can_code/views/components/app_button.dart';
import 'package:i_can_code/views/components/app_dialog.dart';
import 'package:i_can_code/views/components/code_editor_card.dart';
import 'package:i_can_code/views/components/files/file_contents.dart';
import 'package:re_editor/re_editor.dart';

/// Writes what the dialog was given, under [name], in place of [replacing],
/// which is the file it was opened on and null for a new one.
typedef FolderSave = void Function({required String name, required Uint8List bytes, String? replacing});

/// Says why [name] cannot be used, or null when it can, for the file that has
/// [current] as its name now.
typedef FolderNameCheck = FolderNameProblem? Function(String name, {String? current});

/// Opens [path] in the folder the console and the program page share, to read
/// and change by hand, or with no [path] a new file to type.
///
/// A file only a program could have made, too large to edit here or holding
/// no text, opens to read and delete only.
Future<void> showFolderFileDialog(
  BuildContext context, {
  required FolderNameCheck problemWith,
  required FolderSave onSave,
  required ValueChanged<String> onDelete,
  String? path,
  Uint8List? bytes,
}) {
  final text = bytes == null ? '' : _textOf(bytes);
  if (path != null && (text == null || (bytes?.length ?? 0) > FolderStoreBase.maxEditableBytes)) {
    return showAppDialog<void>(
      context,
      wide: true,
      builder: (context) => _ReadDialog(path: path, text: text, onDelete: onDelete),
    );
  }

  return showAppDialog<void>(
    context,
    wide: true,
    // An edit is lost when the dialog closes, so only its buttons close it.
    dismissible: false,
    builder: (context) =>
        _EditDialog(path: path, text: text ?? '', problemWith: problemWith, onSave: onSave, onDelete: onDelete),
  );
}

/// [bytes] as text, or null when they are not UTF-8.
String? _textOf(Uint8List bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return null;
  }
}

/// Asks before [path] goes, because nothing brings it back. Completes with
/// whether to go on.
Future<bool> _confirmDelete(BuildContext context, String path) async {
  final localizations = context.localizations;
  final confirmed = await showAppDialog<bool>(
    context,
    builder: (context) => AppDialog(
      title: Text(localizations.folderDialog_deleteTitle(path)),
      body: Text(localizations.folderDialog_deleteBody),
      actions: [
        AppButton(
          tone: AppButtonTone.neutral,
          onPress: () => Navigator.of(context).pop(false),
          child: Text(localizations.common_cancel),
        ),
        AppButton(
          onPress: () => Navigator.of(context).pop(true),
          child: Text(localizations.folderDialog_delete),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

Widget _title(BuildContext context, String path) =>
    Text(path, style: TextStyle(fontFamily: context.appTheme.text.code.fontFamily));

class _EditDialog extends StatefulWidget {

  /// Null for a new file.
  final String? path;

  final String text;
  final FolderNameCheck problemWith;
  final FolderSave onSave;
  final ValueChanged<String> onDelete;

  const _EditDialog({
    required this.path,
    required this.text,
    required this.problemWith,
    required this.onSave,
    required this.onDelete,
  });

  @override
  State<_EditDialog> createState() => _EditDialogState();

}

class _EditDialogState extends State<_EditDialog> {

  /// How many lines the editor shows where the window has room for them. The
  /// card gives way to a shorter window, in whole lines.
  static const int _preferredLines = 12;

  /// What the editor started as. `csv.writer` ends its rows in \r\n, which the
  /// editor would keep as a stray character at the end of every line.
  late final String _initial = widget.text.replaceAll('\r\n', '\n');

  late final TextEditingController _name = TextEditingController(text: widget.path ?? '')..addListener(_onName);
  late final CodeLineEditingController _code = CodeLineEditingController.fromText(_initial);

  /// What stops the file being saved, once Save was pressed. Rechecked as the
  /// name changes, so the message goes as soon as it no longer holds.
  FolderNameProblem? _problem;
  bool _checked = false;

  bool _tooLarge = false;

  @override
  void dispose() {
    _name
      ..removeListener(_onName)
      ..dispose();
    _code.dispose();
    super.dispose();
  }

  void _onName() => setState(() {
    if (_checked) _problem = widget.problemWith(_name.text.trim(), current: widget.path);
  });

  void _save() {
    final name = _name.text.trim();
    final problem = widget.problemWith(name, current: widget.path);
    final bytes = utf8.encode(_code.text);
    final tooLarge = bytes.length > FolderStoreBase.maxEditableBytes;
    if (problem != null || tooLarge) {
      setState(() {
        _checked = true;
        _problem = problem;
        _tooLarge = tooLarge;
      });
      return;
    }

    // Saving what was opened unchanged would write it back with \n for every
    // \r\n it had, and change a file nobody changed.
    final unchanged = widget.path != null && name == widget.path && _code.text == _initial;
    if (!unchanged) widget.onSave(name: name, bytes: bytes, replacing: widget.path);
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final path = widget.path!;
    if (!await _confirmDelete(context, path) || !mounted) return;
    widget.onDelete(path);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = context.localizations;
    final path = widget.path;
    final name = _name.text.trim();

    return AppDialog(
      title: path == null ? Text(localizations.folderDialog_newTitle) : _title(context, path),
      body: Text(localizations.folderDialog_about),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          FTextField(
            control: .managed(controller: _name),
            label: Text(localizations.folderDialog_name),
            hint: localizations.folderDialog_nameHint,
            error: _problem == null ? null : Text(_problemText(localizations, _problem!)),
            // A new file starts with its name. An existing one is opened to be
            // changed, which is what the editor is for.
            autofocus: path == null,
            textInputAction: TextInputAction.next,
            // A file name is not prose: nothing here is a word to capitalise or
            // correct.
            textCapitalization: TextCapitalization.none,
            autocorrect: false,
            style: FTextFieldStyleDelta.delta(
              border: squircleFieldBorder(context, radius: kChipCornerRadius),
              contentTextStyle: FVariantsDelta.delta([
                FVariantOperation.all(
                  TextStyleDelta.delta(
                    fontFamily: context.appTheme.text.code.fontFamily,
                    fontFamilyFallback: context.appTheme.text.code.fontFamilyFallback,
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          Flexible(
            child: ConstrainedBox(
              // The strip over the editor is about one line high.
              constraints: BoxConstraints(maxHeight: CodeEditorCard.heightForLines(_preferredLines + 1)),
              child: CodeEditorCard(
                controller: _code,
                status: '',
                fileName: name.isEmpty ? localizations.folderDialog_newTitle : name,
                height: null,
                highlight: false,
                autofocus: path != null,
              ),
            ),
          ),
          if (_tooLarge) ...[
            const SizedBox(height: 8),
            Text(
              localizations.folderDialog_tooLarge(FolderStoreBase.maxEditableBytes ~/ 1024),
              style: TextStyle(fontSize: 15, color: context.appTheme.colors.warning),
            ),
          ],
        ],
      ),
      actions: [
        if (path != null)
          AppButton(
            tone: AppButtonTone.outline,
            icon: FLucideIcons.trash2,
            onPress: () => unawaited(_delete()),
            child: Text(localizations.folderDialog_delete),
          ),
        // Only its glyph, so the four fit on one line in the dialog's width.
        if (canDownloadFiles)
          AppButton.icon(
            icon: FLucideIcons.download,
            semanticsLabel: localizations.fileDialog_download,
            tip: localizations.fileDialog_download,
            // What is in the editor, saved or not: what the student sees.
            onPress: () => downloadTextFile(
              (name.isEmpty ? localizations.folderDialog_nameHint : name).split('/').last,
              _code.text,
            ),
          ),
        AppButton(
          tone: AppButtonTone.neutral,
          onPress: () => Navigator.of(context).pop(),
          child: Text(localizations.common_cancel),
        ),
        AppButton(onPress: _save, child: Text(localizations.folderDialog_save)),
      ],
    );
  }

  static String _problemText(AppLocalizations localizations, FolderNameProblem problem) => switch (problem) {
    FolderNameProblem.empty => localizations.folderDialog_nameEmpty,
    FolderNameProblem.slash => localizations.folderDialog_nameSlash,
    FolderNameProblem.reserved => localizations.folderDialog_nameReserved,
    FolderNameProblem.taken => localizations.folderDialog_nameTaken,
    FolderNameProblem.tooLong => localizations.folderDialog_nameTooLong(FolderStoreBase.maxNameLength),
  };

}

/// A file that only a program could have made: shown, and not edited.
class _ReadDialog extends StatelessWidget {

  /// The most of a large file that is drawn. Laying out megabytes of text
  /// would hold the page up for a file nobody reads to the end here.
  static const int _shownCharacters = 64 * 1024;

  final String path;

  /// Null when the file holds no text.
  final String? text;

  final ValueChanged<String> onDelete;

  const _ReadDialog({required this.path, required this.text, required this.onDelete});

  Future<void> _delete(BuildContext context) async {
    if (!await _confirmDelete(context, path) || !context.mounted) return;
    onDelete(path);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = context.localizations;
    final text = this.text;
    final tokens = context.appTheme;

    return AppDialog(
      title: _title(context, path),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(localizations.folderDialog_about),
          const SizedBox(height: 8),
          Text(
            text == null ? localizations.fileDialog_notText : localizations.folderDialog_readOnly,
            style: TextStyle(fontSize: 15, color: tokens.colors.warning),
          ),
        ],
      ),
      content: text == null
          ? null
          : ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.5),
              child: FileContents(
                text: text.length > _shownCharacters ? text.substring(0, _shownCharacters) : text,
              ),
            ),
      actions: [
        AppButton(
          tone: AppButtonTone.outline,
          icon: FLucideIcons.trash2,
          onPress: () => unawaited(_delete(context)),
          child: Text(localizations.folderDialog_delete),
        ),
        if (canDownloadFiles && text != null)
          AppButton(
            tone: AppButtonTone.outline,
            icon: FLucideIcons.download,
            onPress: () => downloadTextFile(path.split('/').last, text),
            child: Text(localizations.fileDialog_download),
          ),
        AppButton(
          tone: AppButtonTone.neutral,
          onPress: () => Navigator.of(context).pop(),
          child: Text(localizations.fileDialog_close),
        ),
      ],
    );
  }

}
