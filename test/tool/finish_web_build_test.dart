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
      ]),
    );
    write('assets/assets/fonts/Lexend-Variable.ttf', 'lexend' * 100);
    write('assets/packages/forui/assets/fonts/inter/Inter.ttf', 'inter');
    write('assets/packages/forui/assets/fonts/inter/Inter-Italic.ttf', 'inter italic');
    write(courseBundlePath, '{}');
    write('canvaskit/canvaskit.wasm', 'full');
    write('canvaskit/chromium/canvaskit.wasm', 'chromium');
    write('canvaskit/skwasm.wasm', 'another renderer');
  });

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
    expect(families, ['Lexend', 'Roboto']);
  });

  test('a manifest without the unused font stops the build, since forui changed', () {
    stripUnusedFont(web);

    expect(() => stripUnusedFont(web), throwsA(isA<BuildCheckFailure>()));
  });

  test('every startup file is measured once, plain and gzipped', () {
    stripUnusedFont(web);
    final sizes = startupSizes(web);

    // The file bundled under two families weighs once.
    expect(sizes.files.keys, [
      'main.dart.js',
      'assets/FontManifest.json',
      'assets/assets/fonts/Lexend-Variable.ttf',
      courseBundlePath,
    ]);
    final [plain, gzipped] = sizes.files['assets/assets/fonts/Lexend-Variable.ttf']!;
    expect(plain, 600);
    expect(gzipped, lessThan(plain));

    // Only CanvasKit's own variants: the build ships other renderers beside them.
    expect(sizes.canvasKit.keys, ['canvaskit/canvaskit.wasm', 'canvaskit/chromium/canvaskit.wasm']);
  });

  test('the sizes take the placeholder\'s place in index.html', () {
    stripUnusedFont(web);
    writeStartupSizes(web, startupSizes(web));

    final index = read('index.html');
    expect(index, isNot(contains(sizesPlaceholder)));

    final table = index.substring(index.indexOf('= ') + 2, index.indexOf(';</script>'));
    final decoded = jsonDecode(table) as Map<String, dynamic>;
    expect((decoded['files'] as Map).keys, contains('main.dart.js'));
    expect((decoded['canvasKit'] as Map).keys, contains('canvaskit/chromium/canvaskit.wasm'));
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

  test('the build this was written for passes its checks', () {
    expect(() => checkAssumptions(web), returnsNormally);
  });
}
