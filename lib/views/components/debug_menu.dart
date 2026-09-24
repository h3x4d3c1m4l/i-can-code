import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:get_it/get_it.dart';
import 'package:i_can_code/services/tour_store.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/views/components/app_button.dart';

/// Developer tools behind Alt+B, in debug builds only. A pass-through in a
/// release build, where [kDebugMode] is a constant false and the handler is
/// never registered.
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

  @override
  State<DebugMenu> createState() => _DebugMenuState();

}

class _DebugMenuState extends State<DebugMenu> {

  bool _open = false;

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      HardwareKeyboard.instance.addHandler(_onKey);
    }
  }

  @override
  void dispose() {
    if (kDebugMode) {
      HardwareKeyboard.instance.removeHandler(_onKey);
    }
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.physicalKey != PhysicalKeyboardKey.keyB ||
        !HardwareKeyboard.instance.isAltPressed) {
      return false;
    }
    // Handled either way, so the "∫" does not land in a code editor.
    if (!_open) unawaited(_show());
    return true;
  }

  Future<void> _show() async {
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

/// Not localized: it exists only in debug builds, and never in front of a
/// student.
class _DebugPanel extends StatelessWidget {

  const _DebugPanel();

  @override
  Widget build(BuildContext context) {
    final text = context.appTheme.text;
    final muted = context.theme.colors.mutedForeground;
    final tours = GetIt.I.isRegistered<TourStore>() ? GetIt.I<TourStore>() : null;
    final seen = tours?.seen ?? const <String>{};

    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Debug', style: text.h3),
          const SizedBox(height: 20),
          Text('Tips', style: text.label),
          const SizedBox(height: 6),
          Text(
            seen.isEmpty ? 'None seen yet.' : 'Seen: ${(seen.toList()..sort()).join(', ')}',
            style: text.bodySmall.copyWith(color: muted),
          ),
          const SizedBox(height: 12),
          AppButton(
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
          const SizedBox(height: 24),
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
