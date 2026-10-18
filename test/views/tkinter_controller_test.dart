import 'dart:convert';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_code/services/editor_settings.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/progress/code_draft_store.dart';
import 'package:i_can_code/services/vm/vm_runtime.dart';
import 'package:i_can_code/views/base/build_context_accessor.dart';
import 'package:i_can_code/views/components/vm/vm_session_controller.dart';
import 'package:i_can_code/views/components/vm/vm_session_view_model.dart';
import 'package:i_can_code/views/tkinter_screen/tkinter_screen_controller.dart';
import 'package:i_can_code/views/tkinter_screen/tkinter_screen_view_model.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../support/fake_vm_runtime.dart';

const VmWindow _root = VmWindow(xid: 11, title: 'My window', mapped: true, isRoot: true, width: 300, height: 200);
const VmWindow _dialog = VmWindow(xid: 12, title: 'Question', mapped: true, transientFor: 11);

void main() {
  late List<FakeVmRuntime> runtimes;
  late CodeDraftStore drafts;
  late EditorSettings settings;
  late TkinterScreenViewModel viewModel;
  late TkinterScreenController controller;

  /// The page's machine half, where everything about the machine and its runs
  /// is kept.
  late VmSessionViewModel session;

  FakeVmRuntime runtime() => runtimes.last;

  /// A page opened on a machine that is [supported], in a build that ships the
  /// image unless [imageIncluded] says otherwise, and the runtime it made.
  void open({bool supported = true, bool imageIncluded = true}) {
    final accessor = BuildContextAccessor();
    viewModel = TkinterScreenViewModel(contextAccessor: accessor, subjectSlug: 'learn-python');
    session = viewModel.machine;
    controller = TkinterScreenController(
      viewModel: viewModel,
      contextAccessor: accessor,
      imageIncluded: imageIncluded,
      drafts: drafts,
      settings: settings,
      createRuntime: () {
        final created = FakeVmRuntime(supported: supported);
        runtimes.add(created);
        return created;
      },
    );
  }

  /// Opened, and the machine ready.
  Future<void> openReady(WidgetTester tester) async {
    open();
    runtime().ready();
    await tester.pump();
  }

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    runtimes = [];
    drafts = CodeDraftStore();
    settings = EditorSettings();
  });

  /// A test of the page, which leaves it at the end: a timer still pending
  /// then (the draft's, the output's) fails a widget test.
  void testPage(String description, Future<void> Function(WidgetTester tester) body) {
    testWidgets(description, (tester) async {
      await body(tester);
      // Idempotent, so a test that already left the page is not a problem.
      controller.dispose();
      await tester.pump();
    });
  }

  group('the machine', () {
    testPage('opening the page starts the download, and only that', (tester) async {
      open();

      expect(runtime().loads, 1);
      expect(session.machine, TkinterMachine.loading);
      expect(runtime().runs, isEmpty);
    });

    testPage('progress and ready reach the screen, with what the machine calls itself', (tester) async {
      open();
      runtime().emit(const VmLoadProgress(5000000, 20000000));
      await tester.pump();

      expect(session.loadProgress?.loaded, 5000000);
      expect(session.loadProgress?.total, 20000000);

      runtime().ready();
      await tester.pump();

      expect(session.machine, TkinterMachine.ready);
      expect(session.interpreterLabel, 'Python 3.12.12 · Tk 8.6.16');
    });

    testPage('a browser that cannot host it downloads nothing and runs nothing', (tester) async {
      open(supported: false);

      expect(session.machine, TkinterMachine.unavailable);
      expect(runtime().loads, 0);
      expect(session.canRun, isFalse);

      controller.run();
      expect(runtime().runs, isEmpty);
    });

    testPage('a build without the image downloads nothing, and says so rather than blame the browser', (tester) async {
      open(imageIncluded: false);

      expect(session.machine, TkinterMachine.notIncluded);
      expect(runtime().loads, 0, reason: 'every download would be a 404');
      expect(session.canRun, isFalse);

      controller.run();
      expect(runtime().runs, isEmpty);
    });

    testPage('Retry does not bring back the end of a run the failed download refused', (tester) async {
      // Run pressed during the download, which then fails: the host ends the
      // waiting run as broken before it reports the failure (vm_run.js #fail).
      open();
      controller.run();
      runtime()
        ..end(runtime().lastRunId, const VmExit(reason: VmEndReason.broken, message: 'HTTP 404'))
        ..emit(const VmFailed(VmFailure.network, 'HTTP 404'));
      await tester.pump();
      expect(session.machine, TkinterMachine.failed);
      expect(session.notices, isEmpty, reason: 'the failure card says it');

      controller.machine.retry();
      runtime().ready();
      await tester.pump();

      expect(session.machine, TkinterMachine.ready);
      expect(session.notices, isEmpty, reason: 'nothing has run on the new machine');
    });

    testPage('Retry does not bring back a hint about a run on the machine that failed', (tester) async {
      await openReady(tester);
      controller.run();
      final id = runtime().lastRunId;
      runtime()
        ..emit(VmRunHint(id, VmHint.tkNoMainloop))
        ..end(id, const VmExit(reason: VmEndReason.exit, code: 0));
      await tester.pump();
      expect(session.notices, [TkinterNotice.noMainloop]);

      // The park after the run failed.
      runtime().emit(const VmFailed(VmFailure.broken, 'The restore failed.'));
      await tester.pump();
      controller.machine.retry();
      runtime().ready();
      await tester.pump();

      expect(session.notices, isEmpty);
      expect(session.hints, isEmpty);
    });

    testPage('a byte count that arrives after the failure leaves the failure card and its Retry', (tester) async {
      // A state that 404s at once while the wasm still streams: the page stayed
      // on "2,1 van 22,7 MB" with no card and no way to try again.
      open();
      runtime()
        ..emit(const VmLoadProgress(1000000, 22659783))
        ..emit(const VmFailed(VmFailure.network, 'HTTP 404'))
        ..emit(const VmLoadProgress(2097152, 22659783));
      await tester.pump();

      expect(session.machine, TkinterMachine.failed);
      expect(session.failure, VmFailure.network);
      expect(session.loadProgress?.loaded, 1000000);

      controller.machine.retry();
      runtime().emit(const VmLoadProgress(3000000, 22659783));
      await tester.pump();

      expect(session.machine, TkinterMachine.loading, reason: 'Retry is the one way out of failed');
      expect(session.loadProgress?.loaded, 3000000);
    });

    testPage('a failed machine refuses runs, and Retry builds a new one', (tester) async {
      await openReady(tester);
      runtime().emit(const VmFailed(VmFailure.unresponsive, 'No HELLO to READY, twice in a row.'));
      await tester.pump();

      expect(session.machine, TkinterMachine.failed);
      expect(session.failure, VmFailure.unresponsive);
      expect(session.failureMessage, contains('HELLO'));

      controller.run();
      expect(runtime().runs, isEmpty, reason: 'a failed machine cannot take a program');

      final failed = runtime();
      controller.machine.retry();

      expect(failed.disposed, isTrue);
      expect(runtimes, hasLength(2));
      expect(runtime().loads, 1);
      expect(session.machine, TkinterMachine.loading);
    });

    testPage('leaving the page frees the machine', (tester) async {
      await openReady(tester);
      controller
        ..run()
        ..dispose();

      expect(runtime().disposed, isTrue);
    });
  });

  group('a run', () {
    testPage('sends what is in the editor as main.py', (tester) async {
      await openReady(tester);
      session.code.text = 'import tkinter\nprint("hoi")\n';

      controller.run();

      expect(runtime().runs.single.program.entry, 'main.py');
      expect(runtime().lastSource, 'import tkinter\nprint("hoi")\n');
      expect(session.running, isTrue);
    });

    testPage('pressed before the machine is ready is handed over at once, to wait for it', (tester) async {
      open();

      controller.run();

      // The runtime queues it; the screen does not hold it back.
      expect(runtime().runs, hasLength(1));
      expect(session.running, isTrue);
      expect(session.machine, TkinterMachine.loading);
    });

    testPage('output reaches the screen a few times a second, and all of it at the end', (tester) async {
      await openReady(tester);
      controller.run();
      final id = runtime().lastRunId;

      runtime()
        ..emit(VmOutput(id, 'een\n', fromStderr: false))
        ..emit(VmOutput(id, 'twee\n', fromStderr: false));
      await tester.pump();
      expect(session.output, isEmpty, reason: 'batched, not laid out on every batch');

      await tester.pump(VmSessionController.outputInterval);
      expect(session.output, 'een\ntwee\n');

      runtime()
        ..emit(VmOutput(id, 'drie\n', fromStderr: false))
        ..end(id, const VmExit(reason: VmEndReason.exit, code: 0));
      await tester.pump();

      expect(session.output, 'een\ntwee\ndrie\n', reason: 'the end flushes what is left');
      expect(session.running, isFalse);
      expect(session.notices, isEmpty);
    });

    testPage('a new run supersedes the old, and nothing of the old lands after it', (tester) async {
      await openReady(tester);
      controller.run();
      final first = runtime().lastRunId;
      runtime().emit(VmOutput(first, 'oud\n', fromStderr: false));
      await tester.pump(VmSessionController.outputInterval);

      controller.run();
      final second = runtime().lastRunId;
      runtime()
        // Late frames of the first run, and its end as the fake host sent it.
        ..emit(VmOutput(first, 'te laat\n', fromStderr: false))
        ..emit(const VmWindows(1, [_root]))
        ..emit(VmOutput(second, 'nieuw\n', fromStderr: false));
      await tester.pump(VmSessionController.outputInterval);

      expect(second, isNot(first));
      expect(session.output, 'nieuw\n');
      expect(session.windows, isEmpty);
      expect(session.running, isTrue, reason: 'the first run ending is not this one ending');
      expect(session.exit, isNull);
    });

    testPage('Stop turns the button back at once, and a stop is no verdict', (tester) async {
      await openReady(tester);
      controller.run();
      final id = runtime().lastRunId;
      runtime().emit(VmOutput(id, 'bezig\n', fromStderr: false));
      await tester.pump();

      final stopping = controller.machine.stop();
      expect(session.running, isFalse, reason: 'the page never waits on the guest');
      await stopping;
      await tester.pump();

      expect(runtime().stops, 1);
      expect(session.exit?.stopped, isTrue);
      expect(session.notices, isEmpty);
      expect(session.output, 'bezig\n', reason: 'what it printed still happened');
    });

    testPage('Stop with nothing running asks nothing of the machine', (tester) async {
      await openReady(tester);

      await controller.machine.stop();

      expect(runtime().stops, 0);
    });
  });

  group('windows', () {
    testPage('the dialog is named for the main window, and a strip closes the window it names', (tester) async {
      await openReady(tester);
      controller.run();
      runtime().emit(VmWindows(runtime().lastRunId, const [_root, _dialog]));
      await tester.pump();

      expect(session.framedWindow?.xid, 11);
      expect(session.labelledWindows.map((window) => window.xid), [12]);

      controller.machine.closeWindowById(12);
      expect(runtime().closedWindows, [12]);
    });

    testPage('a withdrawn main window hands the frame to the dialog', (tester) async {
      await openReady(tester);
      controller.run();
      runtime().emit(
        VmWindows(runtime().lastRunId, const [
          VmWindow(xid: 11, title: '', mapped: false, isRoot: true),
          _dialog,
        ]),
      );
      await tester.pump();

      expect(session.framedWindow?.title, 'Question');
    });

    testPage('the windows go with the run', (tester) async {
      await openReady(tester);
      controller.run();
      final id = runtime().lastRunId;
      runtime()
        ..emit(VmWindows(id, const [_root]))
        ..end(id, const VmExit(reason: VmEndReason.exit, code: 0));
      await tester.pump();

      expect(session.windows, isEmpty);
      expect(session.framedWindow, isNull);
      expect(session.labelledWindows, isEmpty, reason: 'nothing left to close');
    });
  });

  group('windowRegion', () {
    const root = VmWindow(xid: 1, title: 'Hoofd', mapped: true, isRoot: true, width: 237, height: 113);
    const cases = <String, (List<VmWindow>, Rect?)>{
      'no windows': ([], null),
      'one window, at the +0+0 Tk opens it at': ([root], Rect.fromLTWH(0, 0, 237, 113)),
      'a dialog over the main window holds both': (
        [root, VmWindow(xid: 2, title: 'Question', mapped: true, transientFor: 1, x: 10, y: 40, width: 300, height: 120)],
        Rect.fromLTWH(0, 0, 310, 160),
      ),
      'a window partly off the screen, only the part on it': (
        [VmWindow(xid: 1, title: '', mapped: true, x: -50, y: 500, width: 200, height: 200)],
        Rect.fromLTWH(0, 500, 150, 100),
      ),
      'a canvas larger than the screen, the whole screen': (
        [VmWindow(xid: 1, title: '', mapped: true, width: 1924, height: 1084)],
        Rect.fromLTWH(0, 0, 800, 600),
      ),
      'a withdrawn main window with a dialog, the dialog alone': (
        [
          VmWindow(xid: 1, title: 'Hoofd', mapped: false, isRoot: true, width: 237, height: 113),
          VmWindow(xid: 2, title: 'Question', mapped: true, transientFor: 1, x: 250, y: 240, width: 300, height: 120),
        ],
        Rect.fromLTWH(250, 240, 300, 120),
      ),
      'windows that show nothing: withdrawn, off the screen, or of no size': (
        [
          VmWindow(xid: 1, title: '', mapped: false, width: 100, height: 100),
          VmWindow(xid: 2, title: '', mapped: true, x: 900, y: 10, width: 100, height: 100),
          VmWindow(xid: 3, title: '', mapped: true, x: 10, y: 10),
        ],
        null,
      ),
    };

    for (final MapEntry(key: description, value: (windows, region)) in cases.entries) {
      test(description, () => expect(windowRegion(windows), region));
    }

    testPage('the page follows the run\'s windows, and forgets them with it', (tester) async {
      await openReady(tester);
      expect(session.shownRegion, isNull);

      controller.run();
      final id = runtime().lastRunId;
      runtime().emit(VmWindows(id, const [root]));
      await tester.pump();
      expect(session.shownRegion, const Rect.fromLTWH(0, 0, 237, 113));

      runtime().end(id, const VmExit(reason: VmEndReason.exit, code: 0));
      await tester.pump();
      expect(session.shownRegion, isNull);
    });
  });

  group('what the page says about a run', () {
    Future<List<TkinterNotice>> endWith(
      WidgetTester tester,
      VmExit exit, {
      String output = '',
      bool noMainloop = false,
    }) async {
      await openReady(tester);
      controller.run();
      final id = runtime().lastRunId;
      if (output.isNotEmpty) runtime().emit(VmOutput(id, output, fromStderr: true));
      if (noMainloop) runtime().emit(VmRunHint(id, VmHint.tkNoMainloop));
      runtime().end(id, exit);
      await tester.pump();
      return session.notices;
    }

    testPage('a program without mainloop() is told so', (tester) async {
      final notices = await endWith(tester, const VmExit(reason: VmEndReason.exit, code: 0), noMainloop: true);

      expect(notices, [TkinterNotice.noMainloop]);
    });

    testPage('a traceback is introduced as the program stopping with an error', (tester) async {
      final notices = await endWith(
        tester,
        const VmExit(reason: VmEndReason.exit, code: 1),
        output: 'Traceback (most recent call last):\nNameError: name \'x\' is not defined\n',
      );

      expect(notices, [TkinterNotice.crashed]);
      expect(notices.single.aboutTheProgram, isTrue);
    });

    testPage('input() gets advice about an Entry instead of "it crashed"', (tester) async {
      final notices = await endWith(
        tester,
        const VmExit(reason: VmEndReason.exit, code: 1),
        output: 'Traceback (most recent call last):\n  File "/run/icc/work/main.py", line 1\nEOFError: EOF when reading a line\n',
      );

      expect(notices, [TkinterNotice.noInput]);
    });

    testPage('a window or canvas the X server cannot hold is a limit of the machine, not a crash', (tester) async {
      // Printed by a 1920 × 1080 Canvas on the 96 MiB image, where Xorg could
      // grow its heap by 8 MiB. At 128 MiB, where it may grow by 16, a
      // 3000 × 3000 one ends the same way.
      final notices = await endWith(
        tester,
        const VmExit(reason: VmEndReason.exit, code: 1),
        output:
            'X Error of failed request:  BadAlloc (insufficient resources for operation)\n'
            '  Major opcode of failed request:  53 (X_CreatePixmap)\n'
            '  Serial number of failed request:  1972\n'
            '  Current serial number in output stream:  1975\n',
      );

      expect(notices, [TkinterNotice.tooLarge]);
      expect(notices.single.aboutTheProgram, isFalse);
    });

    testPage('running out of memory is its own sentence', (tester) async {
      final notices = await endWith(tester, const VmExit(reason: VmEndReason.outOfMemory, signal: 9));

      expect(notices, [TkinterNotice.outOfMemory]);
    });

    testPage('a machine failing never reads as the student\'s mistake', (tester) async {
      for (final (reason, notice) in [
        (VmEndReason.broken, TkinterNotice.harnessBroken),
        (VmEndReason.fetch, TkinterNotice.harnessFetch),
        (VmEndReason.unresponsive, TkinterNotice.harnessUnresponsive),
      ]) {
        // A traceback-looking line in the output changes nothing: the machine
        // failed first.
        final notices = await endWith(tester, VmExit(reason: reason, message: 'x'), output: 'EOFError: EOF when reading a line');
        expect(notices, [notice], reason: '$reason');
        expect(notices.single.aboutTheProgram, isFalse, reason: '$reason');
        controller.dispose();
      }
    });

    testPage('closing the window is how a program ends, not an error', (tester) async {
      final notices = await endWith(tester, const VmExit(reason: VmEndReason.closed, signal: 9));

      expect(notices, isEmpty);
    });

    testPage('output the host cut off is marked incomplete', (tester) async {
      await endWith(tester, const VmExit(reason: VmEndReason.exit, code: 0, truncated: true), output: 'veel\n');

      expect(session.outputIncomplete, isTrue);
    });

    testPage('only the end of a long output is shown', (tester) async {
      final long = List.filled(VmSessionViewModelBase.outputShown + 10, 'x').join();
      await endWith(tester, const VmExit(reason: VmEndReason.exit, code: 0), output: long);

      expect(session.visibleOutput, hasLength(VmSessionViewModelBase.outputShown));
      expect(session.outputIncomplete, isTrue);
    });
  });

  group('the setup', () {
    testPage('goes beside the program on every run, from the settings', (tester) async {
      await settings.setTkinterSetup('import turtle\n');
      await openReady(tester);

      controller.run();
      final files = runtime().runs.last.program.files;

      expect(runtime().runs.last.program.entry, 'main.py');
      expect(utf8.decode(files[vmSetupFile]!), 'import turtle\n');
    });

    testPage('a blank one sends no file', (tester) async {
      await settings.setTkinterSetup('  \n');
      await openReady(tester);

      controller.run();

      expect(runtime().runs.last.program.files.keys, ['main.py']);
    });

    testPage('a change while the page is open counts from the next run', (tester) async {
      await openReady(tester);
      await settings.setTkinterSetup('print("later")\n');

      controller.run();

      expect(utf8.decode(runtime().runs.last.program.files[vmSetupFile]!), 'print("later")\n');
    });
  });

  group('the draft', () {
    /// What a reload finds in storage, which is what a discarded tab gets.
    Future<String?> stored() async {
      final reloaded = CodeDraftStore();
      await reloaded.load(const Course(lessons: []));
      return reloaded.pageCodeFor('tkinter.python');
    }

    testPage('an earlier visit\'s program replaces the sample', (tester) async {
      drafts.keepPage('tkinter.python', 'print("van de vorige keer")');

      open();

      expect(session.code.text, 'print("van de vorige keer")');
    });

    testPage('what is typed is kept after a pause, and on the way out', (tester) async {
      open();

      session.code.text = 'print(1)';
      await tester.pump(CodeDraftStoreBase.writeDelay);
      expect(await stored(), 'print(1)');

      session.code.text = 'print(2)';
      controller.dispose();
      await tester.pump();
      expect(await stored(), 'print(2)');
    });

    testPage('Run keeps the program at once', (tester) async {
      await openReady(tester);

      session.code.text = 'print(3)';
      controller.run();
      await tester.pump();

      expect(await stored(), 'print(3)');
    });

    testPage('going back to the sample forgets the draft', (tester) async {
      drafts.keepPage('tkinter.python', 'print(4)');
      open();

      session.code.text = TkinterScreenViewModelBase.sample;

      expect(drafts.pageCodeFor('tkinter.python'), isNull);
    });
  });

  // What a project on the machine waits for before "Het werkt!". The page
  // asks for none of it, so this drives the session on its own.
  group('the first window a run shows', () {
    testWidgets('is reported once per run, only once it is mapped, and never for a run that was superseded', (
      tester,
    ) async {
      final accessor = BuildContextAccessor();
      final sessionModel = VmSessionViewModel(contextAccessor: accessor, subjectSlug: 'learn-python', program: '');
      late FakeVmRuntime fake;
      var shown = 0;
      final sessionController = VmSessionController(
        viewModel: sessionModel,
        contextAccessor: accessor,
        onWindowShown: () => shown++,
        createRuntime: () => fake = FakeVmRuntime(),
        settings: settings,
        imageIncluded: true,
      );
      addTearDown(() {
        sessionController.dispose();
        sessionModel.dispose();
      });
      fake.ready();
      await tester.pump();

      sessionController.run();
      final first = fake.lastRunId;
      fake.emit(VmWindows(first, const [VmWindow(xid: 11, title: '', mapped: false, isRoot: true)]));
      await tester.pump();
      expect(shown, 0, reason: 'a withdrawn window shows nothing');

      fake
        ..emit(VmWindows(first, const [_root]))
        ..emit(VmWindows(first, const [_root, _dialog]));
      await tester.pump();
      expect(shown, 1);

      sessionController.run();
      fake.emit(VmWindows(first, const [_root]));
      await tester.pump();
      expect(shown, 1, reason: 'the window of the run before is not this one\'s');

      fake.emit(VmWindows(fake.lastRunId, const [_root]));
      await tester.pump();
      expect(shown, 2, reason: 'every run shows its own');
    });
  });

  // The host keeps one machine per tab, so a screen opened over another takes
  // the machine from it: a project that opens a task's requirement does.
  group('the one machine', () {
    /// A session of a screen of its own, and every runtime it makes.
    (VmSessionController, VmSessionViewModel, List<FakeVmRuntime>) openSession() {
      final accessor = BuildContextAccessor();
      final made = <FakeVmRuntime>[];
      final sessionModel = VmSessionViewModel(contextAccessor: accessor, subjectSlug: 'learn-python', program: '');
      final sessionController = VmSessionController(
        viewModel: sessionModel,
        contextAccessor: accessor,
        createRuntime: () {
          final created = FakeVmRuntime();
          made.add(created);
          return created;
        },
        settings: settings,
        imageIncluded: true,
      );
      addTearDown(() {
        sessionController.dispose();
        sessionModel.dispose();
      });
      return (sessionController, sessionModel, made);
    }

    /// What the host tells a session once a newer one's openVm() destroyed its machine.
    const replaced = VmFailed(VmFailure.replaced, 'A newer openVm() on this page took over the machine.');

    testWidgets('comes back to the screen under one that leaves, as a new machine', (tester) async {
      final (_, under, made) = openSession();
      made.single.ready();
      await tester.pump();

      final (over, _, _) = openSession();
      made.single.emit(replaced);
      await tester.pump();
      expect(under.machine, TkinterMachine.failed);

      over.dispose();

      expect(made, hasLength(2), reason: 'a new machine, the way Retry builds one');
      expect(made.first.disposed, isTrue);
      expect(made.last.loads, 1);
      expect(under.machine, TkinterMachine.loading);
    });

    testWidgets('is not built again for a machine that failed of its own accord', (tester) async {
      final (_, under, made) = openSession();
      made.single.emit(const VmFailed(VmFailure.network, 'HTTP 404'));
      await tester.pump();

      final (over, _, _) = openSession();
      over.dispose();

      expect(made, hasLength(1), reason: 'that failure keeps its card and its Retry');
      expect(under.failure, VmFailure.network);
    });

    testWidgets('stays with the newest screen while an older one goes', (tester) async {
      // A screen that replaces another is built before the old one is disposed.
      final (older, _, olderMade) = openSession();
      final (_, newer, newerMade) = openSession();
      newerMade.single.ready();
      olderMade.single.emit(replaced);
      await tester.pump();

      older.dispose();
      await tester.pump();

      expect(newerMade, hasLength(1));
      expect(newer.machine, TkinterMachine.ready);
    });
  });
}
