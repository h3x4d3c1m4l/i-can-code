import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:i_can_code/services/vm/vm_runtime.dart';

/// Builds the platform view that shows the guest's screen. [onCreated] MUST be
/// called with the view's id, which is how the display hands the view back when
/// it is disposed.
typedef VmViewBuilder = Widget Function(BuildContext context, VmDisplayBinding binding, ValueChanged<int> onCreated);

/// The platform view the page uses. `flutter test` cannot build it
/// (`HtmlElementView` throws off the web), so a test passes a builder of its own.
Widget buildHtmlElementView(BuildContext context, VmDisplayBinding binding, ValueChanged<int> onCreated) =>
    HtmlElementView(viewType: binding.viewType, creationParams: binding.viewParams, onPlatformViewCreated: onCreated);

/// The guest's screen, embedded as a platform view, with the keyboard, focus
/// and pointer wiring that makes it behave like a widget.
///
/// **Every workaround for the platform view lives here and nowhere else**, and
/// each leans on engine behaviour that was verified in headless Chrome with
/// Flutter 3.47.4 and the real v86 unless it says otherwise:
///
/// - **Focus.** `HtmlElementView` has no working focus (flutter/flutter#39496),
///   and `PlatformViewLink` adds an invisible Tab stop of its own. Hence the
///   [ExcludeFocus] around the view and one [FocusNode] that stands for it.
/// - **Keys.** The engine listens on the window in the capture phase and v86 in
///   the bubble phase. Answering every key with
///   [KeyEventResult.skipRemainingHandlers] keeps the app's shortcuts from
///   seeing it, and a key the framework did not handle is neither prevented nor
///   stopped, so v86 still gets it. Tab and Escape belong to the program while
///   one runs ([holdsTab]).
/// - **Leaving.** Escape then Tab: that Tab turns the guest's keyboard off
///   synchronously, before v86's later listener sees it, and is left to the
///   app's own traversal. With no program running a Tab alone does the same.
///   WCAG 2.1.2 wants the way out stated, which the window frame does while
///   this holds focus and Tab.
/// - **DOM focus follows Flutter focus, both ways.** A node that gains focus
///   moves DOM focus onto the element; one that loses it moves DOM focus to the
///   `flutter-view` rather than blurring, because a blur makes the engine report
///   the whole view as unfocused. DOM focus arriving on the element requests the
///   node, and DOM focus leaving turns the keyboard off: a click on another
///   platform view moved DOM focus while this node still held Flutter's.
/// - **Pointer down requests focus** before the browser's own mousedown focus
///   lands, which keeps the engine's text input (flutter/flutter#166857) from
///   pulling focus back to a text field. A node that already has focus gets no
///   focus change, so pointer down turns the keyboard back on itself.
/// - **One display per machine owns its binding.** A display that replaces
///   another is built before the old one is disposed, so the new one takes the
///   keyboard as it binds and the old one's unbind leaves a binding it no longer
///   owns alone. That covers the Dart side only: in Chrome, DOM focus still
///   leaves with the old view's element, and the engine reports that as the
///   whole view losing focus. So the page keeps one display with a global key.
/// - **The wheel is claimed**, or it would also scroll the page under the display.
/// - **The mouse is on only while this widget wins the hit test.** Flutter UI
///   drawn over a platform view does not stop the browser from delivering the
///   click to the element under it. Pointer events reach Flutter before the
///   compatibility mouse events v86 listens to, and Flutter dispatches them
///   synchronously, so a global pointer route turns v86's mouse on or off for
///   every event by whether this widget's [Listener] saw it first. A popover or
///   dialog over the display wins the hit test, and the program gets nothing.
/// - **No focus in the semantics tree.** With semantics on, the engine moves
///   DOM focus onto the element of whichever semantics node is focused. The
///   [Focus] adds none, or that move would take the keyboard from the guest the
///   moment the display gained it.
/// - **A crop that clicks still land in.** The view shows [region] only, by
///   moving v86's screen box inside a box that clips it (`web/vm/vm_screen.js`).
///   v86 maps a pointer through that screen box's bounding rect, which the move
///   is part of, so no offset of ours is added to any click.
class VmDisplay extends StatefulWidget {

