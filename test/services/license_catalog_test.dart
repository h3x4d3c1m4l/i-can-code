import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_code/services/licenses/bundled_licenses.dart';
import 'package:i_can_code/services/licenses/license_catalog.dart';

Future<LicenseCatalog> _load(List<LicenseEntry> entries) =>
    LicenseCatalog.load(entries: Stream.fromIterable(entries), appPackage: 'the_app');

void main() {
  test('a package is filed by where its entry came from', () async {
    final catalog = await _load(const [
      LicenseEntryWithLineBreaks(['the_app'], 'The app.'),
      LicenseEntryWithLineBreaks(['some_package'], 'A package.'),
      BundledLicenseEntry(LicenseOrigin.rust, ['some_crate'], 'A crate.'),
    ]);

    expect(catalog.components.map((it) => (it.origin, it.name)), [
      (LicenseOrigin.app, 'the_app'),
      (LicenseOrigin.rust, 'some_crate'),
      (LicenseOrigin.packages, 'some_package'),
    ]);
  });

  test('a text shared with the app does not make the app of its neighbour', () async {
    // Flutter folds packages with the same text into one entry, so the app can
    // turn up in a list of names.
    final catalog = await _load(const [
      LicenseEntryWithLineBreaks(['other_package', 'the_app'], 'Shared.'),
    ]);

    expect(catalog.of(LicenseOrigin.app).single.name, 'the_app');
    expect(catalog.of(LicenseOrigin.packages).single.name, 'other_package');
  });

  test('a package gathers every text that names it, once each', () async {
    final catalog = await _load(const [
      BundledLicenseEntry(LicenseOrigin.python, ['libc'], 'Summary.'),
      BundledLicenseEntry(LicenseOrigin.python, ['libc'], 'MIT.'),
      BundledLicenseEntry(LicenseOrigin.python, ['libc', 'other'], 'MIT.'),
    ]);

    expect(catalog.components.firstWhere((it) => it.name == 'libc').texts, ['Summary.', 'MIT.']);
    expect(catalog.components.firstWhere((it) => it.name == 'other').texts, ['MIT.']);
  });

  test('one origin is in order of name, whatever the case', () async {
    final catalog = await _load(const [
      LicenseEntryWithLineBreaks(['zebra'], 'Z.'),
      LicenseEntryWithLineBreaks(['Apple'], 'A.'),
      LicenseEntryWithLineBreaks(['mango'], 'M.'),
    ]);

    expect(catalog.components.map((it) => it.name), ['Apple', 'mango', 'zebra']);
  });

  test('a text keeps its lines and its first indent, and loses the blank lines around it', () async {
    final catalog = await _load(const [
      LicenseEntryWithLineBreaks(['apache'], '\n\n        Apache License\n   Version 2.0\n\n'),
    ]);

    expect(catalog.components.single.texts.single, '        Apache License\n   Version 2.0');
  });

  test('an entry of another kind is read from its paragraphs', () async {
    final catalog = await _load([_ParagraphsOnly()]);

    expect(catalog.components.single.texts.single, 'First.\n\n  Indented.');
  });
}

/// What a plugin MAY register: a [LicenseEntry] that is not Flutter's own.
class _ParagraphsOnly extends LicenseEntry {

  @override
  Iterable<String> get packages => const ['plugin'];

  @override
  Iterable<LicenseParagraph> get paragraphs => const [LicenseParagraph('First.', 0), LicenseParagraph('Indented.', 1)];

}
