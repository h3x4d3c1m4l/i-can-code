import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/l10n/generated/app_localizations.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/theme.dart';
import 'package:i_can_code/views/catalog_screen/components/restart_lesson_dialog.dart';
import 'package:i_can_code/views/components/app_button.dart';
import 'package:i_can_code/views/components/app_dialog.dart';

/// Loads the app's own fonts, which `flutter test` otherwise draws every glyph
/// of as a square a whole em wide, too wide for two buttons on a phone. In a
/// file of its own, since a font once loaded stays loaded for every later test
/// in the process.
Future<void> _loadFonts() async {
  const families = {kDisplayFontFamily, kBodyFontFamily};
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

/// Pumps an empty page in a window [width] wide and returns a context below
/// its Navigator, which is where `OverlayHost` puts every screen.
Future<BuildContext> _page(WidgetTester tester, {required double width}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  late BuildContext page;
  await tester.pumpWidget(
    FTheme(
      data: buildAppTheme(),
      child: Localizations(
        locale: const Locale('nl'),
        delegates: AppLocalizations.localizationsDelegates,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: MediaQueryData(size: Size(width, 800)),
            child: Navigator(
              onGenerateRoute: (_) => PageRouteBuilder<void>(
                pageBuilder: (_, _, _) => Builder(
                  builder: (context) {
                    page = context;
                    return const SizedBox.expand();
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  return page;
}

Future<void> _open(WidgetTester tester, BuildContext page, List<String> labels) async {
  unawaited(
    showAppDialog<void>(
      page,
      builder: (context) => AppDialog(
        title: const Text('Doorgaan?'),
        // Wider than the buttons. A dialog with less to say is only as wide as
        // its buttons, which then sit at the end edge whatever the row does.
        body: const Text('Een zin die breder is dan de twee knoppen eronder samen, zodat er naast ze ruimte overblijft.'),
        actions: [for (final label in labels) AppButton(onPress: () {}, child: Text(label))],
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Where the content of the dialog ends: its edge, less the dialog's padding.
double _endEdge(WidgetTester tester) => tester.getTopRight(find.byType(AppDialog)).dx - 28;

Rect _button(WidgetTester tester, String label) => tester.getRect(find.widgetWithText(AppButton, label));

void main() {
  setUpAll(_loadFonts);

  // A Wrap is as wide as its buttons, so one in a column that does not stretch
  // it had no room to move them, and they sat at the start edge.
  testWidgets('puts the buttons at the end edge, not under the start of the text', (tester) async {
    final page = await _page(tester, width: 1280);
    await _open(tester, page, ['Annuleren', 'Doorgaan']);

    expect(_button(tester, 'Doorgaan').right, closeTo(_endEdge(tester), 0.5));
    expect(_button(tester, 'Annuleren').right, lessThan(_button(tester, 'Doorgaan').left));
  });

  testWidgets('breaks buttons that do not fit side by side into lines, each at the end edge', (tester) async {
    final page = await _page(tester, width: 360);
    await _open(tester, page, ['Annuleren', 'Opnieuw beginnen']);

    final first = _button(tester, 'Annuleren');
    final second = _button(tester, 'Opnieuw beginnen');
    expect(second.top, greaterThan(first.bottom), reason: 'the two did not wrap at this width');
    expect(first.right, closeTo(_endEdge(tester), 0.5));
    expect(second.right, closeTo(_endEdge(tester), 0.5));
  });

  testWidgets('puts the buttons of the restart question at the end edge', (tester) async {
    final page = await _page(tester, width: 1280);
    unawaited(showRestartLessonDialog(page, lesson: 'Uitvoer'));
    await tester.pumpAndSettle();

    expect(_button(tester, 'Opnieuw beginnen').right, closeTo(_endEdge(tester), 0.5));
  });
}
