import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/l10n/generated/app_localizations.dart';
import 'package:i_can_code/services/vm/vm_runtime.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/theme.dart';
import 'package:i_can_code/views/components/vm/vm_load_panel.dart';
import 'package:i_can_code/views/components/vm/window_frame.dart';

/// Loads the app's own fonts, which `flutter test` otherwise draws every glyph
/// of as a square a whole em wide. In a file of its own, since a font once
/// loaded stays loaded for every later test in the process.
Future<void> _loadFonts() async {
  const families = {kDisplayFontFamily, kBodyFontFamily, kCodeFontFamily};
  final manifest = jsonDecode(await rootBundle.loadString('FontManifest.json')) as List<dynamic>;

  for (final family in manifest.cast<Map<String, dynamic>>()) {
    if (!families.contains(family['family'])) continue;

    final loader = FontLoader(family['family'] as String);
    for (final font in (family['fonts'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }
}

void main() {
  setUpAll(_loadFonts);

  // The panel stands in the frame's empty box until the machine is ready, and
  // a panel that scrolled there would hide the note under its own bottom edge.
  for (final locale in const [Locale('nl'), Locale('en')]) {
    testWidgets('fits the frame\'s stand-in size in $locale with the longest note, without scrolling', (tester) async {
      await tester.pumpWidget(
        FTheme(
          data: buildAppTheme(),
          child: Localizations(
            locale: locale,
            delegates: AppLocalizations.localizationsDelegates,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: MediaQuery(
                data: const MediaQueryData(size: Size(1400, 1000)),
                child: Center(
                  child: SizedBox.fromSize(
                    size: WindowFrame.emptySize,
                    child: const VmLoadPanel(
                      progress: VmLoadProgress(5000000, 20373228, bytesPerSecond: 2300000, remaining: Duration(seconds: 42), keeps: false),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
      expect(scroll.position.maxScrollExtent, 0, reason: 'the content is ${scroll.position.viewportDimension + scroll.position.maxScrollExtent} px tall');
    });
  }
}
