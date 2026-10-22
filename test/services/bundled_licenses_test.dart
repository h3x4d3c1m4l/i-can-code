import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_code/app_info.dart';
import 'package:i_can_code/services/licenses/bundled_licenses.dart';
import 'package:i_can_code/services/licenses/license_catalog.dart';
import 'package:yaml/yaml.dart';

/// The directories a bundled licence text lives in, and which files in them
/// are one.
const Map<String, String> _licenceFiles = {
  'assets/licenses': '.txt',
  'assets/python/licenses': '.txt',
  'assets/microbit/licenses': '.txt',
  'assets/fonts': '.txt',
};

void main() {
  // The asset bundle `flutter test` builds from pubspec.yaml is what
  // `rootBundle` reads here, and it needs a binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  final separator = '\n${'-' * 80}\n';

  group('parseNotices', () {
    test('splits the names of a text from the text', () {
      final notices = parseNotices('one\ntwo\n\nFirst text.\n\nIts second paragraph.${separator}three\n\nSecond text.');

      expect(notices.map((it) => it.packages), [
        ['one', 'two'],
        ['three'],
      ]);
      expect(notices.first.text, 'First text.\n\nIts second paragraph.');
      expect(notices.last.text, 'Second text.');
    });

    test('reads two files joined end to end', () {
      // What `just gen-rust-licenses` writes: cargo-about ends each run with a
      // separator and a newline, and the two runs are appended.
      final joined = 'one\n\nFirst.$separator\ntwo\n\nSecond.$separator\n';

      expect(parseNotices(joined).map((it) => (it.packages.single, it.text)), [('one', 'First.'), ('two', 'Second.')]);
    });

    test('keeps the indent a text opens with', () {
      final notices = parseNotices('apache\n\n        Apache License\n   Version 2.0');

      expect(notices.single.text, startsWith('        Apache License'));
    });

    test('refuses a text that has no names', () {
      // A licence with a line of 80 hyphens in it is cut in two, and the second
      // half then has nothing above its first blank line.
      expect(() => parseNotices('one\n\nFirst half.$separator\n\nSecond half.').toList(), throwsFormatException);
    });
  });

  group('the bundled licences', () {
    test('every one is in the bundle, and says something', () async {
      // Read through the bundle rather than off the disk: a file that is there
      // and not declared in pubspec.yaml is absent at runtime, without a word.
      final entries = await bundledLicenseEntries(rootBundle).toList();

      expect(entries, isNotEmpty);
      for (final entry in entries) {
        expect(entry.packages, isNotEmpty);
        expect(entry.packages, everyElement(isNotEmpty));
        expect((entry as BundledLicenseEntry).text.trim(), isNotEmpty, reason: '${entry.packages}');
      }
    });

    test('no licence file on disk is left out of the list', () {
      final listed = kBundledLicenses.map((it) => it.asset).toSet();

      for (final MapEntry(key: directory, value: suffix) in _licenceFiles.entries) {
        final files = Directory(directory).listSync().whereType<File>().where((it) => it.path.endsWith(suffix));

        for (final file in files) {
          expect(listed, contains(file.path), reason: 'add it to kBundledLicenses, or nobody is shown it');
        }
      }
    });

    test('a generated text names its copyright holder', () async {
      // cargo-about prints the SPDX template for a crate that ships no licence
      // file, placeholders and all. `rust/about.toml` clarifies those.
      final generated = kBundledLicenses.where((it) => it.packages.isEmpty);

      expect(generated, isNotEmpty);
      for (final license in generated) {
        final text = await rootBundle.loadString(license.asset);

        expect(text, isNot(contains('<year>')), reason: license.asset);
        expect(text, isNot(contains('<copyright holders>')), reason: license.asset);
        for (final notice in parseNotices(text)) {
          expect(notice.packages, everyElement(matches(RegExp(r'^[A-Za-z0-9_-]+$'))), reason: license.asset);
        }
      }
    });
  });

  test('the app is filed under the name pubspec.yaml gives it', () {
    final pubspec = loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;

    expect(kAppPackage, pubspec['name']);
  });

  test('the build carries the app, its packages and everything bundled', () async {
    // Flutter's own NOTICES, which is where the LICENSE at the repository root
    // ends up, and what the app adds beside it. Read from the bundle and not
    // from `LicenseRegistry`: the test binding registers no licences at all.
    final notices = utf8.decode(gzip.decode((await rootBundle.load('NOTICES.Z')).buffer.asUint8List()));

    final catalog = await LicenseCatalog.load(
      entries: Stream.fromIterable([
        for (final notice in parseNotices(notices)) LicenseEntryWithLineBreaks(notice.packages, notice.text),
        ...await bundledLicenseEntries(rootBundle).toList(),
      ]),
    );

    final app = catalog.of(LicenseOrigin.app).single;
    expect(app.name, kAppPackage);
    expect(app.texts.single, startsWith('Mozilla Public License Version 2.0'));

    expect(catalog.of(LicenseOrigin.packages).map((it) => it.name), containsAll(['flutter', 'mobx', 'auto_route']));
    expect(catalog.of(LicenseOrigin.python).map((it) => it.name), [
      'CPython',
      'iniconfig',
      'LLVM compiler-rt',
      'packaging',
      'pluggy',
      'Pygments',
      'pytest',
      'wasi-libc',
    ]);
    expect(catalog.of(LicenseOrigin.rust).map((it) => it.name), containsAll(['nusb', 'Rust standard library']));
    expect(catalog.of(LicenseOrigin.fonts), hasLength(4));

    // The VM image is not an asset, and only a build that ships it has one.
    for (final origin in LicenseOrigin.values.where((it) => it != LicenseOrigin.tkinter)) {
      expect(catalog.of(origin), isNotEmpty, reason: '$origin');
    }
  });

  group('the VM image', () {
    test('is one component, under its own origin, with its notices whole', () async {
      const notices = 'Notices for the Tkinter VM image\n\nv86\n===\n\n    Copyright (c) 2012';

      final catalog = await LicenseCatalog.load(entries: vmLicenseEntries(loadNotices: () async => notices));

      final component = catalog.of(LicenseOrigin.tkinter).single;
      expect(component.name, kVmImageComponent);
      expect(component.texts, [notices]);
    });

    test('notices that cannot be read fail the screen, not leave a gap in it', () async {
      final entries = vmLicenseEntries(loadNotices: () => Future.error(StateError('404 fetching NOTICES.txt')));

      await expectLater(LicenseCatalog.load(entries: entries), throwsStateError);
    });
  });
}
