import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:get_it/get_it.dart';
import 'package:i_can_code/l10n/generated/app_localizations.dart';
import 'package:i_can_code/services/editor_settings.dart';
import 'package:i_can_code/services/progress/code_draft_store.dart';
import 'package:i_can_code/services/vm/vm_runtime.dart';
import 'package:i_can_code/theme/theme.dart';
import 'package:i_can_code/views/base/build_context_accessor.dart';
import 'package:i_can_code/views/components/code_editor_card.dart';
import 'package:i_can_code/views/components/notice_card.dart';
import 'package:i_can_code/views/components/output_card.dart';
import 'package:i_can_code/views/tkinter_screen/components/no_window_panel.dart';
import 'package:i_can_code/views/tkinter_screen/components/program_dialog.dart';
import 'package:i_can_code/views/tkinter_screen/components/run_notice.dart';
import 'package:i_can_code/views/tkinter_screen/components/vm_display.dart';
import 'package:i_can_code/views/tkinter_screen/components/vm_load_panel.dart';
import 'package:i_can_code/views/tkinter_screen/components/window_frame.dart';
import 'package:i_can_code/views/tkinter_screen/components/window_strips.dart';
import 'package:i_can_code/views/tkinter_screen/tkinter_screen.dart';
import 'package:i_can_code/views/tkinter_screen/tkinter_screen_controller.dart';
import 'package:i_can_code/views/tkinter_screen/tkinter_screen_view.dart';
import 'package:i_can_code/views/tkinter_screen/tkinter_screen_view_model.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../support/fake_vm_runtime.dart';

/// Stands in for the platform view, which `flutter test` cannot build. It
/// reports a view id the way the engine does, a frame after it is created.
class _FakeView extends StatefulWidget {

  static const int viewId = 7;

  final ValueChanged<int> onCreated;

  const _FakeView({required this.onCreated});

  @override
  State<_FakeView> createState() => _FakeViewState();

}

class _FakeViewState extends State<_FakeView> {

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onCreated(_FakeView.viewId));
  }

  @override
  Widget build(BuildContext context) => const ColoredBox(color: Color(0xFF000000), child: SizedBox.expand());

}

Widget _fakeView(BuildContext context, VmDisplayBinding binding, ValueChanged<int> onCreated) =>
    _FakeView(onCreated: onCreated);

/// What the VmDisplay tests show: the top left of the screen, the size of the
/// box they lay the display out in.
const Rect _region = Rect.fromLTWH(0, 0, 400, 300);

/// The starter program's window, about the size Tk gives it.
const VmWindow _small = VmWindow(xid: 11, title: 'My first window', mapped: true, isRoot: true, width: 237, height: 113);

const VmWindow _fullScreen = VmWindow(xid: 11, title: 'Full screen', mapped: true, isRoot: true, width: 800, height: 600);

/// The page, with a machine the test drives and the fake platform view, in a
/// build that ships the image.
class _TestTkinterScreen extends TkinterScreen {

  final VmRuntime Function() createRuntime;

  const _TestTkinterScreen(this.createRuntime) : super(subjectSlug: 'learn-python');

  @override
  TkinterScreenController createController({
    required TkinterScreenViewModel viewModel,
    required BuildContextAccessor contextAccessor,
  }) => TkinterScreenController(
    viewModel: viewModel,
    contextAccessor: contextAccessor,
    createRuntime: createRuntime,
    imageIncluded: true,
    drafts: CodeDraftStore(),
    settings: EditorSettings(),
  );

  @override
  TkinterScreenView createView({
    required TkinterScreenController controller,
    required TkinterScreenViewModel viewModel,
    required BuildContextAccessor contextAccessor,
  }) => TkinterScreenView(
    viewModel: viewModel,
    controller: controller,
    contextAccessor: contextAccessor,
    displayViewBuilder: _fakeView,
  );

}

/// What every widget here needs: the theme, Dutch, a size and an [Overlay],
/// which the app has above every screen (see `OverlayHost`).
Widget _host(Widget child, {Size size = const Size(1400, 1000), Locale locale = const Locale('nl')}) => FTheme(
  data: buildAppTheme(),
  child: Localizations(
    locale: locale,
    delegates: AppLocalizations.localizationsDelegates,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: MediaQueryData(size: size),
        child: Overlay(initialEntries: [OverlayEntry(builder: (_) => child)]),
      ),
    ),
  ),
);

