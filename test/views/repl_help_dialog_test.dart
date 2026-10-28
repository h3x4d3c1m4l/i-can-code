import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/l10n/generated/app_localizations.dart';
import 'package:i_can_code/theme/theme.dart';
import 'package:i_can_code/views/components/app_button.dart';
import 'package:i_can_code/views/repl_screen/components/repl_help_dialog.dart';

/// Opens the help over an empty page in a window [height] tall.
Future<void> _open(WidgetTester tester, {required double height}) async {
  const width = 1280.0;
  tester.view.physicalSize = Size(width, height);
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
            data: MediaQueryData(size: Size(width, height)),
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

  unawaited(showReplHelpDialog(page));
  await tester.pumpAndSettle();
}

void main() {
  // The text above the table once stood still, and on a short window it left
  // the table no room at all.
  testWidgets('scrolls the text with the table, and keeps the button on a short window', (tester) async {
    await _open(tester, height: 400);

    final text = find.textContaining('Wat je typt');
    final table = find.text('Enter');
    final scrollView = find.byType(SingleChildScrollView);
    expect(find.ancestor(of: text, matching: scrollView), findsOneWidget);
    expect(find.ancestor(of: table, matching: scrollView), findsOneWidget);

    expect(tester.getRect(find.widgetWithText(AppButton, 'Sluiten')).bottom, lessThanOrEqualTo(400));
  });
}
