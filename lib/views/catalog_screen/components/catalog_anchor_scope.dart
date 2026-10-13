import 'package:flutter/widgets.dart';
import 'package:i_can_code/routing/catalog_anchor.dart';

/// Turns the anchor in the catalog's address into something its parts can act
/// on: a request to go there, and the one clock every part that lights up
/// draws from.
///
/// An `AnchorTarget` below is what moves and what lights up. This only says
/// when.
///
/// ## What this leans on
///
/// - auto_route hands a page new arguments in place, so [anchor] changes on a
///   mounted catalog. A change to an anchor is a request. A change to none is
///   not: the reader moved on, and the page stays where it is.
/// - An anchor that names nothing has no target, so nobody calls
///   [CatalogAnchorRequest.arrived] and nothing lights up. That is the whole
///   handling of an id the course does not have.
/// - One [AnimationController] rather than one per target, so a heading and
///   the cards under it pulse as one.
class CatalogAnchorScope extends StatefulWidget {

  /// Two rings, one after the other. A matter of taste, like [reducedHold].
  static const Duration ringDuration = Duration(milliseconds: 1400);

  /// How long the ring stands still for a reader who asked for less motion.
  /// There is no pulse to watch, so it is given the time to be found.
  static const Duration reducedHold = Duration(milliseconds: 1500);

  /// What the address asks for now. Null asks for nothing.
  final CatalogAnchor? anchor;

  final Widget child;

  const CatalogAnchorScope({required this.anchor, required this.child, super.key});

  /// The request in force, or null below no scope and before any anchor was
  /// asked for. Rebuilds the caller when a new one is made.
  static CatalogAnchorRequest? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_RequestScope>()?.request;

  @override
  State<CatalogAnchorScope> createState() => _CatalogAnchorScopeState();

}

/// One arrival at an anchor.
///
/// Compared by identity: asking for the same place a second time is a second
/// request.
class CatalogAnchorRequest {

  final CatalogAnchor anchor;

  /// From 0 to 1 while the place is lit, and at rest otherwise.
  final Animation<double> ring;

  final VoidCallback _onArrived;

  bool _taken = false;

  CatalogAnchorRequest._(this.anchor, this.ring, this._onArrived);

  /// Claims the request for the target that will go to it. True once.
  ///
  /// A target built later sees the same request, and must not send the page
  /// back to a place the reader has since scrolled away from.
  bool take() {
    if (_taken) return false;

    return _taken = true;
  }

  /// Called by the target once the page has come to rest on it, which is what
  /// starts [ring].
  void arrived() => _onArrived();

}

class _CatalogAnchorScopeState extends State<CatalogAnchorScope> with SingleTickerProviderStateMixin {

  late final AnimationController _ring = AnimationController(vsync: this);

  CatalogAnchorRequest? _request;

  @override
  void initState() {
    super.initState();
    _ask(widget.anchor);
  }

  @override
  void didUpdateWidget(CatalogAnchorScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.anchor != oldWidget.anchor) _ask(widget.anchor);
  }

  @override
  void dispose() {
    _ring.dispose();
    super.dispose();
  }

  void _ask(CatalogAnchor? anchor) {
    if (anchor == null) return;

    _ring.reset();
    _request = CatalogAnchorRequest._(anchor, _ring, _light);
  }

  void _light() {
    if (!mounted) return;

    // Not through `context.motion`: that answers no time at all, and a ring
    // that is gone in one frame points at nothing.
    _ring
      ..duration = MediaQuery.disableAnimationsOf(context)
          ? CatalogAnchorScope.reducedHold
          : CatalogAnchorScope.ringDuration
      ..forward(from: 0);
  }

  @override
  Widget build(BuildContext context) => _RequestScope(request: _request, child: widget.child);

}

class _RequestScope extends InheritedWidget {

  final CatalogAnchorRequest? request;

  const _RequestScope({required this.request, required super.child});

  @override
  bool updateShouldNotify(_RequestScope old) => !identical(request, old.request);

}
