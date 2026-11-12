import 'package:flutter/widgets.dart';

/// A [FocusNode] whose own key handlers run before the one a [Focus] widget
/// attaches to it.
///
/// `code_forge` builds its `Focus` on the node it is given and passes its own
/// `onKeyEvent`, which handles Tab, Escape and the clipboard keys without
/// asking anyone. A handler that has to see those keys first goes in
/// [preempt].
///
/// What it leans on, read in Flutter 3.50.0:
///
/// - **`FocusNode.onKeyEvent` is a plain field**, and `FocusNode.attach` writes
///   it with `onKeyEvent ?? this.onKeyEvent`. Overriding it with a getter and a
///   setter here lets the attached handler be kept instead of replacing ours.
/// - **The focus manager calls the getter for every key** (`handleKeyMessage`),
///   so what it calls is [_dispatch] however often the node is attached.
/// - **A `Focus` with an external node writes the field once**, in `initState`.
///   `didUpdateWidget` leaves an external node's handler alone.
class PreemptingFocusNode extends FocusNode {

  final List<FocusOnKeyEventCallback> _preempting;

  /// What the [Focus] built on this node attached.
  FocusOnKeyEventCallback? _attached;

  /// [preempt] runs in order, each only when the one before ignored the key.
  PreemptingFocusNode({required List<FocusOnKeyEventCallback> preempt, super.debugLabel})
    : _preempting = [...preempt];

  /// Adds [handler] after the ones given so far, ahead of the attached one.
  void addPreempting(FocusOnKeyEventCallback handler) => _preempting.add(handler);

  void removePreempting(FocusOnKeyEventCallback handler) => _preempting.remove(handler);

  @override
  FocusOnKeyEventCallback? get onKeyEvent => _dispatch;

  @override
  set onKeyEvent(FocusOnKeyEventCallback? handler) {
    // `attach` writes back what it read when it is given no handler.
    if (handler == _dispatch) return;
    _attached = handler;
  }

  KeyEventResult _dispatch(FocusNode node, KeyEvent event) {
    for (final handler in [..._preempting]) {
      final result = handler(node, event);
      if (result != KeyEventResult.ignored) return result;
    }
    return _attached?.call(node, event) ?? KeyEventResult.ignored;
  }

}
