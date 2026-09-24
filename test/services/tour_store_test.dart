import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_code/services/tour_store.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  });

  test('remembers what was seen, across a reload', () async {
    await TourStore().markSeen('lesson');

    final reloaded = TourStore();
    expect(reloaded.hasSeen('lesson'), isFalse, reason: 'nothing is read before load');

    await reloaded.load();
    expect(reloaded.hasSeen('lesson'), isTrue);
    expect(reloaded.hasSeen('catalog'), isFalse);
  });
}
