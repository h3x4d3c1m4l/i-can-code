import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Where something the app ships comes from, which is how the licence screen
/// groups what it lists. Declared in the order the screen shows them.
enum LicenseOrigin {

  /// The app's own code, under the `LICENSE` at the repository root.
  app,

  /// The interpreter a student's code runs on, and what it is linked against.
  python,

  /// The Rust core's crates, and the standard library compiled in with them.
  rust,

  /// The firmware a program is written to a board on top of.
  microbit,

  fonts,

  /// Vendored files that belong to none of the above.
  other,

  /// Every Dart package and the Flutter engine. Flutter collects these itself.
  packages,
}

/// A licence text the app ships as an asset, for something Flutter's own
/// NOTICES does not cover: it only knows the pub packages and the engine.
class BundledLicense {

  final LicenseOrigin origin;

  /// The asset holding the text. MUST be declared in `pubspec.yaml`.
  final String asset;

  /// What the whole file is the licence of.
  ///
  /// Empty for a file in the NOTICES format, which names the packages of each
  /// of its texts itself. See [parseNotices].
  final List<String> packages;

  const BundledLicense(this.origin, this.asset, this.packages);

  const BundledLicense.notices(this.origin, this.asset) : packages = const [];

}

/// Everything [registerBundledLicenses] adds. `docs/licenses.md` says where
/// each file comes from and what rewrites it.
///
/// Several files MAY name one package: it is then covered by all of them.
const List<BundledLicense> kBundledLicenses = [
  BundledLicense(LicenseOrigin.python, 'assets/python/licenses/cpython.txt', ['CPython']),
  BundledLicense(LicenseOrigin.python, 'assets/python/licenses/cpython-incorporated.txt', ['CPython']),
  BundledLicense(LicenseOrigin.python, 'assets/python/licenses/wasi-libc.txt', ['wasi-libc']),
  BundledLicense(LicenseOrigin.python, 'assets/python/licenses/wasi-libc-apache-llvm.txt', ['wasi-libc']),
  BundledLicense(LicenseOrigin.python, 'assets/python/licenses/wasi-libc-apache.txt', ['wasi-libc']),
  BundledLicense(LicenseOrigin.python, 'assets/python/licenses/wasi-libc-mit.txt', ['wasi-libc']),
  BundledLicense(LicenseOrigin.python, 'assets/python/licenses/wasi-libc-musl.txt', ['wasi-libc']),
  BundledLicense(LicenseOrigin.python, 'assets/python/licenses/wasi-libc-cloudlibc.txt', ['wasi-libc']),
  BundledLicense(LicenseOrigin.python, 'assets/python/licenses/compiler-rt.txt', ['LLVM compiler-rt']),

  BundledLicense.notices(LicenseOrigin.rust, 'assets/licenses/rust-crates.txt'),
  BundledLicense(LicenseOrigin.rust, 'assets/licenses/rust-COPYRIGHT.txt', ['Rust standard library']),
  BundledLicense(LicenseOrigin.rust, 'assets/licenses/rust-LICENSE-MIT.txt', ['Rust standard library']),
  BundledLicense(LicenseOrigin.rust, 'assets/licenses/rust-LICENSE-APACHE.txt', ['Rust standard library']),

  BundledLicense(LicenseOrigin.microbit, 'assets/microbit/licenses/micropython-microbit-v2.txt', [
    'micropython-microbit-v2',
  ]),
  BundledLicense(LicenseOrigin.microbit, 'assets/microbit/licenses/micropython.txt', ['MicroPython']),
  BundledLicense(LicenseOrigin.microbit, 'assets/microbit/licenses/codal.txt', [
    'codal-core',
    'codal-microbit-v2',
    'codal-nrf52',
  ]),
  BundledLicense(LicenseOrigin.microbit, 'assets/microbit/licenses/codal-microbit-nrf5sdk.txt', [
    'codal-microbit-nrf5sdk',
  ]),

  BundledLicense(LicenseOrigin.fonts, 'assets/fonts/OFL-Fredoka.txt', ['Fredoka']),
  BundledLicense(LicenseOrigin.fonts, 'assets/fonts/OFL-Lexend.txt', ['Lexend']),
  BundledLicense(LicenseOrigin.fonts, 'assets/fonts/OFL-JetBrainsMono.txt', ['JetBrains Mono']),
  BundledLicense(LicenseOrigin.fonts, 'assets/fonts/OFL-NotoColorEmoji.txt', ['Noto Color Emoji']),

  BundledLicense(LicenseOrigin.other, 'assets/licenses/coi-serviceworker.txt', ['coi-serviceworker']),
];

/// A [LicenseEntry] that also says where its packages come from.
///
/// The entries Flutter reads from NOTICES carry no such thing, which is how the
/// licence screen tells the two apart.
class BundledLicenseEntry extends LicenseEntryWithLineBreaks {

  final LicenseOrigin origin;

  const BundledLicenseEntry(this.origin, super.packages, super.text);

}

/// What separates two texts in a NOTICES file. Flutter's own, restated because
/// the tool that writes it is not part of the framework.
final String _noticesSeparator = '\n${'-' * 80}\n';

/// Splits [notices] into its texts and the packages each one covers.
///
/// The format is the one Flutter writes its own NOTICES in: the package names,
/// one per line, a blank line, the text, and a line of 80 hyphens between two
/// of them. Blank lines around a block are skipped, so files MAY be joined end
/// to end.
///
/// Throws a [FormatException] on a block with no names, which is what a text
/// holding a line of 80 hyphens of its own turns into.
Iterable<({List<String> packages, String text})> parseNotices(String notices) sync* {
  for (final raw in notices.split(_noticesSeparator)) {
    // Not `trim()`: a text MAY open with an indented line, a centred title.
    final block = raw.replaceFirst(RegExp(r'^\n+'), '');
    if (block.trim().isEmpty) continue;

    final split = block.indexOf('\n\n');
    if (split <= 0) throw FormatException('A licence without package names', block);

    yield (packages: block.substring(0, split).split('\n'), text: block.substring(split + 2));
  }
}

/// Reads every one of [licenses] out of [bundle].
///
/// A file that cannot be read is an error on the stream, not a gap in it: a
/// licence left out without anyone noticing is worse than a screen that says it
/// could not load.
Stream<LicenseEntry> bundledLicenseEntries(
  AssetBundle bundle, {
  List<BundledLicense> licenses = kBundledLicenses,
}) async* {
  for (final license in licenses) {
    final text = await bundle.loadString(license.asset, cache: false);

    if (license.packages.isNotEmpty) {
      yield BundledLicenseEntry(license.origin, license.packages, text);
    } else {
      for (final notice in parseNotices(text)) {
        yield BundledLicenseEntry(license.origin, notice.packages, notice.text);
      }
    }
  }
}

/// Adds [kBundledLicenses] to Flutter's [LicenseRegistry], beside the NOTICES
/// the framework registers itself.
///
/// Does no I/O: the registry calls back the first time something listens to
/// [LicenseRegistry.licenses], and the assets are read then.
void registerBundledLicenses() {
  LicenseRegistry.addLicense(() => bundledLicenseEntries(rootBundle));
}
