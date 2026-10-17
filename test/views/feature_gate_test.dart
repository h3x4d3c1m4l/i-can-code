import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:i_can_code/services/feature_toggles.dart';
import 'package:i_can_code/views/components/feature_gate.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

const StaticFeatureToggle _feature = StaticFeatureToggle('test', description: 'A test feature');

Widget _gate() => const Directionality(
  textDirection: TextDirection.ltr,
  child: FeatureGate(feature: _feature, fallback: Text('fallback'), child: Text('gated')),
);

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    GetIt.I.registerSingleton<FeatureToggles>(FeatureToggles());
  });

  tearDown(GetIt.I.reset);

  testWidgets('builds the fallback while the feature is off, which it starts as', (tester) async {
    await tester.pumpWidget(_gate());

    expect(find.text('gated'), findsNothing);
    expect(find.text('fallback'), findsOneWidget);
  });

  testWidgets('follows a switch at once, both ways', (tester) async {
    final toggles = GetIt.I<FeatureToggles>();
    await tester.pumpWidget(_gate());

    await toggles.set(_feature.name, on: true);
    await tester.pump();
    expect(find.text('gated'), findsOneWidget);

    await toggles.set(_feature.name, on: false);
    await tester.pump();
    expect(find.text('gated'), findsNothing);
  });
}
