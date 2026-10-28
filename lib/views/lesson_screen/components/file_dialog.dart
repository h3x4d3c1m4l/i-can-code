import 'dart:async';
import 'dart:convert';

import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/services/file_download/file_download.dart';
import 'package:i_can_code/services/python/python_attempt_runner.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/views/components/app_button.dart';
import 'package:i_can_code/views/components/app_dialog.dart';
import 'package:i_can_code/views/components/lesson/selectable_code.dart';
import 'package:i_can_code/views/components/scroll_card.dart';

/// Where a file on a step came from, which is what its dialog says about it.
enum FileOrigin {

  /// One of the step's own `file` blocks, as the program finds it.
  given,

  /// Made by the student's program.
  created,

  /// One of the step's files, which the student's program changed.
  changed,

}

/// One file the lesson screen can open.
class ShownFile {

  /// Relative to the program's working directory.
  final String path;

  /// Null when the file holds no text to show.
  final String? text;

  /// [text] is only the start of the file.
  final bool truncated;

  final FileOrigin origin;

  const ShownFile({required this.path, required this.text, required this.origin, this.truncated = false});

  ShownFile.given(String name, String text) : this(path: name, text: text, origin: FileOrigin.given);

  ShownFile.written(WrittenFile file)
    : this(
        path: file.path,
        text: file.text,
        truncated: file.truncated,
        origin: file.changed ? FileOrigin.changed : FileOrigin.created,
      );

}

/// Opens [file] in a dialog: what it holds, and a way to copy or save it.
///
/// A dialog rather than a card on the step, so a file of any length costs the
/// step one button and never pushes Run out of view.
Future<void> showFileDialog(BuildContext context, ShownFile file) =>
    showAppDialog<void>(context, wide: true, builder: (context) => _FileDialogBody(file: file));

class _FileDialogBody extends StatefulWidget {

  final ShownFile file;

  const _FileDialogBody({required this.file});

  @override
  State<_FileDialogBody> createState() => _FileDialogBodyState();

}

class _FileDialogBodyState extends State<_FileDialogBody> {

  static const Duration _confirmation = Duration(seconds: 2);

  Timer? _revert;
  bool _copied = false;

  @override
  void dispose() {
    _revert?.cancel();
    super.dispose();
  }

  Future<void> _copy(String text) async {
    final view = View.of(context);
    final announcement = context.localizations.fileDialog_copied;
    final direction = Directionality.of(context);

    try {
      await Clipboard.setData(ClipboardData(text: text));
    } on PlatformException {
      // A browser MAY refuse the clipboard, and then there is nothing to confirm.
      return;
    }
    if (!mounted) return;

    setState(() => _copied = true);
    // The tick is a glyph, so a screen reader is told in words.
    unawaited(SemanticsService.sendAnnouncement(view, announcement, direction));
    _revert?.cancel();
    _revert = Timer(_confirmation, () => setState(() => _copied = false));
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.file;
    final text = file.text;
    final tokens = context.appTheme;
    final localizations = context.localizations;

    final about = switch (file.origin) {
      FileOrigin.given => localizations.fileDialog_given,
      FileOrigin.created => localizations.fileDialog_created,
      FileOrigin.changed => localizations.fileDialog_changed,
    };
    final note = switch (text) {
      null => localizations.fileDialog_notText,
      '' => localizations.fileDialog_empty,
      _ when file.truncated => localizations.fileDialog_truncated,
      _ => null,
    };

    return AppDialog(
      title: Text(file.path, style: TextStyle(fontFamily: tokens.text.code.fontFamily)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(about),
          if (note != null) ...[
            const SizedBox(height: 8),
            Text(note, style: TextStyle(fontSize: 15, color: tokens.colors.warning)),
          ],
        ],
      ),
      content: text == null || text.isEmpty
          ? null
          : ConstrainedBox(
              // A long file scrolls inside the card rather than pushing the
              // buttons off the screen.
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.5),
              child: _Contents(text: text),
            ),
      actions: [
        if (text != null && text.isNotEmpty)
          AppButton(
            tone: AppButtonTone.outline,
            icon: _copied ? FLucideIcons.check : FLucideIcons.copy,
            onPress: () => unawaited(_copy(text)),
            child: Text(localizations.fileDialog_copy),
          ),
        // Not the start of a file passed off as the whole of it.
        if (canDownloadFiles && text != null && !file.truncated)
          AppButton(
            tone: AppButtonTone.outline,
            icon: FLucideIcons.download,
            onPress: () => downloadTextFile(file.path.split('/').last, text),
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

/// The file's text on the page's own light card, the one a program's output
/// is shown on.
class _Contents extends StatelessWidget {

  final String text;

  const _Contents({required this.text});

  @override
  Widget build(BuildContext context) {
    return ScrollCard(
      child: SelectableCode(
        child: Text(
          // `csv.writer` ends its rows in \r\n, which would draw as a blank
          // line under each. Copied and downloaded, the text is as written.
          const LineSplitter().convert(text).join('\n'),
          style: context.appTheme.text.code.copyWith(fontSize: 15, height: 1.7),
        ),
      ),
    );
  }

}
