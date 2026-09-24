import 'package:flutter/widgets.dart';

/// Where an introduction finds the things it points at, by what they are.
///
/// Not a [GlobalKey] per target. A key may be mounted only once, and the bar's
/// trail is swapped by a `FadeThrough` that keeps the outgoing copy mounted
/// while the incoming one fades in: two copies of one crumb, one key. Here the
/// later registration simply wins, and a copy that leaves takes only its own
/// entry with it.
class TourTargetRegistry {

  final Map<Object, BuildContext> _contexts = {};

  void _add(Object id, BuildContext context) => _contexts[id] = context;

  void _remove(Object id, BuildContext context) {
    if (identical(_contexts[id], context)) _contexts.remove(id);
  }

  /// Where [id] is on screen, in global coordinates. Null while it is not
  /// mounted or not yet laid out.
  Rect? rectOf(Object id) {
    final context = _contexts[id];
    if (context == null || !context.mounted) return null;

    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;

    return box.localToGlobal(Offset.zero) & box.size;
  }

}

/// Hands a [TourTargetRegistry] to every [TourTarget] below it.
class TourTargetScope extends InheritedWidget {

  final TourTargetRegistry registry;

  const TourTargetScope({required this.registry, required super.child, super.key});

  static TourTargetRegistry? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<TourTargetScope>()?.registry;

  @override
  bool updateShouldNotify(TourTargetScope old) => registry != old.registry;

}

/// Makes [child] something an introduction can point at, as [id].
///
/// A pass-through below no [TourTargetScope].
class TourTarget extends StatefulWidget {

  /// Compared by `==`, so a record such as `(part, index)` names one of many.
  final Object id;

  final Widget child;

  const TourTarget({required this.id, required this.child, super.key});

  @override
  State<TourTarget> createState() => _TourTargetState();

}

class _TourTargetState extends State<TourTarget> {

  TourTargetRegistry? _registry;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _registry?._remove(widget.id, context);
    _registry = TourTargetScope.maybeOf(context)?.._add(widget.id, context);
  }

  @override
  void didUpdateWidget(TourTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id == widget.id) return;
    _registry
      ?.._remove(oldWidget.id, context)
      .._add(widget.id, context);
  }

  @override
  void dispose() {
    _registry?._remove(widget.id, context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;

}
