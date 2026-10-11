import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/app_info.dart';
import 'package:i_can_code/l10n/generated/app_localizations.dart';
import 'package:i_can_code/services/licenses/bundled_licenses.dart';
import 'package:i_can_code/theme/theme.dart';
import 'package:i_can_code/views/components/app_button.dart';
import 'package:i_can_code/views/components/catalog_group_heading.dart';
import 'package:i_can_code/views/licenses_screen/components/license_detail.dart';
import 'package:i_can_code/views/licenses_screen/components/license_row.dart';
import 'package:i_can_code/views/licenses_screen/licenses_screen.dart';

const Size _wide = Size(1400, 900);

/// Under `lg`, where the list and the text are shown one at a time.
const Size _narrow = Size(800, 900);

/// The screen at [size], under the [Overlay] the app has above every screen.
Future<void> _pump(WidgetTester tester, {Size size = _wide}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    FTheme(
      data: buildAppTheme(),
      child: Localizations(
        locale: const Locale('nl'),
        delegates: AppLocalizations.localizationsDelegates,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Overlay(initialEntries: [OverlayEntry(builder: (_) => const LicensesScreen())]),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _row(String name) => find.widgetWithText(LicenseRow, name);

LicenseDetail _detail(WidgetTester tester) => tester.widget(find.byType(LicenseDetail));

void main() {
  setUp(() {
    // The test binding registers no licences of its own, so this is the whole
    // registry: one entry of each kind the screen tells apart.
    LicenseRegistry.addLicense(
      () => Stream.fromIterable(const [
        LicenseEntryWithLineBreaks([kAppPackage], 'The licence of the app.'),
        LicenseEntryWithLineBreaks(['mobx'], 'The licence of mobx.'),
        BundledLicenseEntry(LicenseOrigin.rust, ['nusb'], 'The licence of nusb.'),
        BundledLicenseEntry(LicenseOrigin.rust, ['nusb'], 'A second one for nusb.'),
        BundledLicenseEntry(LicenseOrigin.python, ['CPython'], 'The licence of CPython.'),
      ]),
    );
  });

  tearDown(LicenseRegistry.reset);

  testWidgets('the list is grouped by origin, the app first', (tester) async {
    await _pump(tester);

    final headings = tester.widgetList<CatalogGroupHeading>(find.byType(CatalogGroupHeading)).map((it) => it.label);
    expect(headings, ['Deze app', 'Python', 'Rust', 'Dart & Flutter']);

    // By its title, not by the package name the registry files it under.
    expect(_row('I Can Code'), findsOneWidget);
    expect(_row(kAppPackage), findsNothing);
  });

  testWidgets('the app\'s own licence is open before anything is picked', (tester) async {
    await _pump(tester);

    expect(_detail(tester).name, 'I Can Code');
    expect(_detail(tester).texts, ['The licence of the app.']);
    expect(tester.widget<LicenseRow>(_row('I Can Code')).selected, isTrue);
  });

  testWidgets('picking a component shows every text that covers it', (tester) async {
    await _pump(tester);

    await tester.tap(_row('nusb'));
    await tester.pumpAndSettle();

    expect(_detail(tester).origin, 'Rust');
    expect(_detail(tester).texts, ['The licence of nusb.', 'A second one for nusb.']);
    expect(find.text('2 licenties'), findsOneWidget);
    expect(tester.widget<LicenseRow>(_row('nusb')).selected, isTrue);
    expect(tester.widget<LicenseRow>(_row('I Can Code')).selected, isFalse);
  });

  testWidgets('the search narrows the list and drops an empty group', (tester) async {
    await _pump(tester);

    await tester.enterText(find.byType(EditableText), 'NUS');
    await tester.pumpAndSettle();

    expect(_row('nusb'), findsOneWidget);
    expect(find.byType(LicenseRow), findsOneWidget);
    expect(find.byType(CatalogGroupHeading), findsOneWidget);

    await tester.enterText(find.byType(EditableText), 'no such thing');
    await tester.pumpAndSettle();

    expect(find.byType(LicenseRow), findsNothing);
    expect(find.text('Niets gevonden.'), findsOneWidget);
  });

  testWidgets('the app is found by its title', (tester) async {
    await _pump(tester);

    await tester.enterText(find.byType(EditableText), 'can code');
    await tester.pumpAndSettle();

    expect(_row('I Can Code'), findsOneWidget);
  });

  testWidgets('a narrow window shows the list, then one component, then the list again', (tester) async {
    await _pump(tester, size: _narrow);

    expect(find.byType(LicenseDetail), findsNothing);
    expect(tester.widget<LicenseRow>(_row('I Can Code')).selected, isFalse, reason: 'nothing is open yet');

    await tester.tap(_row('CPython'));
    await tester.pumpAndSettle();

    expect(_detail(tester).name, 'CPython');
    expect(find.byType(LicenseRow), findsNothing);

    await tester.tap(find.widgetWithText(AppButton, 'Alle onderdelen'));
    await tester.pumpAndSettle();

    expect(find.byType(LicenseDetail), findsNothing);
    expect(_row('CPython'), findsOneWidget);
  });

  testWidgets('a narrow window comes back to the list as it was searched', (tester) async {
    await _pump(tester, size: _narrow);

    await tester.enterText(find.byType(EditableText), 'cpy');
    await tester.pumpAndSettle();
    await tester.tap(_row('CPython'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(AppButton, 'Alle onderdelen'));
    await tester.pumpAndSettle();

    // The list was taken away while the component was open. A field that came
    // back empty over a list still narrowed would hide every other component.
    expect(tester.widget<EditableText>(find.byType(EditableText)).controller.text, 'cpy');
    expect(find.byType(LicenseRow), findsOneWidget);
  });

  testWidgets('a registry that cannot be read says so, and a retry reads it', (tester) async {
    var broken = true;
    LicenseRegistry.reset();
    LicenseRegistry.addLicense(
      () => broken
          ? Stream.error(StateError('an asset is missing'))
          : Stream.fromIterable(const [LicenseEntryWithLineBreaks(['mobx'], 'The licence of mobx.')]),
    );

    await _pump(tester);

    expect(find.text('De licenties konden niet geladen worden'), findsOneWidget);
    expect(find.byType(LicenseRow), findsNothing);

    broken = false;
    await tester.tap(find.widgetWithText(AppButton, 'Opnieuw proberen'));
    await tester.pumpAndSettle();

    expect(_row('mobx'), findsOneWidget);
  });
}
