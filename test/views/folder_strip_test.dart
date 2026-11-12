import 'dart:convert';

import 'package:code_forge/code_forge.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/l10n/generated/app_localizations.dart';
import 'package:i_can_code/services/folder_store.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/theme.dart';
import 'package:i_can_code/views/components/code_editor/code_editing_controller.dart';
import 'package:i_can_code/views/components/files/file_button.dart';
import 'package:i_can_code/views/components/files/folder_strip.dart';

import '../support/code_editor.dart';

/// Loads the app's own fonts: the strip measures its buttons, and the test
/// font's square glyphs a whole em wide would measure something else.
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

/// What the strip asked of its page.
class _Page {

  final FolderStore folder = FolderStore();
  final List<({String name, String text, String? replacing})> saved = [];
  final List<String> deleted = [];

  Map<String, Uint8List> get files => folder.filesOf('python');

  void put(String path, String text) => folder.put('python', path, utf8.encode(text));

  FolderNameProblem? problemWith(String name, {String? current}) =>
      folder.problemWith('python', name, current: current);

  void save({required String name, required Uint8List bytes, String? replacing}) {
    saved.add((name: name, text: utf8.decode(bytes), replacing: replacing));
    if (replacing != null && replacing != name) folder.remove('python', replacing);
    folder.put('python', name, bytes);
  }

  void delete(String path) {
    deleted.add(path);
    folder.remove('python', path);
  }

}

