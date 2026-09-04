import 'package:flutter/widgets.dart';

/// Gives its child an [Overlay] and a [Navigator] of its own, both the size of
/// the window.
///
/// The bar sits **above the router**, and the router's `Navigator` — the one
/// every screen's popovers and dialogs hang off — is below it. So the bar has
/// neither, and both are things it needs: forui's popover renders through an
/// `OverlayPortal`, which throws without an [Overlay] ancestor, and
/// `showFDialog` looks up a [Navigator]. That is what put a red error box where
/// the settings cog should be, and the error widget's own width then squeezed
/// the trail out of the row beside it.
///
/// The window rather than the bar, because both escape it: a menu the height of
/// the bar would be clipped to 76px, and a dialog's barrier has to cover the
/// page it is asking about.
///
/// **Declarative pages, not `onGenerateRoute`.** A route built by
/// `onGenerateRoute` keeps the page it was handed on the first frame, so the
/// router underneath would stop updating and the app would freeze on whatever
/// screen it started on. A [Page] is diffed on every rebuild instead: the
/// Navigator updates the live route's `settings` in place, which is where
/// [_HostPage] reads its child back out of.
class OverlayHost extends StatelessWidget {

  final Widget child;

  const OverlayHost({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    return Navigator(
      pages: [_HostPage(child: child)],
      // One page that is never popped: there is nothing here to remove.
      onDidRemovePage: (_) {},
    );
  }

}

class _HostPage extends Page<void> {

  final Widget child;

  const _HostPage({required this.child}) : super(key: const ValueKey('overlay-host'));

  @override
  Route<void> createRoute(BuildContext context) => PageRouteBuilder<void>(
    settings: this,
    // Nothing navigates to or from it, so there is nothing to animate.
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    // Read off the route rather than closed over: `this` is the page from the
    // frame the route was built in, and by now there is a newer one.
    pageBuilder: (context, _, _) => (ModalRoute.of(context)!.settings as _HostPage).child,
  );

}
