import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:i_can_code/views/components/app_header.dart';
import 'package:i_can_code/views/components/app_header_host.dart';

/// Puts a screen's own header in the app's bar for as long as the screen is up.
///
/// Wraps the screen rather than sitting in it: the bar itself lives above the
/// router (see [AppHeaderHost]), and this is the only thing that reaches it.
/// Below no host — a widget test that builds one screen on its own — it is a
/// pass-through and the screen renders exactly as it did.
///
/// Both the publish and the release are **deferred by a microtask**, for two
/// reasons that happen to want the same thing:
///
/// - The bar is built before the screen is, so filling it from `initState`
///   would rebuild a widget that Flutter has already built this frame.
/// - A screen is disposed *after* its successor is created, so an immediate
///   release could empty a bar the next screen has already filled. Deferring
///   puts the claim and the release in the queue in the order they happened,
///   and the host keeps the claims of every screen still standing.
class AppHeaderPublisher extends StatefulWidget {

  final AppHeaderBuilder builder;
  final Widget child;

  const AppHeaderPublisher({required this.builder, required this.child, super.key});

  @override
  State<AppHeaderPublisher> createState() => _AppHeaderPublisherState();

}

class _AppHeaderPublisherState extends State<AppHeaderPublisher> {

  AppHeaderSlot? _slot;

  /// Delegates to whichever builder the widget currently carries, so the bar is
  /// published **once**: a screen that rebuilds does not have to hand its
  /// header over again, and the host resolves the current builder either way.
  AppHeaderConfig _resolve(BuildContext context) => widget.builder(context);

  @override
  void initState() {
    super.initState();
    scheduleMicrotask(_publish);
  }

  void _publish() {
    if (!mounted) return;
    _slot = AppHeaderScope.of(context)?..publish(this, _resolve);
  }

  @override
  void dispose() {
    final slot = _slot;
    scheduleMicrotask(() => slot?.release(this));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;

}
