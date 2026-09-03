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

  test('every step of a lesson is one screen, and a second lesson is another', () {
    final first = lessonRoute(languageSlug: 'learn-python', lessonId: 'input-and-output', sectionId: 'intro');
    final later = lessonRoute(languageSlug: 'learn-python', lessonId: 'input-and-output', sectionId: 'print-yourself');
    final other = lessonRoute(languageSlug: 'learn-python', lessonId: 'variables', sectionId: 'intro');

    // auto_route keys a page on its route name alone, so the widget's own key
    // is the only thing that decides whether the screen — and its view model —
    // survives a replace. Equal within a lesson, different across lessons.
    expect(first.args!.key, later.args!.key);
    expect(first.args!.key, isNot(other.args!.key));
  });

  test('a lesson without a section resolves to the resume marker', () {
    final matched = AppRouter().matcher.match('/learn-python/input-and-output');

    // The bare form redirects rather than being a second route for the same
    // page, which auto_route forbids.
    expect(matched!.last.params.getString('sectionId'), resumeSection);
  });
}