Widget _host(_Page page, {double width = 700}) => FTheme(
  data: buildAppTheme(),
  child: Localizations(
    locale: const Locale('nl'),
    delegates: AppLocalizations.localizationsDelegates,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(size: Size(1200, 800)),
        child: Navigator(
          onGenerateRoute: (_) => PageRouteBuilder<void>(
            pageBuilder: (_, _, _) => Align(
              child: SizedBox(
                width: width,
                child: FolderStrip(
                  files: page.files,
                  problemWith: page.problemWith,
                  onSave: page.save,
                  onDelete: page.delete,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);

/// The editor in the open dialog. Its text is set through its controller,
/// because a key event types nothing into it.
CodeEditingController _editor(WidgetTester tester) => editorIn(tester);

/// Lets the editor's timers run out before the test ends.
Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.pump(codeForgeTimers);
}

void main() {
  late _Page page;

  setUpAll(_loadFonts);

  setUp(() => page = _Page());

  group('the line', () {
    testWidgets('shows every file that fits, after the button for a new one', (tester) async {
      page
        ..put('cijfers.csv', '')
        ..put('uit.csv', '');
      await tester.pumpWidget(_host(page));

      expect(find.bySemanticsLabel('Nieuw bestand'), findsOneWidget);
      expect(find.text('cijfers.csv'), findsOneWidget);
      expect(find.text('uit.csv'), findsOneWidget);
      expect(find.textContaining('+'), findsNothing);
    });

    testWidgets('follows the folder as it changes', (tester) async {
      await tester.pumpWidget(_host(page));
      expect(find.byType(FileButton), findsOneWidget);

      page.put('nieuw.csv', '');
      await tester.pump();

      expect(find.text('nieuw.csv'), findsOneWidget);
    });

    testWidgets('never takes a second line: what does not fit goes behind +N', (tester) async {
      for (var i = 1; i <= 6; i++) {
        page.put('bestand_$i.csv', '');
      }
      await tester.pumpWidget(_host(page, width: 320));

      expect(tester.getSize(find.byType(FolderStrip)).height, tester.getSize(find.byType(FileButton).first).height);
      final shown = find.textContaining('bestand_').evaluate().length;
      expect(shown, lessThan(6));
      expect(find.text('+${6 - shown}'), findsOneWidget);
      expect(find.bySemanticsLabel('Nog ${6 - shown} bestanden'), findsOneWidget);
    });

    testWidgets('lists the rest in a menu, and opens one from there', (tester) async {
      for (var i = 1; i <= 6; i++) {
        page.put('bestand_$i.csv', 'rij $i');
      }
      await tester.pumpWidget(_host(page, width: 320));
      final shown = find.textContaining('bestand_').evaluate().length;

      await tester.tap(find.text('+${6 - shown}'));
      await tester.pumpAndSettle();
      expect(find.text('bestand_6.csv'), findsOneWidget);

      await tester.tap(find.text('bestand_6.csv'));
      await _settle(tester);

      expect(_editor(tester).text, 'rij 6');
      await tester.tap(find.text('Annuleren'));
      await _settle(tester);
    });

    testWidgets('is one height, whatever a button holds', (tester) async {
      for (var i = 1; i <= 6; i++) {
        page.put('bestand_$i.csv', '');
      }
      await tester.pumpWidget(_host(page, width: 320));

      final heights = {for (final element in find.byType(FileButton).evaluate()) element.size!.height};
      expect(heights, hasLength(1), reason: 'the new-file button, the files and +N');
    });

    testWidgets('cuts a long name short rather than hiding it while some of it fits', (tester) async {
      page.put('een_heel_lange_naam_voor_de_cijfers_van_2026.csv', '');
      await tester.pumpWidget(_host(page, width: 300));

      expect(find.text('een_heel_lange_naam_voor_de_cijfers_van_2026.csv'), findsOneWidget);
      expect(find.textContaining('+'), findsNothing);
      expect(tester.getSize(find.byType(FolderStrip)).height, tester.getSize(find.byType(FileButton).first).height);
    });
  });

  group('a new file', () {
    testWidgets('is named, typed and saved', (tester) async {
      await tester.pumpWidget(_host(page));

      await tester.tap(find.bySemanticsLabel('Nieuw bestand'));
      await _settle(tester);
      await tester.enterText(find.byType(EditableText), 'cijfers.csv');
      _editor(tester).text = 'naam,cijfer\nSanne,7.5\n';
      await tester.tap(find.text('Opslaan'));
      await _settle(tester);

      expect(page.saved.single, (name: 'cijfers.csv', text: 'naam,cijfer\nSanne,7.5\n', replacing: null));
      expect(find.text('Opslaan'), findsNothing);
      expect(find.text('cijfers.csv'), findsOneWidget, reason: 'on the line now');
    });

    testWidgets('says why a name cannot be used, and saves nothing until it can', (tester) async {
      await tester.pumpWidget(_host(page));
      await tester.tap(find.bySemanticsLabel('Nieuw bestand'));
      await _settle(tester);

      await tester.enterText(find.byType(EditableText), 'main.py');
      await tester.tap(find.text('Opslaan'));
      await _settle(tester);

      expect(page.saved, isEmpty);
      expect(find.text('Die naam gebruikt de app zelf. Kies een andere.'), findsOneWidget);

      await tester.enterText(find.byType(EditableText), 'mijn.py');
      await tester.pumpAndSettle();
      expect(find.text('Die naam gebruikt de app zelf. Kies een andere.'), findsNothing);

      await tester.tap(find.text('Opslaan'));
      await _settle(tester);
      expect(page.saved.single.name, 'mijn.py');
    });

    testWidgets('is not thrown away by Escape or a press beside the dialog', (tester) async {
      await tester.pumpWidget(_host(page));
      await tester.tap(find.bySemanticsLabel('Nieuw bestand'));
      await _settle(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _settle(tester);
      await tester.tapAt(const Offset(5, 5));
      await _settle(tester);

      expect(find.text('Opslaan'), findsOneWidget);
      await tester.tap(find.text('Annuleren'));
      await _settle(tester);
      expect(find.text('Opslaan'), findsNothing);
      expect(page.saved, isEmpty);
    });

    testWidgets('can hold no more than a file may', (tester) async {
      await tester.pumpWidget(_host(page));
      await tester.tap(find.bySemanticsLabel('Nieuw bestand'));
      await _settle(tester);

      await tester.enterText(find.byType(EditableText), 'groot.txt');
      _editor(tester).text = 'x' * (FolderStoreBase.maxEditableBytes + 1);
      await tester.tap(find.text('Opslaan'));
      await _settle(tester);

      expect(page.saved, isEmpty);
      expect(find.textContaining('te veel tekst'), findsOneWidget);
      await tester.tap(find.text('Annuleren'));
      await _settle(tester);
    });
  });

  group('a file in the folder', () {
    testWidgets('opens in the editor, and saved unchanged writes nothing', (tester) async {
      // What `csv.writer` writes, which the editor shows without the \r.
      page.put('uit.csv', 'a,b\r\n1,2\r\n');
      await tester.pumpWidget(_host(page));

      await tester.tap(find.text('uit.csv'));
      await _settle(tester);
      expect(_editor(tester).text, 'a,b\n1,2\n');

      await tester.tap(find.text('Opslaan'));
      await _settle(tester);
      expect(page.saved, isEmpty);
      expect(find.text('Opslaan'), findsNothing);
    });

    testWidgets('has its buttons on one line', (tester) async {
      page.put('rapport.txt', 'a\n');
      await tester.pumpWidget(_host(page));
      await tester.tap(find.text('rapport.txt'));
      await _settle(tester);

      final tops = {
        for (final label in ['Verwijderen', 'Annuleren', 'Opslaan']) tester.getCenter(find.text(label)).dy.round(),
      };
      expect(tops, hasLength(1));
      await tester.tap(find.text('Annuleren'));
      await _settle(tester);
    });

    testWidgets('is changed and renamed in one go', (tester) async {
      page.put('oud.csv', 'a\n');
      await tester.pumpWidget(_host(page));

      await tester.tap(find.text('oud.csv'));
      await _settle(tester);
      await tester.enterText(find.byType(EditableText), 'nieuw.csv');
      _editor(tester).text = 'b\n';
      await tester.tap(find.text('Opslaan'));
      await _settle(tester);

      expect(page.saved.single, (name: 'nieuw.csv', text: 'b\n', replacing: 'oud.csv'));
      expect(page.files.keys, ['nieuw.csv']);
    });

    testWidgets('is deleted only once that is confirmed', (tester) async {
      page.put('weg.csv', 'a\n');
      await tester.pumpWidget(_host(page));
      await tester.tap(find.text('weg.csv'));
      await _settle(tester);

      await tester.tap(find.text('Verwijderen'));
      await _settle(tester);
      expect(find.text('weg.csv verwijderen?'), findsOneWidget);
      expect(page.deleted, isEmpty);

      await tester.tap(find.text('Verwijderen').last);
      await _settle(tester);

      expect(page.deleted, ['weg.csv']);
      expect(find.text('Opslaan'), findsNothing, reason: 'the file dialog closes with it');
    });

    testWidgets('that holds no text opens to read and delete only', (tester) async {
      page.folder.put('python', 'data.bin', Uint8List.fromList([0xff, 0xfe, 0x00]));
      await tester.pumpWidget(_host(page));

      await tester.tap(find.text('data.bin'));
      await tester.pumpAndSettle();

      expect(find.textContaining('geen tekst'), findsOneWidget);
      expect(find.text('Opslaan'), findsNothing);
      expect(find.text('Verwijderen'), findsOneWidget);
      expect(find.byType(CodeForge), findsNothing);

      await tester.tap(find.text('Sluiten'));
      await tester.pumpAndSettle();
    });

    testWidgets('too large to edit opens to read, and shows the start of it', (tester) async {
      page.put('groot.txt', 'eerste regel\n${'x' * FolderStoreBase.maxEditableBytes}');
      await tester.pumpWidget(_host(page));

      await tester.tap(find.text('groot.txt'));
      await tester.pumpAndSettle();

      expect(find.textContaining('te groot om hier te bewerken'), findsOneWidget);
      expect(find.textContaining('eerste regel'), findsOneWidget);
      expect(find.byType(CodeForge), findsNothing);
      await tester.tap(find.text('Sluiten'));
      await tester.pumpAndSettle();
    });
  });
}
