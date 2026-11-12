import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Keeps the browser's own context menu off [child], so a right click on it
/// can open a menu of the app's instead of both.
///
/// A no-op anywhere but on the web.
///
/// ## What this leans on
///
/// - [BrowserContextMenu] is one switch for the whole page. There is none per
///   widget, so this throws it while the pointer is over [child] and back when
///   it leaves. Everywhere else the browser's menu MUST keep working:
///   `SelectableCode` relies on it for Copy.
/// - A pointer is over a widget before it can click on it, so the switch is
///   thrown long before the `contextmenu` event it is there to stop.
/// - A widget taken away from under the pointer is sent no exit. `dispose`
///   stands in for it, or the browser's menu would stay off for the page.
/// - Two of these can overlap, a stuck group heading over a card, so the menu
///   comes back only when the pointer has left the last of them.
///
/// None of it runs under `flutter test`, where there is no browser. Check a
/// change to this in one: a right click on [child] shows no browser menu, and
/// a right click on a code sample still does.
class BrowserMenuSuppressor extends StatefulWidget {

  final Widget child;

  const BrowserMenuSuppressor({required this.child, super.key});

  @override
  State<BrowserMenuSuppressor> createState() => _BrowserMenuSuppressorState();

}

class _BrowserMenuSuppressorState extends State<BrowserMenuSuppressor> {

  /// How many of these the pointer is over, across the page.
  static int _hovered = 0;

  bool _inside = false;

  @override
  void dispose() {
    _leave();
    super.dispose();
  }

  void _enter() {
    if (_inside) return;
    _inside = true;

    if (_hovered++ == 0 && kIsWeb) unawaited(BrowserContextMenu.disableContextMenu());
  }

  void _leave() {
    if (!_inside) return;
    _inside = false;

    if (--_hovered == 0 && kIsWeb) unawaited(BrowserContextMenu.enableContextMenu());
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    // Not opaque: it watches the pointer, and must not take a hover away from
    // whatever lies behind [widget.child].
    opaque: false,
    onEnter: (_) => _enter(),
    onExit: (_) => _leave(),
    child: widget.child,
  );

}
