import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_code/services/lessons/course.dart';

import '../../tool/finish_web_build.dart';

void main() {
  late Directory web;

  void write(String path, String text) => File('${web.path}/$path')
    ..createSync(recursive: true)
    ..writeAsStringSync(text);

  String read(String path) => File('${web.path}/$path').readAsStringSync();

  // The least of a `flutter build web` this tool reads.
  setUp(() {
    web = Directory.systemTemp.createTempSync('finish_web_build_test');

    write('index.html', '<script>const sizes = $sizesPlaceholder;</script> {"useLocalCanvasKit":true}');
    write('main.dart.js', 'A.fC(v.G.window.fetch(a),t.X)');
    write(
      'assets/FontManifest.json',
      jsonEncode([
        {
          'family': 'Lexend',
          'fonts': [
            {'asset': 'assets/fonts/Lexend-Variable.ttf'},
          ],
        },
        {
          'family': 'Roboto',
          'fonts': [
            {'asset': 'assets/fonts/Lexend-Variable.ttf'},
          ],
        },
        {
          'family': unusedFontFamily,
          'fonts': [
            {'asset': 'packages/forui/assets/fonts/inter/Inter.ttf'},
            {'style': 'italic', 'asset': 'packages/forui/assets/fonts/inter/Inter-Italic.ttf'},
          ],
        },
        for (final family in unlistedFontFamilies)
          {
            'family': family,
            'fonts': [
              {'asset': '$family.ttf'},
            ],
          },
      ]),
    );
    write('assets/assets/fonts/Lexend-Variable.ttf', 'lexend' * 100);
    write('assets/packages/forui/assets/fonts/inter/Inter.ttf', 'inter');
    write('assets/packages/forui/assets/fonts/inter/Inter-Italic.ttf', 'inter italic');
    for (final family in unlistedFontFamilies) {
      write('assets/$family.ttf', 'icon');
    }
    write(courseBundlePath, '{}');
    write('canvaskit/canvaskit.wasm', 'full');
    write('canvaskit/chromium/canvaskit.wasm', 'chromium');
    write('canvaskit/skwasm.wasm', 'skwasm');
    write('canvaskit/skwasm_heavy.wasm', 'skwasm heavy');
    write('canvaskit/wimp.wasm', 'another renderer');
  });

  // What `--wasm` adds to the build above.
  void buildWasm() {
    write('main.dart.wasm', 'wasm' * 100);
    write('main.dart.mjs', 'YJ: (x0,x1) => x0.fetch(x1),');
  }

  tearDown(() => web.deleteSync(recursive: true));

  test('the course bundle is looked for where the build puts it', () {
    expect(courseBundlePath, 'assets/${Course.bundleAsset}');
  });

  test('the unused font leaves the manifest and the build, and nothing else does', () {
    final removed = stripUnusedFont(web);

    expect(removed, [
      'assets/packages/forui/assets/fonts/inter/Inter.ttf',
      'assets/packages/forui/assets/fonts/inter/Inter-Italic.ttf',
    ]);
    expect(File('${web.path}/${removed.first}').existsSync(), isFalse);
    expect(File('${web.path}/assets/assets/fonts/Lexend-Variable.ttf').existsSync(), isTrue);

    final families = (jsonDecode(read('assets/FontManifest.json')) as List<dynamic>).map((f) => (f as Map)['family']);
    expect(families, ['Lexend', 'Roboto', ...unlistedFontFamilies]);
  });

  test("code_forge's fonts leave the manifest and stay in the build", () {
    unlistFonts(web);

    final families = (jsonDecode(read('assets/FontManifest.json')) as List<dynamic>).map((f) => (f as Map)['family']);
    expect(families, ['Lexend', 'Roboto', unusedFontFamily]);
    for (final family in unlistedFontFamilies) {
      expect(File('${web.path}/assets/$family.ttf').existsSync(), isTrue, reason: family);
    }
  });

  test("a manifest without code_forge's fonts stops the build, since code_forge changed", () {
    unlistFonts(web);

    expect(() => unlistFonts(web), throwsA(isA<BuildCheckFailure>()));
  });

  test('a manifest without the unused font stops the build, since forui changed', () {
    stripUnusedFont(web);

    expect(() => stripUnusedFont(web), throwsA(isA<BuildCheckFailure>()));
  });

  test('every startup file is measured once, plain and gzipped', () {
    stripUnusedFont(web);
    unlistFonts(web);
    final sizes = startupSizes(web);

    // The file bundled under two families weighs once.
    expect(sizes.files.keys, [
      'assets/FontManifest.json',
      'assets/assets/fonts/Lexend-Variable.ttf',
      courseBundlePath,
    ]);
    final [plain, gzipped] = sizes.files['assets/assets/fonts/Lexend-Variable.ttf']!;
    expect(plain, 600);
    expect(gzipped, lessThan(plain));

    // Only the JavaScript build, with only CanvasKit's own variants: the build
    // ships other renderers beside them.
    expect(sizes.builds.keys, ['dart2js']);
    expect(sizes.builds['dart2js']!.files.keys, ['main.dart.js']);
    expect(sizes.builds['dart2js']!.renderers.keys, ['canvaskit/canvaskit.wasm', 'canvaskit/chromium/canvaskit.wasm']);
  });

  test('a build with --wasm is measured as two builds, each with its own entrypoint and renderers', () {
    buildWasm();
    stripUnusedFont(web);
    unlistFonts(web);
    final sizes = startupSizes(web);

    expect(sizes.files.keys, isNot(contains('main.dart.wasm')));
    expect(sizes.builds.keys, ['dart2js', 'dart2wasm']);
    expect(sizes.builds['dart2js']!.files.keys, ['main.dart.js']);
    expect(sizes.builds['dart2wasm']!.files.keys, ['main.dart.wasm']);
    expect(sizes.builds['dart2wasm']!.renderers.keys, skwasmVariants);
  });

  test('a build with --wasm and no skwasm stops the build', () {
    buildWasm();
    File('${web.path}/canvaskit/skwasm_heavy.wasm').deleteSync();

    expect(() => startupSizes(web), throwsA(isA<BuildCheckFailure>()));
  });

  test('the sizes take the placeholder\'s place in index.html', () {
    stripUnusedFont(web);
    writeStartupSizes(web, startupSizes(web));

    final index = read('index.html');
    expect(index, isNot(contains(sizesPlaceholder)));

    final table = index.substring(index.indexOf('= ') + 2, index.indexOf(';</script>'));
    final decoded = jsonDecode(table) as Map<String, dynamic>;
    expect((decoded['files'] as Map).keys, contains(courseBundlePath));
    final js = (decoded['builds'] as Map)['dart2js'] as Map;
    expect((js['files'] as Map).keys, ['main.dart.js']);
    expect((js['renderers'] as Map).keys, contains('canvaskit/chromium/canvaskit.wasm'));
  });

  test('an index.html without the placeholder stops the build', () {
    write('index.html', '<script></script> {"useLocalCanvasKit":true}');

    expect(() => writeStartupSizes(web, startupSizes(web)), throwsA(isA<BuildCheckFailure>()));
  });

  test('a build that loads CanvasKit from a CDN is refused', () {
    write('index.html', '<script>const sizes = $sizesPlaceholder;</script> {"useLocalCanvasKit":false}');

    expect(() => checkAssumptions(web), throwsA(isA<BuildCheckFailure>()));
  });

  test('an engine that no longer fetches through window.fetch is refused', () {
    write('main.dart.js', 'A.somethingElse(a)');

    expect(() => checkAssumptions(web), throwsA(isA<BuildCheckFailure>()));
  });

  test('a WebAssembly engine that no longer calls fetch is refused', () {
    buildWasm();
    write('main.dart.mjs', 'YJ: (x0,x1) => x0.somethingElse(x1),');

    expect(() => checkAssumptions(web), throwsA(isA<BuildCheckFailure>()));
  });

  test('the build this was written for passes its checks', () {
    expect(() => checkAssumptions(web), returnsNormally);
  });

  test('the same build with --wasm passes its checks', () {
    buildWasm();

    expect(() => checkAssumptions(web), returnsNormally);
  });
}
