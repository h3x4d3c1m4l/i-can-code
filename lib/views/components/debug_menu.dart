import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:forui/forui.dart';
import 'package:get_it/get_it.dart';
import 'package:i_can_code/services/color_vision_controller.dart';
import 'package:i_can_code/services/mobile_browser_warning.dart';
import 'package:i_can_code/services/tour_store.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/views/components/app_button.dart';

/// Developer tools behind Alt+B, in release builds as well, so a simulation can
/// be shown on the deployed site. The app is open source, so the key hides
/// nothing. The cog offers the same menu in debug builds only.
///
/// A handler on [HardwareKeyboard] rather than `Shortcuts`: those only hear a
/// key while the focus is somewhere below them, and on a freshly opened page
/// nothing has the focus at all. It matches the *physical* B, because Option+B
/// on a Mac types "∫" and reports that as its logical key.
///
/// MUST sit below a [Navigator], which the dialog is pushed onto.
class DebugMenu extends StatefulWidget {

  final Widget child;

  const DebugMenu({required this.child, super.key});

  /// Opens the menu from below it, as Alt+B does. Null below no [DebugMenu].
  static VoidCallback? opener(BuildContext context) {
    final state = context.findAncestorStateOfType<_DebugMenuState>();
    return state == null ? null : () => unawaited(state._show());
  }

  @override
  State<DebugMenu> createState() => _DebugMenuState();

}

class _DebugMenuState extends State<DebugMenu> {

  bool _open = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    final keys = HardwareKeyboard.instance;
    // Alt and nothing else: ⌘⌥B is Chrome's bookmark manager on a Mac, and
    // Alt+Shift+B moves to the bookmarks bar in Chrome and Edge.
    if (event is! KeyDownEvent ||
        event.physicalKey != PhysicalKeyboardKey.keyB ||
        !keys.isAltPressed ||
        keys.isControlPressed ||
        keys.isMetaPressed ||
        keys.isShiftPressed) {
      return false;
    }
    // Handled either way, so the "∫" does not land in a code editor.
    unawaited(_show());
    return true;
  }

  Future<void> _show() async {
    if (_open) return;
    _open = true;
    await showFDialog<void>(
      context: context,
      builder: (context, style, animation) => FDialog(
        animation: animation,
        builder: (context, style) => const _DebugPanel(),
      ),
    );
    _open = false;
  }

  @override
  Widget build(BuildContext context) => widget.child;

}

/// Not localized: a student only meets it by knowing the key.
class _DebugPanel extends StatelessWidget {

  const _DebugPanel();

  @override
  Widget build(BuildContext context) {
    final tours = GetIt.I.isRegistered<TourStore>() ? GetIt.I<TourStore>() : null;
    final seen = tours?.seen ?? const <String>{};
    final mobileWarning = GetIt.I.isRegistered<MobileBrowserWarning>() ? GetIt.I<MobileBrowserWarning>() : null;
    final colorVision = GetIt.I.isRegistered<ColorVisionController>() ? GetIt.I<ColorVisionController>() : null;

    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Debug', style: context.appTheme.text.h3),
          if (colorVision != null) ...[
            const SizedBox(height: 20),
            _DebugRow(title: 'Colour vision', control: _ColorVisionPicker(colorVision)),
          ],
          const SizedBox(height: 20),
          _DebugRow(
            title: 'Tips',
            status: seen.isEmpty ? 'None seen yet.' : 'Seen: ${(seen.toList()..sort()).join(', ')}',
            control: AppButton(
              tone: AppButtonTone.neutral,
              icon: FLucideIcons.rotateCcw,
              // Closes as well, so the tip the current screen offers again is
              // not hidden behind this dialog.
              onPress: tours == null || seen.isEmpty
                  ? null
                  : () {
                      unawaited(tours.clear());
                      Navigator.of(context).pop();
                    },
              child: const Text('Show tips again'),
            ),
          ),
          const SizedBox(height: 20),
          _DebugRow(
            title: 'Mobile warning',
            status: mobileWarning?.dismissed ?? false ? 'Dismissed in this browser.' : 'Not dismissed.',
            control: AppButton(
              tone: AppButtonTone.neutral,
              icon: FLucideIcons.rotateCcw,
              // Shown again at the next start, and only in a mobile browser.
              onPress: mobileWarning == null || !mobileWarning.dismissed
                  ? null
                  : () {
                      unawaited(mobileWarning.clear());
                      Navigator.of(context).pop();
                    },
              child: const Text('Ask again'),
            ),
          ),
          const SizedBox(height: 28),
          Align(
            alignment: Alignment.centerRight,
            child: AppButton(
              onPress: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ),
        ],
      ),
    );
  }

}