/// Lets events from the machine reach the screen. Two frames: an Observer
/// invalidated in the middle of a frame waits for its end before it rebuilds
/// (flutter_mobx's `_markNeedsBuildImmediatelyOrDelayed`).
Future<void> _deliver(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

/// re_editor starts its caret from a 100 ms timer that nothing cancels, and a
/// test that ends before it fails.
Future<void> _settleEditor(WidgetTester tester) => tester.pump(const Duration(milliseconds: 150));

void _useWindow(WidgetTester tester, Size size) {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  });

  group('displayScale', () {
    const guest = Size(800, 600);

    test('is 1 wherever the screen fits, and never more', () {
      expect(displayScale(available: const Size(1000, 800), guest: guest, devicePixelRatio: 1), 1);
      expect(displayScale(available: const Size(3000, 3000), guest: guest, devicePixelRatio: 2), 1);
    });

    test('fits the tighter side', () {
      expect(displayScale(available: const Size(2000, 300), guest: guest, devicePixelRatio: 1), 0.5);
    });

    test('takes a scale that lands on whole device pixels when that costs little', () {
      // 680 wide is 0.85; on a 1.25 display 0.8 is one device pixel per guest
      // pixel, 640 × 480, and sharp.
      expect(displayScale(available: const Size(680, 1000), guest: guest, devicePixelRatio: 1.25), 0.8);
    });

    test('does not halve the screen to make it sharp', () {
      // On a 2× display the sharp scale below 0.83 is 0.5, far too small.
      final scale = displayScale(available: const Size(664, 1000), guest: guest, devicePixelRatio: 2);
      expect(scale, closeTo(0.83, 0.001));
    });

    test('is 0 with no room at all', () {
      expect(displayScale(available: const Size(-10, 500), guest: guest, devicePixelRatio: 1), 0);
    });
  });

  group('WindowFrame', () {
    /// What the frame last handed its builder.
    late ({Size box, double scale}) built;

    /// The frame in [room]. Its hint follows [hint], because the host builds
    /// only the child it was first given.
    Future<void> frame(
      WidgetTester tester, {
      required Size room,
      Size? region,
      String title = 'My window',
      VoidCallback? onClose,
      ValueNotifier<String?>? hint,
    }) async {
      _useWindow(tester, const Size(2400, 2000));
      await tester.pumpWidget(
        _host(
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox.fromSize(
              size: room,
              child: ValueListenableBuilder<String?>(
                valueListenable: hint ?? ValueNotifier(null),
                builder: (context, hint, _) => WindowFrame(
                  title: title,
                  closeLabel: 'Venster sluiten',
                  region: region,
                  onClose: onClose,
                  hint: hint,
                  builder: (context, box, scale) {
                    built = (box: box, scale: scale);
                    return const ColoredBox(key: Key('screen'), color: Color(0xFF000000));
                  },
                ),
              ),
            ),
          ),
          size: const Size(2400, 2000),
        ),
      );
    }

    final screen = find.byKey(const Key('screen'));
    // The frame's own card: the first box it decorates.
    final card = find.descendant(of: find.byType(WindowFrame), matching: find.byType(DecoratedBox)).first;

    Size chrome(Size inside) =>
        Size(inside.width + 2 * WindowFrame.bezel, inside.height + WindowFrame.stripHeight + WindowFrame.bezel);

    testWidgets('hugs a window at its real size where there is room, and never draws it larger', (tester) async {
      await frame(tester, room: const Size(2000, 1600), region: const Size(500, 260));

      expect(tester.getSize(screen), const Size(500, 260));
      expect(built, (box: const Size(500, 260), scale: 1.0));
      expect(tester.getSize(card), chrome(const Size(500, 260)));
    });

    testWidgets('keeps a narrow window centred in a frame wide enough for its strip', (tester) async {
      await frame(tester, room: const Size(2000, 1600), region: const Size(120, 80));

      expect(tester.getSize(screen), const Size(120, 80), reason: 'still at its real size');
      expect(tester.getSize(card), chrome(const Size(WindowFrame.minWidth, 80)));
      final left = tester.getTopLeft(screen).dx - tester.getTopLeft(card).dx - WindowFrame.bezel;
      expect(left, (WindowFrame.minWidth - 120) / 2);
    });

    testWidgets('shrinks a region too wide for the room, keeping its shape', (tester) async {
      await frame(tester, room: Size(420 + 2 * WindowFrame.bezel, 2000), region: vmScreenSize);

      expect(tester.getSize(screen), const Size(420, 315));
      expect(built.scale, 0.525);
      expect(tester.getSize(card), chrome(const Size(420, 315)));
    });

    testWidgets('shrinks a region too tall for the room by its height', (tester) async {
      await frame(
        tester,
        room: const Size(2000, 300 + WindowFrame.stripHeight + WindowFrame.bezel),
        region: vmScreenSize,
      );

      expect(tester.getSize(screen), const Size(400, 300));
      expect(built.scale, 0.5);
    });

    testWidgets('with no window takes its empty size', (tester) async {
      await frame(tester, room: const Size(2000, 1600));

      expect(tester.getSize(screen), WindowFrame.emptySize);
      expect(built, (box: WindowFrame.emptySize, scale: 1.0));
    });

    testWidgets('with no window and little room takes as much of its empty size as fits', (tester) async {
      await frame(tester, room: const Size(300, 1600));

      expect(tester.getSize(screen), Size(300 - 2 * WindowFrame.bezel, WindowFrame.emptySize.height));
      expect(tester.getSize(card).width, 300);
    });

    testWidgets('names the window, and the close button asks it to close', (tester) async {
      var closed = 0;
      await frame(tester, room: const Size(900, 700), region: const Size(300, 200), onClose: () => closed++);

      expect(find.text('My window'), findsOneWidget);
      await tester.tap(find.byIcon(FLucideIcons.x));
      await tester.pumpAndSettle();
      expect(closed, 1);
    });

    testWidgets('states the way out in full, before the title, without changing size', (tester) async {
      const hint = 'Esc, dan Tab: verlaten';
      const title = 'Een venster met een titel die veel te lang is voor de balk erboven';
      final shown = ValueNotifier<String?>(null);
      addTearDown(shown.dispose);
      await frame(tester, room: const Size(2000, 1600), region: const Size(600, 200), title: title, hint: shown);
      final before = tester.getSize(card);

      shown.value = hint;
      await tester.pump();

      expect(tester.getSize(card), before, reason: 'the edge that says so is a colour, not a size');
      expect(tester.renderObject<RenderParagraph>(find.text(hint)).didExceedMaxLines, isFalse);
      expect(tester.renderObject<RenderParagraph>(find.text(title)).didExceedMaxLines, isTrue);
    });
  });

  group('VmLoadPanel', () {
    const total = 20373228;

    /// The panel, fed through a notifier: the host's Overlay keeps the child it
    /// was first given, so a second pumpWidget would change nothing below it.
    Future<ValueNotifier<VmLoadProgress?>> panel(WidgetTester tester, [VmLoadProgress? first, Locale locale = const Locale('nl')]) async {
      final progress = ValueNotifier<VmLoadProgress?>(first);
      addTearDown(progress.dispose);
      await tester.pumpWidget(
        _host(
          Center(
            child: SizedBox(
              width: 600,
              height: 450,
              child: ValueListenableBuilder(
                valueListenable: progress,
                builder: (context, value, _) => VmLoadPanel(progress: value),
              ),
            ),
          ),
          locale: locale,
        ),
      );
      return progress;
    }

    Future<void> show(WidgetTester tester, ValueNotifier<VmLoadProgress?> progress, VmLoadProgress value) async {
      progress.value = value;
      await tester.pump();
    }

    Visibility bytesLine(WidgetTester tester) => tester.widget<Visibility>(
      find.ancestor(of: find.textContaining(RegExp(r'\d (van|of) \d')), matching: find.byType(Visibility)).first,
    );

    /// The note on show, not the invisible one that holds its room.
    String? note(WidgetTester tester) {
      final live = find.descendant(
        of: find.byType(VmLoadPanel),
        matching: find.byWidgetPredicate((widget) => widget is Semantics && (widget.properties.liveRegion ?? false)),
      );
      if (live.evaluate().isEmpty) return null;
      return tester.widget<Text>(find.descendant(of: live, matching: find.byType(Text))).data;
    }

    Size column(WidgetTester tester) =>
        tester.getSize(find.descendant(of: find.byType(VmLoadPanel), matching: find.byType(Column)).first);

    testWidgets('says nothing about bytes before it knows the total', (tester) async {
      await panel(tester);

      expect(find.text('De machine wordt gedownload'), findsOneWidget);
      expect(bytesLine(tester).visible, isFalse);
      expect(note(tester), isNull);
    });

    testWidgets('says how much of how much, in megabytes the way the locale writes them', (tester) async {
      await panel(tester, const VmLoadProgress(5000000, total));

      expect(bytesLine(tester).visible, isTrue);
      expect(find.text('5,0 van 20,4 MB'), findsOneWidget);
    });

    testWidgets('adds the speed and the time left once the download has measured them', (tester) async {
      final progress = await panel(
        tester,
        const VmLoadProgress(5000000, total, bytesPerSecond: 2300000, remaining: Duration(seconds: 7)),
      );
      expect(find.text('5,0 van 20,4 MB'), findsOneWidget);
      expect(find.text('2,3 MB/s · nog ongeveer 10 seconden'), findsOneWidget);

      await show(tester, progress, const VmLoadProgress(1000000, total, bytesPerSecond: 180000, remaining: Duration(seconds: 150)));
      expect(find.text('180 kB/s · nog ongeveer 3 minuten'), findsOneWidget);

      await show(tester, progress, const VmLoadProgress(1000000, total, bytesPerSecond: 300000, remaining: Duration(seconds: 62)));
      expect(find.textContaining('nog ongeveer een minuut'), findsOneWidget);

      await show(tester, progress, const VmLoadProgress(19000000, total, bytesPerSecond: 2300000, remaining: Duration(seconds: 3)));
      expect(find.textContaining('bijna klaar'), findsOneWidget);
    });

    testWidgets('says it in English too', (tester) async {
      await panel(
        tester,
        const VmLoadProgress(5000000, total, bytesPerSecond: 2300000, remaining: Duration(seconds: 42)),
        const Locale('en'),
      );

      expect(find.text('Downloading the machine'), findsOneWidget);
      expect(find.text('5.0 of 20.4 MB'), findsOneWidget);
      expect(find.text('2.3 MB/s · about 45 seconds left'), findsOneWidget);
    });

    testWidgets('follows the machine through unpacking and starting', (tester) async {
      final progress = await panel(tester, const VmLoadProgress(total, total));
      expect(find.text('De machine wordt uitgepakt'), findsOneWidget, reason: 'all of it is here, and unpacking is next');

      await show(tester, progress, const VmLoadProgress(total, total, phase: VmLoadPhase.unpack));
      expect(find.text('De machine wordt uitgepakt'), findsOneWidget);
      expect(find.byIcon(FLucideIcons.check), findsOneWidget, reason: 'downloading is done');

      await show(tester, progress, const VmLoadProgress(total, total, phase: VmLoadPhase.start));
      expect(find.text('De machine wordt gestart'), findsOneWidget);
      expect(find.byIcon(FLucideIcons.check), findsNWidgets(2), reason: 'downloading and unpacking are done');
    });

    testWidgets('a stalled download says so calmly, and stops quoting a speed it no longer has', (tester) async {
      await panel(
        tester,
        const VmLoadProgress(5000000, total, bytesPerSecond: 2300000, remaining: Duration(seconds: 7), stalled: true),
      );

      expect(find.text('5,0 van 20,4 MB'), findsOneWidget);
      expect(find.textContaining('2,3 MB/s'), findsNothing);
      expect(note(tester), 'De verbinding is traag of even weg. Het downloaden gaat vanzelf verder zodra die terug is.');
    });

    testWidgets('says when the browser will not keep the machine', (tester) async {
      await panel(tester, const VmLoadProgress(5000000, total, keeps: false));

      expect(note(tester), startsWith('Deze browser kan de machine niet bewaren.'));
    });

    testWidgets('passes on a slow connection as a hint until the speed is known', (tester) async {
      final progress = await panel(tester, const VmLoadProgress(0, total, slowConnection: true));
      expect(note(tester), 'Je verbinding lijkt traag, dus dit kan een paar minuten duren.');

      await show(
        tester,
        progress,
        const VmLoadProgress(500000, total, slowConnection: true, bytesPerSecond: 60000, remaining: Duration(minutes: 5)),
      );
      expect(note(tester), isNull, reason: 'the measured speed says more');
    });

    testWidgets('says a download picks up where the last one stopped', (tester) async {
      await panel(tester, const VmLoadProgress(9000000, total, cached: 9000000));

      expect(note(tester), 'Het downloaden gaat verder waar het de vorige keer stopte.');
    });

    testWidgets('keeps its size as the speed, the time left and a note arrive', (tester) async {
      final progress = await panel(tester);
      final before = column(tester);

      await show(tester, progress, const VmLoadProgress(5000000, total, bytesPerSecond: 2300000, remaining: Duration(seconds: 7)));
      expect(column(tester), before);

      await show(tester, progress, const VmLoadProgress(5000000, total, keeps: false));
      expect(column(tester), before);
    });

    testWidgets('moves nothing by itself', (tester) async {
      // The emulator shares the page's thread: a panel that animated between
      // reports would slow the download's own restore.
      await panel(tester, const VmLoadProgress(1, 2, bytesPerSecond: 100000, remaining: Duration(seconds: 1)));

      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('VmDisplay', () {
    late FakeDisplayBinding binding;
    late FocusNode before;
    late FocusNode node;
    late FocusNode after;
    late List<KeyEvent> appKeys;

    setUp(() {
      binding = FakeDisplayBinding();
      before = FocusNode(debugLabel: 'before');
      node = FocusNode(debugLabel: 'display');
      after = FocusNode(debugLabel: 'after');
      appKeys = [];
    });

    tearDown(() {
      before.dispose();
      node.dispose();
      after.dispose();
    });

    /// The display between two focusable neighbours, under the app's own Tab
    /// shortcuts and a handler that stands for every other shortcut the app has.
    Future<void> display(WidgetTester tester, {Widget? over, bool holdsTab = true}) async {
      await tester.pumpWidget(
        _host(
          Shortcuts(
            shortcuts: WidgetsApp.defaultShortcuts,
            child: Actions(
              actions: WidgetsApp.defaultActions,
              child: Focus(
                onKeyEvent: (node, event) {
                  appKeys.add(event);
                  return KeyEventResult.ignored;
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Focus(focusNode: before, child: const SizedBox(width: 400, height: 40)),
                    SizedBox(
                      width: 400,
                      height: 300,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: VmDisplay(
                              binding: binding,
                              region: _region,
                              scale: 1,
                              focusNode: node,
                              semanticsLabel: 'My window',
                              background: const Color(0xFF101010),
                              holdsTab: holdsTab,
                              viewBuilder: _fakeView,
                            ),
                          ),
                          ?over,
                        ],
                      ),
                    ),
                    Focus(focusNode: after, child: const SizedBox(width: 400, height: 40)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    Future<void> focusDisplay(WidgetTester tester) async {
      await tester.tap(find.byType(VmDisplay));
      await tester.pump();
    }

    bool displayHasFocus(WidgetTester tester) => node.hasFocus;

    testWidgets('builds with a view of its own, and hands it back when it goes', (tester) async {
      await display(tester);

      expect(binding.background, const Color(0xFF101010));

      await tester.pumpWidget(const SizedBox());

      expect(binding.released, [_FakeView.viewId]);
      expect(binding.keyboardEnabled, isFalse);
      expect(binding.mouseEnabled, isFalse);
    });

    testWidgets('shows its region at its scale, and a new one as soon as it has one', (tester) async {
      final region = ValueNotifier<Rect>(_region);
      addTearDown(region.dispose);
      await tester.pumpWidget(
        _host(
          Align(
            alignment: Alignment.topLeft,
            child: ValueListenableBuilder<Rect>(
              valueListenable: region,
              builder: (context, shown, _) => SizedBox.fromSize(
                size: shown.size / 2,
                child: VmDisplay(
                  binding: binding,
                  region: shown,
                  scale: 0.5,
                  semanticsLabel: 'My window',
                  background: const Color(0xFF101010),
                  viewBuilder: _fakeView,
                ),
              ),
            ),
          ),
        ),
      );

      expect((binding.region, binding.scale), (_region, 0.5));

      region.value = const Rect.fromLTWH(40, 30, 200, 100);
      await tester.pump();
      expect(binding.region, const Rect.fromLTWH(40, 30, 200, 100));

      final shown = binding.regionsShown;
      await tester.pump();
      expect(binding.regionsShown, shown, reason: 'nothing new to show, nothing sent');
    });

    testWidgets('a display another has replaced does not move the screen under it', (tester) async {
      final older = ValueNotifier<Rect>(_region);
      addTearDown(older.dispose);
      const newer = Rect.fromLTWH(10, 10, 200, 100);
      Widget at(Rect region) => SizedBox.fromSize(
        size: region.size,
        child: VmDisplay(
          binding: binding,
          region: region,
          scale: 1,
          semanticsLabel: 'My window',
          background: const Color(0xFF101010),
          viewBuilder: _fakeView,
        ),
      );
      await tester.pumpWidget(
        _host(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<Rect>(valueListenable: older, builder: (context, region, _) => at(region)),
              at(newer),
            ],
          ),
        ),
      );
      expect(binding.region, newer, reason: 'the one that bound last');

      older.value = const Rect.fromLTWH(0, 0, 300, 200);
      await tester.pump();

      expect(binding.region, newer);
    });

    testWidgets('holding focus puts no focused node in the semantics tree', (tester) async {
      final semantics = tester.ensureSemantics();
      await display(tester);
      await focusDisplay(tester);

      expect(displayHasFocus(tester), isTrue);
      // A focused node's element is where Flutter web moves DOM focus, away from the view.
      expect(
        tester.getSemantics(find.byType(VmDisplay)),
        isSemantics(label: 'My window', isFocusable: false, isFocused: false),
      );
      semantics.dispose();
    });

    testWidgets('a display that goes while it has the keyboard says it no longer has it', (tester) async {
      final reported = <bool>[];
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 400,
            height: 300,
            child: VmDisplay(
              binding: binding,
              region: _region,
              scale: 1,
              focusNode: node,
              semanticsLabel: 'My window',
              background: const Color(0xFF101010),
              onFocusChange: reported.add,
              viewBuilder: _fakeView,
            ),
          ),
        ),
      );
      node.requestFocus();
      await tester.pump();
      expect(reported, [true]);

      // A machine that failed, or a retry: the display goes while focused.
      await tester.pumpWidget(const SizedBox());

      expect(reported, [true, false]);
    });

    testWidgets('a display that replaces another on the same machine keeps the keyboard', (tester) async {
      // Without the page's global key: the new display binds before the old one
      // is disposed, and the node they share keeps Flutter focus throughout.
      final reported = <bool>[];
      // Through a notifier: the host's Overlay keeps the child it was first built with.
      final layout = ValueNotifier<Key>(const ValueKey('split'));
      addTearDown(layout.dispose);
      await tester.pumpWidget(
        _host(
          ValueListenableBuilder<Key>(
            valueListenable: layout,
            builder: (context, key, _) => SizedBox(
              width: 400,
              height: 300,
              child: VmDisplay(
                key: key,
                binding: binding,
                region: _region,
                scale: 1,
                focusNode: node,
                semanticsLabel: 'My window',
                background: const Color(0xFF101010),
                onFocusChange: reported.add,
                viewBuilder: _fakeView,
              ),
            ),
          ),
        ),
      );
      node.requestFocus();
      await tester.pump();
      final first = tester.state(find.byType(VmDisplay));
      expect(binding.keyboardEnabled, isTrue);

      layout.value = const ValueKey('stacked');
      await tester.pump();

      expect(tester.state(find.byType(VmDisplay)), isNot(same(first)), reason: 'a display of its own');
      expect(node.hasFocus, isTrue);
      expect(binding.keyboardEnabled, isTrue, reason: 'the old display\'s unbind left it to the new one');
      expect(reported.last, isTrue, reason: 'the frame still states the way out');

      await tester.pumpWidget(const SizedBox());
      expect(binding.keyboardEnabled, isFalse, reason: 'the last display to go takes the keyboard with it');
      expect(reported.last, isFalse);
    });

    testWidgets('a press gives the keyboard back to a display that kept focus without it', (tester) async {
      // Escape then Tab with nowhere to go: the Tab turns the keyboard off, and
      // focus stays, so no focus change will ever turn it back on.
      await tester.pumpWidget(
        _host(
          Shortcuts(
            shortcuts: WidgetsApp.defaultShortcuts,
            child: Actions(
              actions: WidgetsApp.defaultActions,
              child: SizedBox(
                width: 400,
                height: 300,
                child: VmDisplay(
                  binding: binding,
                  region: _region,
                  scale: 1,
                  focusNode: node,
                  semanticsLabel: 'My window',
                  background: const Color(0xFF101010),
                  viewBuilder: _fakeView,
                ),
              ),
            ),
          ),
        ),
      );
      await focusDisplay(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(displayHasFocus(tester), isTrue);
      expect(binding.keyboardEnabled, isFalse);
      final focusedBefore = binding.elementFocused;

      await focusDisplay(tester);

      expect(binding.keyboardEnabled, isTrue);
      expect(binding.elementFocused, greaterThan(focusedBefore), reason: 'DOM focus comes back with it');
    });

    testWidgets('a press takes the keyboard, and DOM focus follows', (tester) async {
      await display(tester);
      expect(binding.keyboardEnabled, isFalse, reason: 'the guest\'s keys listen on the whole window');

      await focusDisplay(tester);

      expect(displayHasFocus(tester), isTrue);
      expect(binding.keyboardEnabled, isTrue);
      expect(binding.elementFocused, greaterThan(0));
    });

    testWidgets('every key goes to the program and none to the app', (tester) async {
      await display(tester);
      await focusDisplay(tester);

      for (final key in [
        LogicalKeyboardKey.keyK,
        LogicalKeyboardKey.space,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.enter,
        LogicalKeyboardKey.tab,
      ]) {
        await tester.sendKeyEvent(key);
      }
      await tester.pump();

      expect(appKeys, isEmpty, reason: 'the app\'s shortcuts never see a key meant for the program');
      expect(displayHasFocus(tester), isTrue, reason: 'Tab alone belongs to the program');
      expect(after.hasFocus, isFalse);
    });

    testWidgets('Escape then Tab leaves, with the keyboard off before the Tab arrives', (tester) async {
      await display(tester);
      await focusDisplay(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      expect(after.hasFocus, isTrue);
      expect(binding.keyboardEnabled, isFalse);
      expect(binding.focusReleased, greaterThan(0));
    });

    testWidgets('with no program to type into, Tab alone leaves, with the keyboard off first', (tester) async {
      await display(tester, holdsTab: false);
      await focusDisplay(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      expect(after.hasFocus, isTrue);
      expect(binding.keyboardEnabled, isFalse);
    });

    testWidgets('Escape then Shift+Tab leaves backwards', (tester) async {
      await display(tester);
      await focusDisplay(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();

      expect(before.hasFocus, isTrue);
      expect(binding.keyboardEnabled, isFalse);
    });

    testWidgets('a key between Escape and Tab keeps the program\'s Tab', (tester) async {
      await display(tester);
      await focusDisplay(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      expect(displayHasFocus(tester), isTrue);
      expect(binding.keyboardEnabled, isTrue);
    });

    testWidgets('DOM focus arriving takes Flutter focus, and leaving turns the keys off', (tester) async {
      await display(tester);

      binding.moveDomFocus(inside: true);
      await tester.pump();
      expect(displayHasFocus(tester), isTrue);
      expect(binding.keyboardEnabled, isTrue);

      binding.moveDomFocus(inside: false);
      await tester.pump();
      expect(displayHasFocus(tester), isFalse);
      expect(binding.keyboardEnabled, isFalse);
    });

    testWidgets('the mouse is the program\'s only while nothing is drawn over it', (tester) async {
      await display(
        tester,
        // A popover over the right half of the screen.
        over: const Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          width: 200,
          child: ColoredBox(color: Color(0xFFFFFFFF)),
        ),
      );
      final screen = tester.getRect(find.byType(VmDisplay));

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);

      await mouse.moveTo(screen.centerLeft + const Offset(50, 0));
      expect(binding.mouseEnabled, isTrue, reason: 'over the program\'s screen');

      await mouse.moveTo(screen.centerRight - const Offset(50, 0));
      expect(binding.mouseEnabled, isFalse, reason: 'over the popover, which wins the hit test');

      await mouse.moveTo(screen.centerLeft + const Offset(50, 0));
      expect(binding.mouseEnabled, isTrue);

      await mouse.moveTo(screen.bottomCenter + const Offset(0, 20));
      expect(binding.mouseEnabled, isFalse, reason: 'off the screen altogether');
    });

    testWidgets('the wheel scrolls the program, not the page around it', (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        _host(
          SingleChildScrollView(
            controller: scroll,
            child: Column(
              children: [
                SizedBox(
                  width: 400,
                  height: 300,
                  child: VmDisplay(
                    binding: binding,
                    region: _region,
                    scale: 1,
                    semanticsLabel: 'My window',
                    background: const Color(0xFF101010),
                    viewBuilder: _fakeView,
                  ),
                ),
                const SizedBox(
                  key: Key('page'),
                  height: 3000,
                  width: 400,
                  child: ColoredBox(color: Color(0xFFFFFFFF)),
                ),
              ],
            ),
          ),
        ),
      );

      tester.binding.handlePointerEvent(
        PointerScrollEvent(position: tester.getCenter(find.byType(VmDisplay)), scrollDelta: const Offset(0, 120)),
      );
      await tester.pump();
      expect(scroll.offset, 0);

      // The page itself still scrolls, which is what makes the first one mean something.
      tester.binding.handlePointerEvent(
        PointerScrollEvent(
          position: tester.getTopLeft(find.byKey(const Key('page'))) + const Offset(20, 20),
          scrollDelta: const Offset(0, 120),
        ),
      );
      await tester.pump();
      expect(scroll.offset, greaterThan(0));
    });
  });

  group('the page', () {
    late List<FakeVmRuntime> runtimes;

    setUp(() => runtimes = []);

    FakeVmRuntime runtime() => runtimes.last;

    Future<void> open(WidgetTester tester, {Size size = const Size(1400, 1000)}) async {
      _useWindow(tester, size);
      await tester.pumpWidget(
        _host(
          _TestTkinterScreen(() {
            final created = FakeVmRuntime();
            runtimes.add(created);
            return created;
          }),
          size: size,
        ),
      );
      await _settleEditor(tester);
    }

    testWidgets('a build without the image says so, and blames neither the browser nor the connection', (tester) async {
      // The page as `flutter test` builds it: no ICC_VM_IMAGE, and the stub.
      GetIt.I
        ..registerSingleton<CodeDraftStore>(CodeDraftStore())
        ..registerSingleton<EditorSettings>(EditorSettings());
      addTearDown(GetIt.I.reset);
      _useWindow(tester, const Size(1400, 1000));
      await tester.pumpWidget(_host(const TkinterScreen(subjectSlug: 'learn-python')));
      await _settleEditor(tester);

      expect(find.text('Tkinter zit niet in deze versie van de app'), findsOneWidget);
      expect(find.textContaining('internetverbinding ligt het niet'), findsOneWidget);
      expect(find.byType(VmLoadPanel), findsNothing, reason: 'there is nothing to download');
      expect(find.byType(VmDisplay), findsNothing);
      // The editor stays: a program can still be written, only not run here.
      expect(find.text('main.py'), findsOneWidget);
    });

    testWidgets('says why where the browser cannot host the machine', (tester) async {
      _useWindow(tester, const Size(1400, 1000));
      await tester.pumpWidget(_host(_TestTkinterScreen(() => FakeVmRuntime(supported: false))));
      await _settleEditor(tester);

      expect(find.text('Dit werkt niet in deze browser'), findsOneWidget);
      expect(find.byType(VmDisplay), findsNothing);
    });

    testWidgets('shows the download where the screen will be, with the editor already open', (tester) async {
      await open(tester);
      runtime().emit(const VmLoadProgress(5000000, 20373228));
      await _deliver(tester);

      expect(find.byType(VmLoadPanel), findsOneWidget);
      expect(find.text('5,0 van 20,4 MB'), findsOneWidget);
      expect(find.text('Machine laden…'), findsOneWidget);
      expect(find.byType(VmDisplay), findsNothing);
    });

    testWidgets('the machine names itself, and its screen comes with the program', (tester) async {
      await open(tester);
      runtime().ready();
      await _deliver(tester);

      expect(find.text('Python 3.12.12 · Tk 8.6.16'), findsOneWidget);
      expect(find.byType(VmDisplay), findsNothing, reason: 'there is nothing to show until a program runs');

      await tester.tap(find.text('Uitvoeren'));
      await tester.pumpAndSettle();

      expect(find.byType(VmDisplay), findsOneWidget);
      expect(find.text('Je programma'), findsOneWidget);
    });

    testWidgets('Run during the download waits in the dialog, which does not jump when the machine arrives', (tester) async {
      await open(tester);
      runtime().emit(const VmLoadProgress(5000000, 20373228));
      await _deliver(tester);
      await tester.tap(find.text('Uitvoeren'));
      await tester.pumpAndSettle();

      expect(find.text('Je programma'), findsOneWidget);
      final loading = tester.getSize(find.byType(VmLoadPanel));
      expect(loading, WindowFrame.emptySize);
      expect(find.text('Wacht op de machine…'), findsOneWidget);

      runtime().ready();
      await _deliver(tester);

      final panel = find.byType(NoWindowPanel);
      expect(tester.widget<NoWindowPanel>(panel).text, 'Het venster van je programma verschijnt hier.');
      expect(tester.getSize(panel), WindowFrame.emptySize, reason: 'the dialog does not jump when the machine is ready');
      expect(tester.getRect(find.byType(VmDisplay)), tester.getRect(panel), reason: 'built beneath it');
      expect(tester.getSemantics(find.byType(VmDisplay)), isSemantics(label: 'Je programma'));

      // A press on the stand-in is a press on the display: it takes the keyboard.
      // The stand-in itself never takes one, which is what warnIfMissed sees.
      await tester.tap(panel, warnIfMissed: false);
      await tester.pump();
      expect(runtime().display.keyboardEnabled, isTrue);
    });

    testWidgets('the frame hugs the program\'s windows, and a dialog widens it until it closes', (tester) async {
      await open(tester);
      runtime().ready();
      await _deliver(tester);
      await tester.tap(find.text('Uitvoeren'));
      await tester.pumpAndSettle();
      final id = runtime().lastRunId;
      final display = runtime().display;

      runtime().emit(VmWindows(id, const [_small]));
      await _deliver(tester);

      expect(find.byType(NoWindowPanel), findsNothing);
      expect(tester.getSize(find.byType(VmDisplay)), const Size(237, 113), reason: 'at its real size');
      expect((display.region, display.scale), (const Rect.fromLTWH(0, 0, 237, 113), 1.0));
      expect(find.text('My first window'), findsOneWidget);

      // A messagebox, centred on its parent and pushed back onto the screen.
      const dialog = VmWindow(xid: 12, title: 'Question', mapped: true, transientFor: 11, y: 20, width: 300, height: 120);
      runtime().emit(VmWindows(id, const [_small, dialog]));
      await _deliver(tester);

      expect(tester.getSize(find.byType(VmDisplay)), const Size(300, 140));
      expect(display.region, const Rect.fromLTWH(0, 0, 300, 140));
      expect(find.text('My first window'), findsOneWidget, reason: 'the frame still names the main window');

      runtime().emit(VmWindows(id, const [_small]));
      await _deliver(tester);

      expect(display.region, const Rect.fromLTWH(0, 0, 237, 113));
      expect(tester.getSize(find.byType(VmDisplay)), const Size(237, 113));
    });

    testWidgets('every window the frame does not name gets a strip of its own', (tester) async {
      await open(tester);
      runtime().ready();
      await _deliver(tester);
      await tester.tap(find.text('Uitvoeren'));
      await tester.pumpAndSettle();
      final id = runtime().lastRunId;

      // A second Toplevel, which with no window manager opens over the root.
      const second = VmWindow(xid: 12, title: 'Second window', mapped: true, width: 200, height: 100);
      runtime().emit(VmWindows(id, const [_small, second]));
      await _deliver(tester);

      expect(find.text('My first window'), findsOneWidget, reason: 'the frame names the root');
      expect(find.text('Second window'), findsOneWidget, reason: 'the second window names itself');

      await tester.tap(find.descendant(of: find.byType(WindowStrips), matching: find.byType(WindowCloseButton)));
      await tester.pump();

      expect(runtime().closedWindows, [12], reason: 'the strip closes its own window, not the framed one');

      runtime().emit(VmWindows(id, const [_small]));
      await _deliver(tester);

      expect(find.byType(WindowStrips), findsNothing, reason: 'one window needs no strip of its own');
      await _settleEditor(tester);
    });

    testWidgets('a window that moves or grows moves the region with it at once', (tester) async {
      await open(tester);
      runtime().ready();
      await _deliver(tester);
      await tester.tap(find.text('Uitvoeren'));
      await tester.pumpAndSettle();
      final id = runtime().lastRunId;

      runtime().emit(VmWindows(id, const [_small]));
      await _deliver(tester);
      runtime().emit(
        VmWindows(id, const [VmWindow(xid: 11, title: 'My first window', mapped: true, isRoot: true, x: 40, y: 30, width: 400, height: 250)]),
      );
      await _deliver(tester);

      expect(runtime().display.region, const Rect.fromLTWH(40, 30, 400, 250));
      expect(tester.getSize(find.byType(VmDisplay)), const Size(400, 250));
      expect(tester.hasRunningAnimations, isFalse, reason: 'the emulator shares the thread an animation would take');
    });

    testWidgets('a program that ends takes the dialog with it, black screen and all', (tester) async {
      await open(tester);
      runtime().ready();
      await _deliver(tester);
      await tester.tap(find.text('Uitvoeren'));
      await tester.pumpAndSettle();
      final id = runtime().lastRunId;
      runtime().emit(VmWindows(id, const [_small]));
      await _deliver(tester);

      runtime().end(id, const VmExit(reason: VmEndReason.exit, code: 0));
      await _deliver(tester);

      expect(find.byType(VmDisplay), findsNothing, reason: 'the screen is the run\'s, and the run is over');
      expect(find.byType(NoWindowPanel), findsNothing);
      expect(runtime().display.released, hasLength(1), reason: 'the platform view is handed back');
      expect(find.text('Uitvoeren').hitTestable(), findsOneWidget, reason: 'the page is the student\'s again');
    });

    testWidgets('a run: the button, the frame, the keyboard, the output and what went wrong', (tester) async {
      await open(tester);
      runtime().ready();
      await _deliver(tester);

      await tester.tap(find.text('Uitvoeren'));
      await tester.pumpAndSettle();

      expect(runtime().runs, hasLength(1));
      expect(runtime().lastSource, TkinterScreenViewModelBase.sample);
      expect(find.text('Stoppen'), findsOneWidget, reason: 'Run is also Stop, behind the dim');
      expect(
        find.text('Esc, dan Tab: verlaten'),
        findsOneWidget,
        reason: 'Run hands the keyboard to the program, and the frame says how to get it back',
      );

      final id = runtime().lastRunId;
      runtime()
        ..emit(VmWindows(id, const [VmWindow(xid: 11, title: 'My first window', mapped: true, isRoot: true)]))
        ..emit(VmOutput(id, 'Hallo\n', fromStderr: false));
      await tester.pump(TkinterScreenController.outputInterval);
      await _deliver(tester);

      expect(find.text('My first window'), findsOneWidget);

      runtime()
        ..emit(VmRunHint(id, VmHint.tkNoMainloop))
        ..end(id, const VmExit(reason: VmEndReason.exit, code: 0));
      await _deliver(tester);

      expect(find.text('Uitvoeren').hitTestable(), findsOneWidget);
      expect(find.byType(VmDisplay), findsNothing, reason: 'the windows went with the run');
      expect(runtime().display.keyboardEnabled, isFalse, reason: 'the keyboard is the page\'s again');
      expect(
        find.text('Esc, dan Tab: verlaten'),
        findsNothing,
        reason: 'there is no display left to leave',
      );
      expect(find.byType(RunNotice), findsOneWidget);
      expect(find.textContaining('mainloop()'), findsOneWidget);
      expect(tester.widget<OutputCard>(find.byType(OutputCard)).text, 'Hallo');
    });

    testWidgets('nothing on the page moves by itself while a program runs', (tester) async {
      // The emulator shares the page's thread; a page that repaints every frame
      // left it 3 % of its speed in the bench.
      await open(tester);
      runtime().ready();
      await _deliver(tester);
      await tester.tap(find.text('Uitvoeren'));
      await tester.pumpAndSettle();
      runtime().emit(VmWindows(runtime().lastRunId, const [VmWindow(xid: 11, title: 'Clock', mapped: true, isRoot: true)]));
      await _deliver(tester);

      // Settled, and then left alone for a while: nothing asks for a frame.
      for (var second = 0; second < 3; second++) {
        await tester.pump(const Duration(seconds: 1));
        expect(tester.hasRunningAnimations, isFalse);
        expect(SchedulerBinding.instance.hasScheduledFrame, isFalse);
      }
    });

    testWidgets('the cross ends the program, and a stop says nothing about it', (tester) async {
      await open(tester);
      runtime().ready();
      await _deliver(tester);
      await tester.tap(find.text('Uitvoeren'));
      await tester.pumpAndSettle();

      // The page's own Stop is behind the dim, which takes the press.
      await tester.tap(find.text('Stoppen'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(runtime().stops, 0, reason: 'nothing on the page takes a press meant for the program');

      await tester.tap(find.byIcon(FLucideIcons.x));
      await tester.pumpAndSettle();

      expect(runtime().stops, 1);
      expect(runtime().closedWindows, isEmpty, reason: 'the cross ends the run, it does not ask a window to close');
      expect(find.text('Uitvoeren').hitTestable(), findsOneWidget);
      expect(find.byType(RunNotice), findsNothing);
    });

    testWidgets('a machine that failed says what broke, in words that do not blame the student, and retries', (tester) async {
      await open(tester);
      runtime().emit(const VmFailed(VmFailure.network, 'The VM image manifest could not be read: HTTP 404'));
      await _deliver(tester);

      expect(find.byType(NoticeCard), findsOneWidget);
      expect(find.text('De machine kon niet worden gedownload'), findsOneWidget);
      expect(find.byType(VmLoadPanel), findsNothing);

      // The machine's own English stays folded on a Dutch page, one press away.
      final semantics = tester.ensureSemantics();
      const english = 'The VM image manifest could not be read: HTTP 404';
      expect(find.text(english), findsNothing);
      expect(
        tester.getSemantics(find.text('Technische details')),
        isSemantics(label: 'Technische details', isButton: true, hasExpandedState: true, isExpanded: false),
      );
      await tester.ensureVisible(find.text('Technische details'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Technische details'));
      await tester.pump();
      expect(find.text(english), findsOneWidget);
      expect(tester.getSemantics(find.text('Technische details')), isSemantics(hasExpandedState: true, isExpanded: true));
      semantics.dispose();

      await tester.tap(find.text('Opnieuw proberen'));
      await tester.pumpAndSettle();

      expect(runtimes, hasLength(2));
      expect(runtimes.first.disposed, isTrue);
      expect(find.byType(VmLoadPanel), findsOneWidget);
    });

    testWidgets('a notice fills the page\'s column, folded and open alike', (tester) async {
      await open(tester);
      runtime().emit(const VmFailed(VmFailure.network, 'HTTP 404 for state.bin.zst'));
      await _deliver(tester);

      final card = find.byType(NoticeCard);
      // Handed the width rather than only allowed it: a body that fits on one
      // line would otherwise leave the card as narrow as that line.
      final constraints = tester.renderObject<RenderBox>(card).constraints;
      expect(constraints.minWidth, constraints.maxWidth);

      final folded = tester.getRect(card);
      final editor = tester.getRect(find.byType(CodeEditorCard));
      expect((folded.left, folded.right), (editor.left, editor.right), reason: 'the page is one column');

      await tester.ensureVisible(find.text('Technische details'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Technische details'));
      await tester.pumpAndSettle();

      expect(tester.getRect(card).width, folded.width, reason: 'opening the details does not widen it');
    });

    testWidgets('a machine another page took over says so in the page\'s language', (tester) async {
      await open(tester);
      runtime()
        ..ready()
        ..emit(const VmFailed(VmFailure.replaced, 'A newer openVm() on this page took over the machine.'));
      await _deliver(tester);

      expect(find.text('Een andere Tkinter-pagina heeft de machine overgenomen'), findsOneWidget);
      expect(find.textContaining('openVm()'), findsNothing);
      expect(find.text('Opnieuw proberen'), findsOneWidget);
    });

    testWidgets('a harness failure during a run is not put on the student', (tester) async {
      await open(tester);
      runtime().ready();
      await _deliver(tester);
      await tester.tap(find.text('Uitvoeren'));
      await tester.pumpAndSettle();

      runtime().end(runtime().lastRunId, const VmExit(reason: VmEndReason.unresponsive, message: 'No PONG to PING.'));
      await _deliver(tester);

      final notice = tester.widget<RunNotice>(find.byType(RunNotice));
      expect(notice.aboutTheProgram, isFalse);
      expect(notice.text, startsWith('Dit lag niet aan je programma'));
    });

    testWidgets('a canvas too large for the machine is its limit, on a plain card', (tester) async {
      await open(tester);
      runtime().ready();
      await _deliver(tester);
      await tester.tap(find.text('Uitvoeren'));
      await tester.pumpAndSettle();

      final id = runtime().lastRunId;
      runtime()
        ..emit(
          VmOutput(
            id,
            'X Error of failed request:  BadAlloc (insufficient resources for operation)\n'
            '  Major opcode of failed request:  53 (X_CreatePixmap)\n',
            fromStderr: true,
          ),
        )
        ..end(id, const VmExit(reason: VmEndReason.exit, code: 1));
      await _deliver(tester);

      final notice = tester.widget<RunNotice>(find.byType(RunNotice));
      expect(notice.aboutTheProgram, isFalse);
      // Non-breaking, so the size is never split over two lines.
      expect(notice.text, contains('800\u00a0×\u00a0600'));
    });

    testWidgets('a resize while the program has the keyboard keeps it, in the same view', (tester) async {
      await open(tester);
      runtime().ready();
      await _deliver(tester);
      await tester.tap(find.text('Uitvoeren'));
      await tester.pumpAndSettle();
      final binding = runtime().display;
      final display = tester.state(find.byType(VmDisplay));
      expect(binding.keyboardEnabled, isTrue);

      // A window resize, browser zoom or a tablet turning.
      _useWindow(tester, const Size(900, 1400));
      await tester.pumpWidget(_host(_TestTkinterScreen(runtime), size: const Size(900, 1400)));
      await tester.pumpAndSettle();

      expect(tester.state(find.byType(VmDisplay)), same(display), reason: 'moved, not built again');
      expect(binding.released, isEmpty, reason: 'the platform view went with it');
      expect(binding.keyboardEnabled, isTrue);
      expect(find.text('Esc, dan Tab: verlaten'), findsOneWidget);

      // And back.
      _useWindow(tester, const Size(1400, 1000));
      await tester.pumpWidget(_host(_TestTkinterScreen(runtime)));
      await tester.pumpAndSettle();

      expect(tester.state(find.byType(VmDisplay)), same(display));
      expect(binding.keyboardEnabled, isTrue);
    });

    testWidgets('a window wider than the page is fitted into the dialog, keeping its shape', (tester) async {
      await open(tester, size: const Size(800, 1400));
      runtime().ready();
      await _deliver(tester);
      await tester.tap(find.text('Uitvoeren'));
      await tester.pumpAndSettle();
      runtime().emit(VmWindows(runtime().lastRunId, const [_fullScreen]));
      await _deliver(tester);

      final screen = tester.getSize(find.byType(VmDisplay));
      expect(screen.width, lessThanOrEqualTo(800 - 2 * ProgramDialog.margin - 2 * WindowFrame.bezel));
      expect(screen.width / screen.height, closeTo(800 / 600, 0.01));
      expect(runtime().display.scale, screen.width / 800);
    });

    testWidgets('leaving the page frees the machine', (tester) async {
      await open(tester);

      await tester.pumpWidget(const SizedBox());

      expect(runtime().disposed, isTrue);
    });
  });
}
