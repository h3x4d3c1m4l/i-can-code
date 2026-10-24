import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/views/components/app_scrollbar.dart';

/// What the frame shows while no window of the program does: before the first
/// run, while a run has not mapped one yet, and after a run that had none.
///
/// Opaque, because it lies over the display: the guest's empty screen is a black
/// X root that says nothing, and the display has to stay built beneath it to
/// keep the keyboard Run gave it.
class NoWindowPanel extends StatelessWidget {

  final String text;

  const NoWindowPanel({required this.text, super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appTheme.colors;
    final style = context.appTheme.text;

    return ColoredBox(
      // The frame's own surface, whose pairing with codeMuted theme_test holds.
      color: colors.codeBackground,
      child: Center(
        child: ScrollConfiguration(
          behavior: const AppScrollBehavior(surface: ScrollSurface.code),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(FLucideIcons.appWindow, size: 28, color: colors.codeMuted),
                const SizedBox(height: 12),
                Text(
                  text,
                  textAlign: TextAlign.center,
                  style: style.bodySmall.copyWith(color: colors.codeMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

}