/// A setting and its state on the left, and what changes it on the right. One
/// line each, so the dialog still fits a short window as it grows.
class _DebugRow extends StatelessWidget {

  final String title;
  final String? status;
  final Widget control;

  const _DebugRow({required this.title, required this.control, this.status});

  @override
  Widget build(BuildContext context) {
    final text = context.appTheme.text;
    final status = this.status;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: text.label),
              if (status != null) ...[
                const SizedBox(height: 4),
                Text(status, style: text.bodySmall.copyWith(color: context.theme.colors.mutedForeground)),
              ],
            ],
          ),
        ),
        const SizedBox(width: 16),
        control,
      ],
    );
  }

}

/// The simulation in use on a button, and every one in a menu under it.
class _ColorVisionPicker extends StatefulWidget {

  final ColorVisionController colorVision;

  const _ColorVisionPicker(this.colorVision);

  @override
  State<_ColorVisionPicker> createState() => _ColorVisionPickerState();

}

class _ColorVisionPickerState extends State<_ColorVisionPicker> with SingleTickerProviderStateMixin {

  /// Owned here for the reason `SettingsMenu` gives: the popover does not open
  /// itself.
  late final FPopoverController _controller = FPopoverController(vsync: this);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorVision = widget.colorVision;

    return Observer(
      builder: (context) => FPopoverMenu(
        control: FPopoverControl.managed(controller: _controller),
        menuAnchor: Alignment.topRight,
        childAnchor: Alignment.bottomRight,
        menu: [
          FItemGroup(
            children: [
              for (final deficiency in ColorVisionDeficiency.values)
                FItem(
                  title: Text(_nameOf(deficiency)),
                  subtitle: switch (_lossOf(deficiency)) {
                    final loss? => Text(loss),
                    null => null,
                  },
                  suffix: colorVision.deficiency == deficiency ? const Icon(FLucideIcons.check) : null,
                  onPress: () {
                    colorVision.simulate(deficiency);
                    unawaited(_controller.hide());
                  },
                ),
            ],
          ),
        ],
        child: AppButton(
          tone: AppButtonTone.neutral,
          icon: FLucideIcons.chevronDown,
          iconSide: AppButtonIconSide.trailing,
          onPress: _controller.toggle,
          child: Text(_nameOf(colorVision.deficiency)),
        ),
      ),
    );
  }

  String _nameOf(ColorVisionDeficiency deficiency) => switch (deficiency) {
    ColorVisionDeficiency.none => 'Normal',
    ColorVisionDeficiency.protanopia => 'Protanopia',
    ColorVisionDeficiency.deuteranopia => 'Deuteranopia',
    ColorVisionDeficiency.tritanopia => 'Tritanopia',
    ColorVisionDeficiency.achromatopsia => 'Achromatopsia',
  };

  String? _lossOf(ColorVisionDeficiency deficiency) => switch (deficiency) {
    ColorVisionDeficiency.none => null,
    ColorVisionDeficiency.protanopia => 'No red',
    ColorVisionDeficiency.deuteranopia => 'No green',
    ColorVisionDeficiency.tritanopia => 'No blue',
    ColorVisionDeficiency.achromatopsia => 'No colour at all',
  };

}
