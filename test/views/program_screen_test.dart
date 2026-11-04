import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/l10n/generated/app_localizations.dart';
import 'package:i_can_code/services/folder_store.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/progress/code_draft_store.dart';
import 'package:i_can_code/services/python/python_repl.dart';
import 'package:i_can_code/services/python/python_runtime.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/theme.dart';
import 'package:i_can_code/views/base/build_context_accessor.dart';
import 'package:i_can_code/views/components/code_editor_card.dart';
import 'package:i_can_code/views/components/repl_terminal.dart';
import 'package:i_can_code/views/program_screen/program_screen_controller.dart';
import 'package:i_can_code/views/program_screen/program_screen_view.dart';
import 'package:i_can_code/views/program_screen/program_screen_view_model.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// Loads the app's own fonts, which `flutter test` otherwise draws every glyph
/// of as a square a whole em wide. The page has to fit the window without a
/// scroll view, and only the real fonts say whether it does.
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

/// An interpreter that does what the test tells it to, and records what it was
/// handed.
class _FakeSession implements PythonRepl {

  final String? program;
  final bool supported;

  /// The folder it was started with.
  final Map<String, Uint8List> files;

  /// What the page said about the folder since, in order. Null is a removal.
  final List<(String, Uint8List?)> said = [];

  final StreamController<ReplEvent> _events = StreamController<ReplEvent>.broadcast();

  /// Every line the page wrote to standard input.
  final List<String> written = [];

  bool started = false;
  bool disposed = false;

  _FakeSession({required this.program, required this.supported, this.files = const {}});

  void emit(ReplEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  @override
  bool get isSupported => supported;

  @override
  Stream<ReplEvent> get events => _events.stream;

  @override
  Future<void> start() async => started = true;

  @override
  void write(String text) => written.add(text);

  @override
  void endInput() {}

  @override
  void putFile(String path, Uint8List bytes) => said.add((path, bytes));

  @override
  void removeFile(String path) => said.add((path, null));

  @override
  bool get isWaitingForInput => false;

  @override
  void dispose() {
    disposed = true;
    unawaited(_events.close());
  }

}

class _NamedRuntime implements PythonRuntime {

  @override
  bool get isSupported => true;

  @override
  String? get version => 'Python 3.15.0';

  @override
  Future<void> ready() async {}

  @override
  Future<PythonResult> run(String code, {String stdin = ''}) => throw UnimplementedError();

  @override
  Future<void> cancel() async {}

