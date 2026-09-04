import 'package:flutter/widgets.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/views/components/app_header.dart';
import 'package:i_can_code/views/components/header_icon_button.dart';
import 'package:i_can_code/views/components/overlay_host.dart';

/// What a screen can ask of the header.
///
/// Implemented by [AppHeaderHost]'s state and reached through [AppHeaderScope],
/// so a screen does not have to know where the bar actually is.
abstract interface class AppHeaderSlot {

  /// Claims the bar for [owner], which fills it for as long as it is the last
  /// screen standing.
  void publish(Object owner, AppHeaderBuilder builder);

  /// Gives up [owner]'s claim. The bar falls back to the screen underneath it
  /// when there still is one, and empties only when there is not.
  void release(Object owner);

}

/// Hands [AppHeaderSlot] to everything below the bar.
///
/// Looked up with [BuildContext.getInheritedWidgetOfExactType], which creates no
/// dependency: a screen tells the bar what to show, it does not rebuild with it.
class AppHeaderScope extends InheritedWidget {

  final AppHeaderSlot slot;

  const AppHeaderScope({required this.slot, required super.child, super.key});

  /// Null below no host at all — a widget test that builds one screen, and the
  /// initialization screen's own tree before the shell is up.
  static AppHeaderSlot? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppHeaderScope>()?.slot;

  @override
  bool updateShouldNotify(AppHeaderScope old) => slot != old.slot;

}

/// Holds the app's bar **above the router**, so navigating cannot move it.
///
/// The bar used to be the first child of every screen's own column, which meant
/// a new screen brought a new bar: it was rebuilt from nothing on arrival and it
/// travelled with whatever transition the page had. Here it is one widget for
/// the life of the app — the mark, the cog and the popover state stay put, and
/// only what actually changed about the trail fades over (see `FadeThrough`).
///
/// Screens fill it through `AppHeaderPublisher`, and **the last one to claim it
/// is the one it shows**. More than one screen is mounted at a time — a pushed
/// screen leaves the one under it standing, and a replaced one is disposed only
/// after its successor is built — so the bar cannot simply belong to whoever
/// spoke last and empty on the first release. Claims are kept in the order they
/// arrived, which for a page stack is bottom to top: the arriving screen takes
/// the bar, and a leaving one hands it back to the screen underneath rather
/// than clearing it.
///
/// ## Zen mode
///
/// A lesson is read, so its bar starts out of the way: on a screen whose header
/// says [AppHeaderConfig.offersZen] the bar is hidden and the page takes the
/// whole window. It is **one thing the reader turns on and off**, by a button
/// each way — the one in this file brings the bar back, the one in the bar puts
/// it away again — and the answer holds for the rest of the session, lesson
/// after lesson. There is deliberately nothing that reveals it by itself: a bar
/// that came and went with the pointer changed the page's height under the
/// reader's hands.
///
/// It is not persisted either. Reading one lesson without the chrome is not a
/// setting about the app.
class AppHeaderHost extends StatefulWidget {

  final Widget child;

  const AppHeaderHost({required this.child, super.key});

  @override
  State<AppHeaderHost> createState() => _AppHeaderHostState();

}

class _AppHeaderHostState extends State<AppHeaderHost> implements AppHeaderSlot {

  /// The bar arriving or leaving. The page does not move with it — see the
  /// band the bar slides in and out of, above.
  static const Duration _slide = Duration(milliseconds: 260);
  static const Curve _curve = Curves.easeOutCubic;

  /// Where the button that brings the bar back sits: exactly where the cog
  /// will be.
  ///
  /// It waits in the band the bar left behind, in the cog's own column
  /// ([AppHeader.chromeInset], so the two keep lining up once the bar stops
  /// filling the window) and at the cog's own height. Pressing it puts the cog
  /// under the pointer without either of them having moved.
  static const double _showBarTop = (AppHeader.height - HeaderIconButton.size) / 2;

  /// Every screen still standing, in the order they arrived. Insertion order is
  /// what makes the last entry the top of the stack.
  final Map<Object, AppHeaderBuilder> _claims = {};

  /// Scoped to the visit, not to the session: [publish] puts it back on.
  bool _zen = true;

