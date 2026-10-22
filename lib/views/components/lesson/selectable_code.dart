import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Lets the reader select the text under it with the pointer, and copy it with
/// the keyboard or the browser's own menu.
///
/// A [SelectableRegion], which is the widgets-layer half of Material's
/// `SelectionArea`. Three things about it are settled here:
///
/// - It asserts an [Overlay] above it. The app always has one. Below none, in
///   a widget test that builds one widget, [child] is returned as it is.
/// - Its focus node is a tab stop by default, and a page of samples would be a
///   page of stops with nothing to do on them. This one skips traversal and
///   still takes focus on a press, which is what the copy shortcut needs.
/// - [emptyTextSelectionControls] draws no handles and no toolbar, so a long
///   press on a touch screen selects a word and offers nothing to do with it.
///   A caller SHOULD give touch another way to copy.
///
/// On the web the region puts an empty `<div>` under [child], which is how the
/// browser's menu comes to offer Copy. It is registered as invisible, so the
/// engine does not split the canvas around it.
class SelectableCode extends StatefulWidget {

  final Widget child;

  const SelectableCode({required this.child, super.key});

  @override
  State<SelectableCode> createState() => _SelectableCodeState();

}

class _SelectableCodeState extends State<SelectableCode> {

  final FocusNode _focusNode = FocusNode(skipTraversal: true, debugLabel: 'SelectableCode');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (Overlay.maybeOf(context) == null) return widget.child;

    return SelectableRegion(
      // The region wraps itself in the browser-menu shim only while
      // BrowserContextMenu is on, and rebuilding it across a switch of that
      // trips Flutter's "one selectable" assertion. A catalog card switches it
      // off under the pointer, so a lesson opened from one meets the switch on
      // its first rebuild. A new key builds a new region instead.
      key: ValueKey(BrowserContextMenu.enabled),
      focusNode: _focusNode,
      selectionControls: emptyTextSelectionControls,
      child: widget.child,
    );
  }

}