  @override
  void dispose() {}

}

void main() {
  late List<_FakeSession> sessions;
  late CodeDraftStore drafts;
  late FolderStore folder;
  late ProgramScreenViewModel viewModel;
  late ProgramScreenController controller;

  /// The runs the page started. The page also makes one with no program to ask
  /// whether this browser can run one at all, and starts nothing with it.
  List<_FakeSession> runs() => sessions.where((session) => session.program != null).toList();

  String screen() => viewModel.terminal.buffer.getText();

  /// The page as it ships, in a window of [size], on an interpreter this
  /// browser can host unless [supported] says otherwise.
  Future<void> open(WidgetTester tester, {bool supported = true, Size size = const Size(1400, 1000)}) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final accessor = BuildContextAccessor();
    viewModel = ProgramScreenViewModel(contextAccessor: accessor, subjectSlug: 'learn-python', folder: folder);
    controller = ProgramScreenController(
      viewModel: viewModel,
      contextAccessor: accessor,
      drafts: drafts,
      runtime: _NamedRuntime(),
      createSession: ({program, files = const {}}) {
        final session = _FakeSession(program: program, supported: supported, files: Map.of(files));
        sessions.add(session);
        return session;
      },
    );
    final view = ProgramScreenView(viewModel: viewModel, controller: controller, contextAccessor: accessor);

    await tester.pumpWidget(
      FTheme(
        data: buildAppTheme(),
        child: Localizations(
          locale: const Locale('nl'),
          delegates: AppLocalizations.localizationsDelegates,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: MediaQuery(
              data: MediaQueryData(size: size),
              child: Navigator(
                onGenerateRoute: (_) => PageRouteBuilder<void>(
                  pageBuilder: (context, _, _) {
                    accessor.buildContext = context;
                    return view.body;
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // re_editor starts its caret from a timer nothing cancels.
    await tester.pump(const Duration(milliseconds: 150));
  }

  /// Leaves the page, so neither the draft's timer nor the editor's caret is
  /// left pending.
  Future<void> leave(WidgetTester tester) async {
    // A change to the code restarts the caret's timer, which then has to fire
    // while the editor is still there.
    await tester.pump(const Duration(milliseconds: 150));
    controller.dispose();
    await tester.pumpWidget(const SizedBox());
  }

  setUpAll(_loadFonts);

  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    sessions = [];
    drafts = CodeDraftStore();
    folder = FolderStore();
  });

  testWidgets('runs what is in the editor, on an empty terminal', (tester) async {
    await open(tester);
    viewModel.terminal.write('van een vorige run');
    viewModel.code.text = 'print(1)';

    controller.run();

    expect(runs().single.program, 'print(1)');
    expect(runs().single.started, isTrue);
    expect(viewModel.status, ProgramStatus.starting);
    expect(screen(), isNot(contains('van een vorige run')));
    await leave(tester);
  });

  testWidgets('shows what the program prints, and hands it what is typed', (tester) async {
    await open(tester);
    controller.run();
    final run = runs().single
      ..emit(const ReplStarted())
      ..emit(const ReplOutput('Hoe heet je? ', fromStderr: true));
    await tester.pump();

    viewModel.terminal.onOutput!('Sanne\r');

    expect(viewModel.status, ProgramStatus.running);
    expect(run.written, ['Sanne\n']);
    // Echoed by the page, since CPython does not echo.
    expect(screen(), contains('Hoe heet je? Sanne'));
    await leave(tester);
  });

  testWidgets('says when the program has finished, and then sends nothing on', (tester) async {
    await open(tester);
    controller.run();
    final run = runs().single
      ..emit(const ReplStarted())
      ..emit(const ReplExited(0));
    await tester.pump();

    viewModel.terminal.onOutput!('nog iets\r');

    expect(viewModel.status, ProgramStatus.idle);
    expect(run.disposed, isTrue);
    expect(run.written, isEmpty);
    expect(screen(), contains('Klaar (afsluitcode 0)'));
    await leave(tester);
  });

  testWidgets('Stop ends the run, and so does Ctrl-C', (tester) async {
    await open(tester);
    controller.run();
    runs().last.emit(const ReplStarted());
    await tester.pump();

    controller.stop();

    expect(runs().last.disposed, isTrue);
    expect(viewModel.status, ProgramStatus.idle);
    expect(screen(), contains('Gestopt'));

    controller.run();
    runs().last.emit(const ReplStarted());
    await tester.pump();
    viewModel.terminal.onOutput!('\x03');

    expect(runs().last.disposed, isTrue);
    expect(viewModel.status, ProgramStatus.idle);
    await leave(tester);
  });

  testWidgets('a second run throws the first away, and nothing of the first reaches the screen', (tester) async {
    await open(tester);
    controller.run();
    final first = runs().single;

    controller.run();
    first.emit(const ReplOutput('van de eerste', fromStderr: false));
    await tester.pump();

    expect(first.disposed, isTrue);
    expect(runs().last.started, isTrue);
    expect(screen(), isNot(contains('van de eerste')));
    await leave(tester);
  });

  testWidgets('a harness failure is not phrased as the student\'s mistake', (tester) async {
    await open(tester);
    controller.run();
    runs().single.emit(const ReplFailed('404 fetching python.wasm'));
    await tester.pump();

    expect(viewModel.status, ProgramStatus.idle);
    expect(screen(), contains('Dit lag niet aan je programma'));
    expect(screen(), contains('404 fetching python.wasm'));
    await leave(tester);
  });

  testWidgets('Run hands the keyboard to the terminal, where input() is answered', (tester) async {
    await open(tester);

    await tester.tap(find.text('Uitvoeren'));
    await tester.pump();

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'ProgramTerminal');
    expect(find.text('Stoppen'), findsOneWidget);
    await leave(tester);
  });

  testWidgets('names the interpreter in the strip over the editor', (tester) async {
    await open(tester);

    expect(find.text('Python 3.15.0'), findsOneWidget);
    await leave(tester);
  });

  testWidgets('a browser that cannot run one is told so, and offered no Run', (tester) async {
    await open(tester, supported: false);

    expect(viewModel.status, ProgramStatus.unavailable);
    expect(find.text('Dit werkt niet in deze browser'), findsOneWidget);
    expect(find.text('Uitvoeren'), findsNothing);
    expect(sessions.every((session) => !session.started), isTrue);
    await leave(tester);
  });

  group('the folder', () {
    testWidgets('every run starts with it', (tester) async {
      folder.put('python', 'cijfers.csv', utf8.encode('naam,cijfer\n'));
      await open(tester);

      controller.run();

      expect(runs().single.files.keys, ['cijfers.csv']);
      await leave(tester);
    });

    testWidgets('keeps what the program wrote, and shows it beside Run', (tester) async {
      folder.put('python', 'weg.csv', utf8.encode(''));
      await open(tester);
      controller.run();

      runs().single.emit(ReplFiles(changed: {'uit.csv': utf8.encode('a,b\r\n')}, removed: const ['weg.csv']));
      await tester.pump();

      expect(folder.filesOf('python').keys, ['uit.csv']);
      expect(find.text('uit.csv'), findsOneWidget);
      expect(find.text('weg.csv'), findsNothing);
      await leave(tester);
    });

    testWidgets('a run that was thrown away changes nothing in it', (tester) async {
      await open(tester);
      controller.run();
      final first = runs().single;
      controller.run();

      first.emit(ReplFiles(changed: {'oud.csv': utf8.encode('')}, removed: const []));
      await tester.pump();

      expect(folder.filesOf('python'), isEmpty);
      await leave(tester);
    });

    testWidgets('a file saved during a run reaches the run, and a rename takes the old name away', (tester) async {
      await open(tester);
      controller
        ..run()
        ..saveFile(name: 'a.csv', bytes: utf8.encode('1'))
        ..saveFile(name: 'b.csv', bytes: utf8.encode('2'), replacing: 'a.csv')
        ..deleteFile('b.csv');

      expect(runs().single.said.map((said) => (said.$1, said.$2 == null)), [
        ('a.csv', false),
        ('a.csv', true),
        ('b.csv', false),
        ('b.csv', true),
      ]);
      expect(folder.filesOf('python'), isEmpty);
      await leave(tester);
    });

    testWidgets('a file saved between runs waits in the folder for the next one', (tester) async {
      await open(tester);

      controller
        ..saveFile(name: 'a.csv', bytes: utf8.encode('1'))
        ..run();

      expect(runs().single.files.keys, ['a.csv']);
      expect(runs().single.said, isEmpty);
      await leave(tester);
    });
  });

  group('fits the window without scrolling', () {
    // A 13-inch MacBook Air's browser window, a small laptop's, the narrowest
    // that is still side by side, where the line beside Run has least room,
    // and a large monitor's.
    for (final size in const [Size(1470, 830), Size(1280, 650), Size(1024, 700), Size(2560, 1300)]) {
      testWidgets('at ${size.width.round()} × ${size.height.round()}', (tester) async {
        // A full folder, which has to fit on the line beside Run.
        for (var i = 1; i <= 12; i++) {
          folder.put('python', 'cijfers_van_klas_$i.csv', utf8.encode(''));
        }
        await open(tester, size: size);

        // An overflow is reported as an exception, which fails the test by itself.
        final editor = tester.getSize(find.byType(CodeEditorCard));
        final terminal = tester.getSize(find.byType(ReplTerminal));
        // About five lines of output, so an answer and the question before it show.
        expect(terminal.height, greaterThanOrEqualTo(140), reason: 'editor $editor, terminal $terminal');
        await leave(tester);
      });
    }
  });

  group('the draft', () {
    testWidgets('an earlier visit\'s program replaces the sample', (tester) async {
      drafts.keepPage('program.python', 'print("van de vorige keer")');

      await open(tester);

      expect(viewModel.code.text, 'print("van de vorige keer")');
      await leave(tester);
    });

    testWidgets('Run keeps the program at once', (tester) async {
      await open(tester);
      viewModel.code.text = 'print(3)';

      controller.run();
      await tester.pump();

      final reloaded = CodeDraftStore();
      await reloaded.load(const Course(lessons: []));
      expect(reloaded.pageCodeFor('program.python'), 'print(3)');
      await leave(tester);
    });

    testWidgets('going back to the sample forgets the draft', (tester) async {
      drafts.keepPage('program.python', 'print(4)');
      await open(tester);

      viewModel.code.text = ProgramScreenViewModelBase.sample;

      expect(drafts.pageCodeFor('program.python'), isNull);
      await leave(tester);
    });
  });
}
