import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_code/routing/app_router.dart';

void main() {
  // `config()` builds a router delegate, which needs a binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the route table is valid', () {
    // auto_route validates the table when the router is first built, not at
    // codegen and not at compile time. Calling `config()` is what turns a
    // duplicate route name into a test failure rather than a browser one.
    expect(() => AppRouter().config(), returnsNormally);
  });

  test('every route is reachable by its own path', () {
    final matcher = AppRouter().matcher;

    for (final path in [
      '/',
      '/initialization',
      '/learn-python',
      '/learn-python/input-and-output',
      '/learn-python/input-and-output/print-yourself',
    ]) {
      expect(matcher.match(path), isNotNull, reason: path);
    }
  });

  test('a lesson without a section resolves to the resume marker', () {
    final matched = AppRouter().matcher.match('/learn-python/input-and-output');

    // The bare form redirects rather than being a second route for the same
    // page, which auto_route forbids.
    expect(matched!.last.params.getString('sectionId'), resumeSection);
  });
}
