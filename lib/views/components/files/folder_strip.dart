import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/views/components/files/file_button.dart';
import 'package:i_can_code/views/components/files/folder_file_dialog.dart';

/// The folder the console and the program page share, as one line of buttons:
/// one to type a new file, one for each file that fits, and one that lists the
/// rest behind "+N". Each file opens in [showFolderFileDialog].
///
/// **Never more than one line.** On a small window that line is all there is
/// to spare between the editor and the terminal, and a second one would come
/// out of one of them. So the buttons are measured ([FileButton.widthFor])
/// rather than wrapped, a long name is cut short while a few letters of it
/// still fit, and only then does a file move behind "+N".
class FolderStrip extends StatelessWidget {

  static const double _gap = 10;

  /// Where a name is cut, so that one long name does not take a line a few
  /// short ones could share.
  static const double _maxLabelWidth = 180;

  /// The least of a name worth showing. Below it the file goes behind "+N".
  static const double _minLabelWidth = 64;

  /// The store's own view of the folder, read inside this widget's [Observer].
  final Map<String, Uint8List> files;

  final FolderNameCheck problemWith;
  final FolderSave onSave;
  final ValueChanged<String> onDelete;

  /// Where the buttons gather when there is room left over.
  final MainAxisAlignment alignment;

  const FolderStrip({
    required this.files,
    required this.problemWith,
    required this.onSave,
    required this.onDelete,
    this.alignment = MainAxisAlignment.start,
    super.key,
  });

  /// How wide the label of each file in [paths] comes out in [width], in order,
  /// for as many as fit. The rest go behind "+N".
  static List<double> fit(BuildContext context, List<String> paths, double width) {
    var room = width - FileButton.widthFor(context, icon: FLucideIcons.filePlus);
    // A file button less its label: the padding, the icon and the gap after it.
    final chrome = FileButton.widthFor(context, label: '');
    final labels = <double>[];

    for (var i = 0; i < paths.length; i++) {
      final after = paths.length - i - 1;
      final reserve = after == 0 ? 0 : _gap + FileButton.widthFor(context, label: '+$after', icon: null);
      final natural = min(FileButton.labelWidth(context, paths[i]), _maxLabelWidth);

      if (_gap + chrome + natural + reserve <= room) {
        labels.add(natural);
        room -= _gap + chrome + natural;
        continue;
      }
      final squeezed = room - reserve - _gap - chrome;
      if (squeezed >= _minLabelWidth) labels.add(squeezed);
      break;
    }
    return labels;
  }

  @override
  Widget build(BuildContext context) => Observer(
    // A test hands over a plain map, which reads no observable.
    warnWhenNoObservables: false,
    builder: (context) {
      // Copied here, in the Observer's own build: the LayoutBuilder below runs
      // at layout time, where nothing it reads is tracked.
      final files = Map.of(this.files);
      return LayoutBuilder(builder: (context, constraints) => _buildRow(context, files, constraints.maxWidth));
    },
  );

  Widget _buildRow(BuildContext context, Map<String, Uint8List> files, double width) {
    final localizations = context.localizations;
    final paths = files.keys.toList();
    final labels = fit(context, paths, width);

    void open(String? path) => unawaited(
      showFolderFileDialog(
        context,
        path: path,
        bytes: path == null ? null : files[path],
        problemWith: problemWith,
        onSave: onSave,
        onDelete: onDelete,
      ),
    );

    return Row(
      mainAxisAlignment: alignment,
      spacing: _gap,
      children: [
        FileButton(
          icon: FLucideIcons.filePlus,
          tip: localizations.folderStrip_new,
          semanticsLabel: localizations.folderStrip_new,
          onPress: () => open(null),
        ),
        for (final (i, label) in labels.indexed)
          FileButton(
            label: paths[i],
            maxLabelWidth: label,
            semanticsLabel: localizations.folderStrip_open(paths[i]),
            onPress: () => open(paths[i]),
          ),
        if (labels.length < paths.length) _MoreFiles(paths: paths.sublist(labels.length), onOpen: open),
      ],
    );
  }

}

/// "+N", which lists the files that did not fit in a menu of their own.
class _MoreFiles extends StatefulWidget {

  final List<String> paths;
  final ValueChanged<String> onOpen;

  const _MoreFiles({required this.paths, required this.onOpen});

  @override
  State<_MoreFiles> createState() => _MoreFilesState();

}

class _MoreFilesState extends State<_MoreFiles> with SingleTickerProviderStateMixin {

  /// Owned here for the reason `SettingsMenu`'s is: the popover does not open
  /// itself.
  late final FPopoverController _controller = FPopoverController(vsync: this);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _open(String path) {
    unawaited(_controller.hide());
    widget.onOpen(path);
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.paths.length;
    final code = context.appTheme.text.code.copyWith(fontSize: 15);

    return FPopoverMenu(
      control: FPopoverControl.managed(controller: _controller),
      // Above the button: on both pages the line sits low, over the terminal or
      // at the foot of the page.
      menuAnchor: Alignment.bottomRight,
      childAnchor: Alignment.topRight,
      // A program can make far more files than a window is tall.
      maxHeight: 320,
      menu: [
        FItemGroup(
          children: [
            for (final path in widget.paths)
              FItem(
                prefix: const Icon(FLucideIcons.fileText),
                title: Text(path, style: code),
                onPress: () => _open(path),
              ),
          ],
        ),
      ],
      child: FileButton(
        label: '+$count',
        icon: null,
        semanticsLabel: context.localizations.folderStrip_more(count),
        onPress: () => unawaited(_controller.toggle()),
      ),
    );
  }

}