  /// MUST stay the same for the widget's life. The platform view is created
  /// once, for the machine it was first built with, so another machine needs a
  /// display with a key of its own.
  final VmDisplayBinding binding;

  /// Given by the screen so it can move focus here; one of its own otherwise.
  final FocusNode? focusNode;

  /// What a screen reader is told this is. The canvas itself says nothing.
  final String semanticsLabel;

  /// The part of the guest's screen the view shows, in guest pixels.
  final Rect region;

  /// Logical pixels per guest pixel. The display MUST be laid out at
  /// [region]'s size times this: the view clips to its own box.
  final double scale;

  /// The colour around the guest's screen where the view is larger than it.
  final Color background;

  final ValueChanged<bool>? onFocusChange;

  /// Whether Tab goes to the guest rather than out of the display, which is
  /// while a program runs. With none there is nothing to type a Tab into, and
  /// holding it would keep the keyboard for nothing.
  final bool holdsTab;

  final VmViewBuilder viewBuilder;

  const VmDisplay({
    required this.binding,
    required this.region,
    required this.scale,
    required this.semanticsLabel,
    required this.background,
    this.focusNode,
    this.onFocusChange,
    this.holdsTab = true,
    this.viewBuilder = buildHtmlElementView,
    super.key,
  });

  @override
  State<VmDisplay> createState() => _VmDisplayState();

}

class _VmDisplayState extends State<VmDisplay> {

  /// The display that bound each binding last, which is the one whose keyboard
  /// and mouse it is.
  static final Expando<_VmDisplayState> _owners = Expando('VmDisplay owner');

  FocusNode? _ownNode;
  FocusNode get _node => widget.focusNode ?? (_ownNode ??= FocusNode(debugLabel: 'VmDisplay'));

  StreamSubscription<bool>? _domFocus;
  int? _viewId;

  /// Escape was the last key pressed, so a Tab now leaves.
  bool _escapeArmed = false;

  /// This widget's [Listener] saw the pointer event now being routed.
  bool _hit = false;

  /// What v86's mouse was last set to, so the route only crosses into JS when
  /// it changes.
  bool _mouseEnabled = false;

  /// What [VmDisplay.onFocusChange] was last told.
  bool _reportedFocus = false;

