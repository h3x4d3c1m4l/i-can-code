import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:get_it/get_it.dart';
import 'package:i_can_code/l10n/generated/app_localizations.dart';
import 'package:i_can_code/services/python/python_runtime.dart';
import 'package:i_can_code/theme/theme.dart';
import 'package:i_can_code/views/about_screen/about_screen.dart';
import 'package:i_can_code/views/about_screen/components/about_card.dart';

/// An interpreter that loads when the test says so.
class _SlowRuntime implements PythonRuntime {

  final Completer<void> loaded = Completer<void>();

  bool _ready = false;

  @override
  bool get isSupported => true;

  @override
  String? get version => _ready ? 'Python 3.15.0' : null;

  @override
  Future<void> ready() async {
    await loaded.future;
    _ready = true;
  }

  @override
  Future<PythonResult> run(String code, {String stdin = ''}) => throw UnimplementedError();

  @override
  Future<void> cancel() async {}

  @override
  void dispose() {}

}

Future<void> _pump(WidgetTester tester) async {
  tester.view
    ..physicalSize = const Size(1400, 900)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    FTheme(
      data: buildAppTheme(),
      child: Localizations(
        locale: const Locale('nl'),
        delegates: AppLocalizations.localizationsDelegates,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Overlay(initialEntries: [OverlayEntry(builder: (_) => const AboutScreen())]),
        ),
      ),
    ),
  );
}

/// What the row named [label] says.
Finder _valueOf(String label, String value) =>
    find.descendant(of: find.widgetWithText(AboutRow, label), matching: find.text(value));

void main() {
  tearDown(GetIt.I.reset);

  testWidgets('says what this build cannot report, rather than leaving it out', (tester) async {
    GetIt.I.registerSingleton<PythonRuntime>(createPythonRuntime());

    await _pump(tester);
    await tester.pumpAndSettle();

    // A widget test registers no package info, has no rustc file to fetch and
    // no interpreter to load.
    expect(_valueOf('Versie', 'Onbekend'), findsOneWidget);
    expect(_valueOf('Rust', 'Onbekend'), findsOneWidget);
    expect(_valueOf('In de browser', 'Onbekend'), findsOneWidget);
    expect(find.text('Laden…'), findsNothing);
  });

  testWidgets('names what the build already knows', (tester) async {
    GetIt.I.registerSingleton<PythonRuntime>(createPythonRuntime());

    await _pump(tester);
    await tester.pumpAndSettle();

    expect(_valueOf('Draait als', 'JavaScript'), findsOneWidget);
    expect(_valueOf('Op de micro:bit', 'MicroPython-firmware 2.1.1'), findsOneWidget);
    expect(find.text('Broncode op GitHub'), findsOneWidget);
    expect(find.text('Licenties'), findsOneWidget);
  });

  testWidgets('loads the interpreter to ask it what it is', (tester) async {
    final runtime = _SlowRuntime();
    GetIt.I.registerSingleton<PythonRuntime>(runtime);

    await _pump(tester);
    await tester.pump();

    expect(_valueOf('In de browser', 'Laden…'), findsOneWidget);

    runtime.loaded.complete();
    await tester.pumpAndSettle();

    expect(_valueOf('In de browser', 'Python 3.15.0'), findsOneWidget);
  });
}
