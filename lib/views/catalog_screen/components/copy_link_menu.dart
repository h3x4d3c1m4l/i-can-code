import 'dart:async';

import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/views/catalog_screen/components/browser_menu_suppressor.dart';

/// Gives [child] a menu with "Link kopiëren", that puts an address on the
/// clipboard, and on a lesson's card also "Les opnieuw beginnen". It opens
/// where a right click lands, and from the keyboard on Shift+F10 or the menu
/// key while [child] has the focus.
///
/// The copy item says "Gekopieerd" for a moment before the menu closes, because
/// a copy changes nothing else the reader can see.
///
/// MUST be below an [Overlay], which every screen is: the menu is drawn in it.
///
/// ## What this leans on
///
/// - forui's popover is placed against its child, and corrects for the edge of
///   the window *before* it applies `offset`. So the menu is given a child of
///   no size at the pointer, rather than an offset from [child] that could
///   carry it out of the window.
/// - A press that is held is not a way in. forui's long-press recogniser wins
///   the arena from the child's own tap, and a card held a moment too long
///   would open this instead of its lesson. So a touch screen has no way to
///   it.
/// - A screen reader has neither a right click nor a menu key, so the copy is
///   a custom action on [child]'s own node, which is why the two are merged.
class CopyLinkMenu extends StatefulWidget {

  /// The address to copy. Asked for at the press and not before.
  final Uri Function() address;

  /// The "Les opnieuw beginnen" item, for a lesson's card. Null on anything
  /// else. [enabled] is asked each time the menu opens, so the item is greyed
  /// out exactly while there is nothing to forget.
  final ({bool Function() enabled, VoidCallback onPress})? restart;

  final Widget child;

  const CopyLinkMenu({required this.address, required this.child, this.restart, super.key});

  @override
  State<CopyLinkMenu> createState() => _CopyLinkMenuState();

}

class _CopyLinkMenuState extends State<CopyLinkMenu> with SingleTickerProviderStateMixin {

  static const Duration _confirmation = Duration(seconds: 1);

  /// Owned here for the reason `SettingsMenu`'s is: the popover does not open
  /// itself.
  late final FPopoverController _controller = FPopoverController(vsync: this);

  /// Where the menu opens, in [widget.child]'s own coordinates.
  Offset _at = Offset.zero;

  Timer? _close;
  bool _copied = false;

  @override
  void dispose() {
    _close?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _open(Offset at) {
    _close?.cancel();
    setState(() {
      _at = at;
      _copied = false;
    });
    unawaited(_controller.show());
  }

  /// From the keyboard there is no pointer to open at.
  void _openInTheMiddle() => _open(context.size!.center(Offset.zero));

  Future<void> _copy() async {
    final view = View.of(context);
    final announcement = context.localizations.catalogScreen_linkCopied;
    final direction = Directionality.of(context);

    try {
      await Clipboard.setData(ClipboardData(text: widget.address().toString()));
    } on PlatformException {
      // A browser MAY refuse the clipboard, and then there is nothing to confirm.
      if (mounted) unawaited(_controller.hide());
      return;
    }
    if (!mounted) return;

    setState(() => _copied = true);
    // The tick is a glyph, so a screen reader is told in words.
    unawaited(SemanticsService.sendAnnouncement(view, announcement, direction));
    _close?.cancel();
    _close = Timer(_confirmation, () => unawaited(_controller.hide()));
  }

  void _restart() {
    unawaited(_controller.hide());
    widget.restart?.onPress();
  }

  /// [Visibility] rather than `Visibility.maintain`, which would hand a screen
  /// reader the hidden label as well. `RunButton` swaps its two the same way.
  static Widget _label(String text, {required bool visible}) => Visibility(
    visible: visible,
    maintainSize: true,
    maintainAnimation: true,
    maintainState: true,
    child: Text(text),
  );

  @override
  Widget build(BuildContext context) {
    final localizations = context.localizations;
    final restart = widget.restart;
    final canRestart = restart?.enabled() ?? false;

    return Stack(
      // Whatever [widget.child] was given, it still gets: a card is stretched
      // to its column, and a heading is not.
      fit: StackFit.passthrough,
      children: [
        BrowserMenuSuppressor(
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.contextMenu): _openInTheMiddle,
              const SingleActivator(LogicalKeyboardKey.f10, shift: true): _openInTheMiddle,
            },
            child: MergeSemantics(
              child: Semantics(
                customSemanticsActions: {
                  CustomSemanticsAction(label: localizations.catalogScreen_copyLink): () => unawaited(_copy()),
                  // Always listed: this node is not rebuilt when a lesson is
                  // started, so `onPress` decides whether there is anything.
                  if (restart != null)
                    CustomSemanticsAction(label: localizations.catalogScreen_restartLesson): restart.onPress,
                },
                child: GestureDetector(
                  excludeFromSemantics: true,
                  onSecondaryTapUp: (details) => _open(details.localPosition),
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: _at.dx,
          top: _at.dy,
          child: FPopoverMenu(
            control: FPopoverControl.managed(controller: _controller),
            menuAnchor: Alignment.topLeft,
            childAnchor: Alignment.topLeft,
            menu: [
              FItemGroup(
                children: [
                  FItem(
                    prefix: Icon(_copied ? FLucideIcons.check : FLucideIcons.link),
                    // Both laid out and one painted, so the menu does not
                    // change width under the pointer when the item answers.
                    title: Stack(
                      alignment: AlignmentDirectional.centerStart,
                      children: [
                        _label(localizations.catalogScreen_copyLink, visible: !_copied),
                        _label(localizations.catalogScreen_linkCopied, visible: _copied),
                      ],
                    ),
                    onPress: () => unawaited(_copy()),
                  ),
                  if (restart != null)
                    FItem(
                      prefix: const Icon(FLucideIcons.rotateCcw),
                      title: Text(localizations.catalogScreen_restartLesson),
                      enabled: canRestart,
                      onPress: _restart,
                    ),
                ],
              ),
            ],
            child: const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }

}