  @override
  void initState() {
    super.initState();
    _bind(widget.binding);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_route);
  }

  @override
  void didUpdateWidget(VmDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    assert(oldWidget.binding == widget.binding, 'A display for another machine needs a key of its own.');
    if (oldWidget.focusNode != widget.focusNode && oldWidget.focusNode == null) {
      _ownNode?.dispose();
      _ownNode = null;
    }
    if (oldWidget.background != widget.background) widget.binding.setBackground(widget.background);
    // Only the display that bound last: one it replaced can still be mounted, and
    // must not move the screen under its successor.
    if ((oldWidget.region != widget.region || oldWidget.scale != widget.scale) && _owns(widget.binding)) {
      widget.binding.showRegion(widget.region, widget.scale);
    }
  }

  @override
  void dispose() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_route);
    final owned = _owns(widget.binding);
    _unbind(widget.binding);
    // [Focus] stops listening before it lets go of a focused node, so a display
    // disposed with the keyboard would otherwise leave its owner thinking it
    // still has it. A display that replaced this one has the keyboard now.
    if (_reportedFocus && owned) widget.onFocusChange?.call(false);
    _ownNode?.dispose();
    super.dispose();
  }

  bool _owns(VmDisplayBinding binding) => identical(_owners[binding], this);

  void _bind(VmDisplayBinding binding) {
    _owners[binding] = this;
    binding
      ..setBackground(widget.background)
      ..showRegion(widget.region, widget.scale)
      ..setMouseEnabled(false);
    _domFocus = binding.domFocus.listen(_onDomFocus);
    if (_node.hasFocus) {
      _reclaimKeyboard();
    } else {
      binding.setKeyboardEnabled(false);
    }
  }

  void _unbind(VmDisplayBinding binding) {
    unawaited(_domFocus?.cancel());
    _domFocus = null;
    if (_owns(binding)) {
      _owners[binding] = null;
      binding
        ..setKeyboardEnabled(false)
        ..setMouseEnabled(false);
    }
    if (_viewId case final int viewId) binding.releaseView(viewId);
  }

  /// Gives the guest the keyboard and DOM focus for a node that already holds
  /// Flutter focus, which no focus change is going to report: one handed over
  /// by a display this one replaced, or one whose keyboard went off without it.
  void _reclaimKeyboard() {
    widget.binding
      ..setKeyboardEnabled(true)
      ..focusElement();
    if (_reportedFocus) return;
    _reportedFocus = true;
    widget.onFocusChange?.call(true);
  }

  void _onDomFocus(bool inside) {
    if (!mounted) return;
    if (inside) {
      if (!_node.hasFocus) _node.requestFocus();
      return;
    }
    widget.binding.setKeyboardEnabled(false);
    if (_node.hasFocus) _node.unfocus();
  }

  void _onFocusChange(bool focused) {
    _escapeArmed = false;
    widget.binding.setKeyboardEnabled(focused);
    if (focused) {
      widget.binding.focusElement();
    } else {
      widget.binding.releaseFocus();
    }
    _reportedFocus = focused;
    widget.onFocusChange?.call(focused);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.tab && (_escapeArmed || !widget.holdsTab)) {
        _escapeArmed = false;
        // Now, before v86's own listener runs for this same key.
        widget.binding.setKeyboardEnabled(false);
        return KeyEventResult.ignored;
      }
      // Shift is part of Shift+Tab, which leaves backwards.
      if (!_modifiers.contains(event.logicalKey)) _escapeArmed = event.logicalKey == LogicalKeyboardKey.escape;
    }
    return KeyEventResult.skipRemainingHandlers;
  }

  static final Set<LogicalKeyboardKey> _modifiers = {
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
  };

  void _mark(PointerEvent event) => _hit = true;

  /// Runs after every hit-test target of the event, this widget's [Listener]
  /// included, because the gesture binding is the last entry in every path.
  void _route(PointerEvent event) {
    final hit = _hit;
    _hit = false;
    if (hit == _mouseEnabled) return;
    _mouseEnabled = hit;
    widget.binding.setMouseEnabled(hit);
  }

  void _onPointerDown(PointerDownEvent event) {
    _hit = true;
    if (_node.hasFocus) {
      _reclaimKeyboard();
    } else {
      _node.requestFocus();
    }
  }

  void _onPointerSignal(PointerSignalEvent event) {
    _hit = true;
    // Claimed with nothing to do: the guest scrolls, and the page must not.
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {});
  }

  void _onCreated(int viewId) {
    if (!mounted) {
      widget.binding.releaseView(viewId);
      return;
    }
    _viewId = viewId;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: widget.semanticsLabel,
      child: Focus(
        focusNode: _node,
        includeSemantics: false,
        onKeyEvent: _onKey,
        onFocusChange: _onFocusChange,
        child: Listener(
          onPointerDown: _onPointerDown,
          onPointerMove: _mark,
          onPointerUp: _mark,
          onPointerHover: _mark,
          onPointerCancel: _mark,
          onPointerSignal: _onPointerSignal,
          child: ExcludeFocus(child: widget.viewBuilder(context, widget.binding, _onCreated)),
        ),
      ),
    );
  }

}
