import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/l10n/generated/app_localizations.dart';
import 'package:i_can_code/services/editor_settings.dart';
import 'package:i_can_code/theme/theme.dart';
import 'package:i_can_code/views/base/build_context_accessor.dart';
import 'package:i_can_code/views/components/app_button.dart';
import 'package:i_can_code/views/editor_settings_screen/editor_settings_screen_controller.dart';
import 'package:i_can_code/views/editor_settings_screen/editor_settings_screen_view.dart';
import 'package:i_can_code/views/editor_settings_screen/editor_settings_screen_view_model.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  late EditorSettings settings;
  late EditorSettingsScreenViewModel viewModel;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    settings = EditorSettings();
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final accessor = BuildContextAccessor();
    viewModel = EditorSettingsScreenViewModel(contextAccessor: accessor);
    final controller = EditorSettingsScreenController(
      viewModel: viewModel,
      contextAccessor: accessor,
      settings: settings,
    );
    addTearDown(controller.dispose);
    final view = EditorSettingsScreenView(viewModel: viewModel, controller: controller, contextAccessor: accessor);

    await tester.pumpWidget(
      FTheme(
        data: buildAppTheme(),
        child: Localizations(
          locale: const Locale('nl'),
          delegates: AppLocalizations.localizationsDelegates,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: MediaQuery(
              data: const MediaQueryData(size: Size(1400, 1200)),
              // A Navigator, which brings its own Overlay: the dialog pushes a
              // route, the way it does under the app's router.
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
    await tester.pumpAndSettle();
  }

  AppButton restoreButton(WidgetTester tester) =>
      tester.widget<AppButton>(find.ancestor(of: find.text('Standaard herstellen'), matching: find.byType(AppButton)));

  testWidgets('opens on the default, says so, and has nothing to restore', (tester) async {
    await open(tester);

    expect(viewModel.tkinterSetup.text, EditorSettingsBase.defaultTkinterSetup);
    expect(find.text('Standaard'), findsOneWidget);
    expect(find.text('icc_setup.py'), findsOneWidget);
    expect(restoreButton(tester).onPress, isNull);
  });

  testWidgets('opens on what was set before', (tester) async {
    await settings.setTkinterSetup('print("eerder")\n');
    await open(tester);

    expect(viewModel.tkinterSetup.text, 'print("eerder")\n');
    expect(find.text('Aangepast'), findsOneWidget);
  });

  testWidgets('an edit is kept at once', (tester) async {
    await open(tester);

    viewModel.tkinterSetup.text = 'print("nieuw")\n';
    await tester.pump();

    expect(settings.tkinterSetup, 'print("nieuw")\n');
    expect(find.text('Aangepast'), findsOneWidget);
    expect(restoreButton(tester).onPress, isNotNull);
  });

  testWidgets('restoring asks first, then puts the default back', (tester) async {
    await open(tester);
    viewModel.tkinterSetup.text = 'print("nieuw")\n';
    await tester.pump();

    await tester.tap(find.text('Standaard herstellen'));
    await tester.pumpAndSettle();
    expect(find.text('Standaard herstellen?'), findsOneWidget);

    await tester.tap(find.text('Herstellen'));
    await tester.pumpAndSettle();
    expect(settings.tkinterSetupIsDefault, isTrue);
    expect(viewModel.tkinterSetup.text, EditorSettingsBase.defaultTkinterSetup);
  });

  testWidgets('cancelling keeps the change', (tester) async {
    await open(tester);
    viewModel.tkinterSetup.text = 'print("nieuw")\n';
    await tester.pump();

    await tester.tap(find.text('Standaard herstellen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuleren'));
    await tester.pumpAndSettle();

    expect(settings.tkinterSetup, 'print("nieuw")\n');
  });
}