  @override
  void publish(Object owner, AppHeaderBuilder builder) {
    if (!mounted) return;
    setState(() {
      _claims[owner] = builder;
      // **Every lesson opens without the bar.** A reader who asked for it back
      // asked for this lesson, not for every lesson after it — and a screen
      // that does not offer zen ignores this anyway.
      _zen = true;
    });
  }

  @override
  void release(Object owner) {
    if (!mounted || !_claims.containsKey(owner)) return;
    setState(() => _claims.remove(owner));
  }

  /// The header of the last screen still standing, or null below no screen that
  /// has one — the initialization screen.
  AppHeaderBuilder? get _builder => _claims.isEmpty ? null : _claims.values.last;

  @override
  Widget build(BuildContext context) {
    return AppHeaderScope(
      slot: this,
      // The cog's menu and its dialog have nowhere to go otherwise: the bar is
      // above the router, so the Overlay and Navigator every screen uses are
      // below it. See [OverlayHost].
      child: OverlayHost(
        // The builder is a screen's, so it reads the screen's observables. They
        // are tracked here rather than there, which is what lets the bar follow
        // a lesson's step without the screen pushing anything at it.
        child: Observer(
          // A header that reads no observables at all is normal here — the
          // language picker's trail is one fixed word — so the usual warning
          // would fire on every screen that has nothing to watch.
          warnWhenNoObservables: false,
          builder: (context) {
            final config = _builder?.call(context);
            final offersZen = config?.offersZen ?? false;
            final visible = config != null && !(offersZen && _zen);
            final motion = context.motion(_slide);

            return Stack(
              children: [
                // The page has the whole window, at every width and whether the
                // bar is showing or not, and its content passes *under* the bar
                // rather than being cut off above it. What keeps the first
                // screenful clear of the bar is the screen's own top padding —
                // [AppHeader.height], which every screen with a header adds to
                // it. A page inset from above instead would both clip its own
                // content against an invisible edge and reflow the lesson every
                // time either zen button was pressed.
                Positioned.fill(child: widget.child),
                // Below the bar in the stack, so the bar covers it on the way in
                // rather than fading out on top of it. Nothing is behind it
                // either way: the band it waits in is the bar's own.
                if (offersZen) _buildShowBar(context, visible: visible, motion: motion),
                _buildBar(context, config, visible: visible, motion: motion),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildBar(
    BuildContext context,
    AppHeaderConfig? config, {
    required bool visible,
    required Duration motion,
  }) {
    return AnimatedPositioned(
      duration: motion,
      curve: _curve,
      top: visible ? 0 : -AppHeader.height,
      left: 0,
      right: 0,
      height: AppHeader.height,
      // Nothing to fill it with: the initialization screen has no header at
      // all, and a bar parked off screen would still take a tab.
      child: config == null
          ? const SizedBox.shrink()
          // Off screen is not gone. Without both of these the bar would still
          // be read out, and still take the tab meant for the page.
          : ExcludeSemantics(
              excluding: !visible,
              child: ExcludeFocus(
                excluding: !visible,
                child: ColoredBox(
                  color: context.theme.colors.background,
                  child: AppHeader(
                    crumbs: config.crumbs,
                    onTapHome: config.onTapHome,
                    trailing: config.trailing,
                    onHide: config.offersZen ? () => setState(() => _zen = true) : null,
                    version: config.version,
                  ),
                ),
              ),
            ),
    );
  }

  /// The way back to the bar: without it, the bar is not out of the way, it is
  /// lost.
  Widget _buildShowBar(BuildContext context, {required bool visible, required Duration motion}) {
    return Positioned(
      top: _showBarTop,
      right: AppHeader.chromeInset(context),
      // Faded out is not gone either — the same two, for the same reasons.
      child: ExcludeSemantics(
        excluding: visible,
        child: IgnorePointer(
          ignoring: visible,
          child: AnimatedOpacity(
            duration: motion,
            curve: _curve,
            opacity: visible ? 0 : 1,
            child: HeaderIconButton(
              icon: FLucideIcons.panelTopOpen,
              semanticsLabel: context.localizations.appHeader_showBar,
              onPress: () => setState(() => _zen = false),
            ),
          ),
        ),
      ),
    );
  }

}
