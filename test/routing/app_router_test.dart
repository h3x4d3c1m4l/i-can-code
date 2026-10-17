import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_code/routing/app_router.dart';
import 'package:i_can_code/routing/catalog_anchor.dart';

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
      '/licenses',
      '/about',
      '/learn-python',
      '/learn-python/$replLesson',
      '/learn-python/$microbitLesson',
      '/learn-python/$microbitLesson/dice',
      '/learn-python/hello',
      '/learn-python/hello/print-yourself',
    ]) {
      expect(matcher.match(path), isNotNull, reason: path);
    }
  });

  test('every step of a lesson is one screen, and a second lesson is another', () {
    final first = lessonRoute(subjectSlug: 'learn-python', lessonId: 'hello', sectionId: 'intro');
    final later = lessonRoute(subjectSlug: 'learn-python', lessonId: 'hello', sectionId: 'print-yourself');
    final other = lessonRoute(subjectSlug: 'learn-python', lessonId: 'variables', sectionId: 'intro');

    // auto_route keys a page on its route name alone, so the widget's own key
    // is the only thing that decides whether the screen — and its view model —
    // survives a replace. Equal within a lesson, different across lessons.
    expect(first.args!.key, later.args!.key);
    expect(first.args!.key, isNot(other.args!.key));
  });

  test('the licences have their own address, ahead of the subject addresses', () {
    // One segment, the same count as a subject, so it must be declared above
    // that route rather than be read as a subject called "licenses".
    final matched = AppRouter().matcher.match('/licenses');

    expect(matched, hasLength(1));
    expect(matched!.single.name, 'LicensesRoute');
  });

  test('About has its own address, ahead of the subject addresses', () {
    // One segment, like the licences, so it must be declared above the
    // subject route rather than be read as a subject called "about".
    final matched = AppRouter().matcher.match('/about');

    expect(matched, hasLength(1));
    expect(matched!.single.name, 'AboutRoute');
  });

  test('the console has its own address, ahead of the lesson addresses', () {
    // Declared above the lesson routes, so it must win the two-segment match
    // rather than being read as a lesson called "repl".
    final matched = AppRouter().matcher.match('/learn-python/$replLesson');

    expect(matched, hasLength(1));
    expect(matched!.single.name, 'ReplRoute');
    expect(matched.single.params.getString('subjectSlug'), 'learn-python');
  });

  test('both micro:bit screens have their own address, ahead of the lesson addresses', () {
    // Same arrangement as the console above: declared before the lesson routes,
    // so they win the two-segment match instead of being read as lessons called
    // "microbit" and "microbit-repl".
    final program = AppRouter().matcher.match('/learn-python/$microbitLesson');
    final repl = AppRouter().matcher.match('/learn-python/$microbitReplLesson');

    expect(program, hasLength(1));
    expect(program!.single.name, 'MicrobitProgramRoute');
    expect(program.single.params.getString('subjectSlug'), 'learn-python');

    expect(repl, hasLength(1));
    expect(repl!.single.name, 'MicrobitReplRoute');
    expect(repl.single.params.getString('subjectSlug'), 'learn-python');
  });

  test('a lesson without a section resolves to the resume marker', () {
    final matched = AppRouter().matcher.match('/learn-python/hello');

    // The bare form redirects rather than being a second route for the same
    // page, which auto_route forbids.
    expect(matched!.last.params.getString('sectionId'), resumeSection);
  });

  test('a project has its own address under the board, ahead of a lesson step', () {
    // Three segments, the same count as a lesson step, and `microbit` is a
    // reserved lesson id: so this must win rather than read as the step "dice"
    // of a lesson called "microbit".
    final matched = AppRouter().matcher.match('/learn-python/$microbitLesson/dice');

    expect(matched, hasLength(1));
    expect(matched!.single.name, 'ProjectRoute');
    expect(matched.single.params.getString('lessonId'), 'dice');
  });

  test('each project is a screen of its own', () {
    final first = projectRoute(subjectSlug: 'learn-python', lessonId: 'dice');
    final other = projectRoute(subjectSlug: 'learn-python', lessonId: 'marble');

    expect(first.args!.key, isNot(other.args!.key));
  });

  group('a place in the catalog', () {
    const CatalogAnchor week = (kind: CatalogAnchorKind.group, id: 'week-1');
    const CatalogAnchor lesson = (kind: CatalogAnchorKind.lesson, id: 'uitvoer');

    test('is named in the query, which leaves the catalog its own address', () {
      for (final anchor in [week, lesson]) {
        final matched = AppRouter().matcher.match('/learn-python?${anchor.kind.parameter}=${anchor.id}');

        expect(matched, hasLength(1));
        expect(matched!.single.name, 'CatalogRoute');
        expect(matched.single.queryParams.optString(anchor.kind.parameter), anchor.id);
      }
    });

    test('goes out in the address a route to it is given, under the name the screen reads it by', () {
      // The parameter names are written twice, on the screen's constructor and
      // on the kind. A route built from one has to be read back by the other.
      for (final anchor in [week, lesson]) {
        final route = catalogRoute(subjectSlug: 'learn-python', anchor: anchor);

        expect(route.rawQueryParams[anchor.kind.parameter], anchor.id);
        expect(route.rawQueryParams.values.nonNulls, [anchor.id], reason: 'and names nothing else');
      }
    });

    test('is a new screen every time it is asked for, and the catalog itself is not', () {
      // auto_route updates the page it has in place, and arguments that did not
      // change move nothing. A key of its own is what makes asking for the same
      // group twice scroll twice.
      final once = catalogRoute(subjectSlug: 'learn-python', anchor: week);
      final again = catalogRoute(subjectSlug: 'learn-python', anchor: week);

      expect(once.args!.key, isNotNull);
      expect(once.args!.key, isNot(again.args!.key));
      // And none where nothing is asked for: a reader comes back to the page
      // they left.
      expect(catalogRoute(subjectSlug: 'learn-python').args!.key, isNull);
    });

    test('has a whole address, with the route behind the hash', () {
      final base = Uri.parse('https://example.org/i-can-code/#/learn-python/uitvoer/intro');

      expect(
        catalogAddress(subjectSlug: 'learn-python', anchor: week, base: base).toString(),
        'https://example.org/i-can-code/#/learn-python?group=week-1',
      );
      expect(
        catalogAddress(subjectSlug: 'learn-python', anchor: lesson, base: base).toString(),
        'https://example.org/i-can-code/#/learn-python?lesson=uitvoer',
      );
    });
  });
}
