import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_code/services/vm/vm_manifest.dart';

void main() {
  // What `build-state.mjs` writes, cut down to the fields the app reads.
  const manifest = '''
{
 "imageId": "c5594d6160a1889b",
 "agentProto": 1,
 "interpreter": {"python": "Python 3.14.8", "tk": "8.6.17"},
 "notices": {"file": "NOTICES.txt", "bytes": 211500, "sha256": "e843"}
}''';

  test('names the interpreter the saved machine reported', () {
    expect(VmManifest.parse(manifest).interpreterLabel, 'Python 3.14.8 · Tk 8.6.17');
  });

  test('finds the notices inside the bundle it names', () {
    final parsed = VmManifest.parse(manifest);

    expect(parsed.noticesPath, 'vm/image/c5594d6160a1889b/NOTICES.txt');
    expect(parsed.noticesBytes, 211500);
  });

  test('a bundle without notices or an interpreter has neither to show', () {
    final parsed = VmManifest.parse('{"imageId": "298ac660"}');

    expect(parsed.noticesPath, isNull);
    expect(parsed.interpreterLabel, isNull);
  });

  test('refuses what a dev server answers a missing file with', () {
    expect(() => VmManifest.parse('<!DOCTYPE html><html></html>'), throwsFormatException);
    expect(() => VmManifest.parse('{"agentProto": 1}'), throwsFormatException);
  });

  test('a test has no image to read', () async {
    expect(await loadVmManifest(), isNull);
    await expectLater(loadVmNotices(), throwsUnsupportedError);
  });
}
