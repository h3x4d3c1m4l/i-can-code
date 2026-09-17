import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/l10n/generated/app_localizations.dart';
import 'package:i_can_code/services/microbit/microbit_link.dart';
import 'package:i_can_code/theme/theme.dart';
import 'package:i_can_code/views/components/app_button.dart';
import 'package:i_can_code/views/microbit_screen/components/microbit_board_summary.dart';
import 'package:i_can_code/views/microbit_screen/components/microbit_notice.dart';

/// Wraps [child] in what these widgets need: the app theme and the
/// localizations they read their words from.
Widget _host(Widget child) => FTheme(
  data: buildAppTheme(),
  child: Localizations(
    locale: const Locale('nl'),
    delegates: AppLocalizations.localizationsDelegates,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(size: Size(1200, 800)),
        child: Align(
          child: SizedBox(width: 700, child: SingleChildScrollView(child: child)),
        ),
      ),
    ),
  ),
);

void main() {
  group('the link on a platform without a core', () {
    test('reports itself unsupported rather than throwing', () {
      // This is what `flutter test` gets: the conditional import falls through
      // to the stub on the Dart VM. A screen must be able to build and explain
      // itself here, which it cannot do if any of this throws.
      final link = createMicrobitLink();

      expect(link.isSupported, isFalse);
      expect(link.dispose, returnsNormally);
    });

    test('answers empty rather than failing', () async {
      final link = createMicrobitLink();

      expect(await link.transportAvailable(), isFalse);
      expect(await link.requestAccess(), isFalse);
      expect(await link.listDevices(), isEmpty);
    });

    test('has a session that produces nothing and ends', () async {
      // The screen subscribes to this before it knows whether anything is
      // supported, so it has to be a real, empty, closed stream rather than
      // something that throws when listened to.
      final link = createMicrobitLink();

      expect(await link.events.toList(), isEmpty);
    });

    test('accepts the session verbs without doing anything', () async {
      final link = createMicrobitLink();

      await expectLater(link.connect(), completes);
      await expectLater(link.disconnect(), completes);
      expect(() => link.write('print(1)\r'), returnsNormally);
    });
  });

  group('MicrobitNotice', () {
    testWidgets('shows its heading and body', (tester) async {
      await tester.pumpWidget(_host(const MicrobitNotice(title: 'Geen micro:bit', body: 'Sluit het bordje aan.')));

      expect(find.text('Geen micro:bit'), findsOneWidget);
      expect(find.text('Sluit het bordje aan.'), findsOneWidget);
    });

    testWidgets('omits the machine detail and the action when there are none', (tester) async {
      await tester.pumpWidget(_host(const MicrobitNotice(title: 'Titel', body: 'Tekst.')));

      expect(find.byType(AppButton), findsNothing);
    });

    testWidgets('shows the core error under the explanation', (tester) async {
      await tester.pumpWidget(
        _host(
          MicrobitNotice(
            title: 'Titel',
            body: 'Tekst.',
            detail: 'RustLib.init(): failed to fetch',
            action: AppButton(onPress: () {}, child: const Text('Opnieuw')),
          ),
        ),
      );

      expect(find.text('RustLib.init(): failed to fetch'), findsOneWidget);
      expect(find.byType(AppButton), findsOneWidget);
    });
  });

  group('MicrobitBoardSummary', () {
    testWidgets('says it is connected, and to what', (tester) async {
      await tester.pumpWidget(
        _host(
          const MicrobitBoardSummary(
            device: MicrobitDevice(product: 'BBC micro:bit CMSIS-DAP'),
            info: MicrobitBoardInfo(
              boardId: '9906',
              boardVersion: MicrobitBoardVersion.v2,
              idSource: MicrobitIdSource.vendorCommand,
            ),
          ),
        ),
      );

      expect(find.text('Verbonden met micro:bit V2'), findsOneWidget);
      expect(find.byIcon(FLucideIcons.check), findsOneWidget);
      // The board's own USB name is detail, not a headline.
      expect(find.textContaining('CMSIS-DAP'), findsNothing);
    });

    testWidgets('keeps the detail out of the way until it is asked for', (tester) async {
      await tester.pumpWidget(
        _host(
          const MicrobitBoardSummary(
            device: MicrobitDevice(product: 'BBC micro:bit CMSIS-DAP'),
            info: MicrobitBoardInfo(
              vendor: 'Arm',
              product: 'DAPLink CMSIS-DAP',
              protocolVersion: '2.1.0',
              boardId: '9906',
              pageSize: 4096,
              pageCount: 128,
              idSource: MicrobitIdSource.vendorCommand,
            ),
          ),
        ),
      );

      // Above the terminal there is room for one line and nothing else.
      expect(find.textContaining('512 KB'), findsNothing);
      // The way in is an icon, and it carries a label for a screen reader.
      expect(find.byIcon(FLucideIcons.info), findsOneWidget);
    });

    testWidgets('has nothing to open when the board answered nothing', (tester) async {
      // An anonymized serial takes the board id with it, which is exactly the
      // case that must not offer an empty tooltip.
      await tester.pumpWidget(_host(const MicrobitBoardSummary(device: MicrobitDevice())));

      expect(find.text('Verbonden met micro:bit'), findsOneWidget);
      expect(find.byIcon(FLucideIcons.info), findsNothing);
    });

    testWidgets('names a board whose generation the table does not know', (tester) async {
      await tester.pumpWidget(_host(const MicrobitBoardSummary(device: MicrobitDevice(boardId: '9999'))));

      expect(find.text('Verbonden met micro:bit'), findsOneWidget);
      // The id it does have is worth keeping, as detail.
      expect(find.byIcon(FLucideIcons.info), findsOneWidget);
    });
  });

  group('groupSerial', () {
    test('breaks a DAPLink serial into groups of eight', () {
      // 48 unbroken hex characters have nowhere to wrap, which is what pushed
      // the tooltip off the edge of the window.
      expect(
        groupSerial('990636020005282026fc669c6d36d053000000006e052820'),
        '99063602 00052820 26fc669c 6d36d053 00000000 6e052820',
      );
    });

    test('leaves a short tail alone rather than reading past the end', () {
      expect(groupSerial('9906360200'), '99063602 00');
      expect(groupSerial(''), '');
    });
  });
}
