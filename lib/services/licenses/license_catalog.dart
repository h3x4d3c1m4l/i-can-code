import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:i_can_code/app_info.dart';
import 'package:i_can_code/services/licenses/bundled_licenses.dart';

/// One thing the app ships, and every licence text that covers it.
class LicensedComponent {

  final LicenseOrigin origin;

  /// The package's own name. For [LicenseOrigin.app] it is [kAppPackage], which
  /// a screen SHOULD replace with the app's title.
  final String name;

  /// Never empty, and without duplicates.
  final List<String> texts;

  const LicensedComponent({required this.origin, required this.name, required this.texts});

}

/// Everything in [LicenseRegistry], regrouped from "a text and the packages it
/// covers" into "a package and the texts that cover it".
class LicenseCatalog {

  /// Sorted by [LicenseOrigin], then by name without regard to case.
  final List<LicensedComponent> components;

  const LicenseCatalog(this.components);

  /// The components of [origin], in order.
  Iterable<LicensedComponent> of(LicenseOrigin origin) => components.where((it) => it.origin == origin);

  /// Reads [entries], which is [LicenseRegistry.licenses] unless a test hands
  /// over its own.
  ///
  /// A package named [appPackage] is the app itself: Flutter files the `LICENSE`
  /// at the repository root under the package's name, beside its dependencies.
  /// Anything else out of NOTICES is a [LicenseOrigin.packages].
  static Future<LicenseCatalog> load({Stream<LicenseEntry>? entries, String appPackage = kAppPackage}) async {
    final texts = <(LicenseOrigin, String), Set<String>>{};

    void file(LicenseEntry entry) {
      final text = _textOf(entry);
      if (text.isEmpty) return;

      for (final package in entry.packages) {
        final origin = switch (entry) {
          _ when package == appPackage => LicenseOrigin.app,
          BundledLicenseEntry(:final origin) => origin,
          _ => LicenseOrigin.packages,
        };
        texts.putIfAbsent((origin, package), () => {}).add(text);
      }
    }

    // Read to the end and fail afterwards. Not `await for`, which cancels on
    // the first error: the registry's stream is then cancelled in the middle
    // of an `addStream`, and under a widget test's fake clock that cancel does
    // not complete, so a failure never reached the screen it was tested on.
    final done = Completer<void>();
    (Object, StackTrace)? failure;
    (entries ?? LicenseRegistry.licenses).listen(
      file,
      onError: (Object error, StackTrace stack) => failure ??= (error, stack),
      onDone: done.complete,
    );
    await done.future;
    if (failure case (final error, final stack)) Error.throwWithStackTrace(error, stack);

    final components = [
      for (final MapEntry(key: (origin, name), :value) in texts.entries)
        LicensedComponent(origin: origin, name: name, texts: List.unmodifiable(value)),
    ]..sort(_byOriginThenName);

    return LicenseCatalog(List.unmodifiable(components));
  }

  static int _byOriginThenName(LicensedComponent a, LicensedComponent b) {
    final byOrigin = a.origin.index.compareTo(b.origin.index);
    if (byOrigin != 0) return byOrigin;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  /// The text as its author wrote it, line breaks included.
  ///
  /// Not [LicenseEntry.paragraphs], which joins lines into paragraphs: that
  /// turns a table or a directory tree in a licence into one run of words.
  static String _textOf(LicenseEntry entry) {
    final text = switch (entry) {
      LicenseEntryWithLineBreaks(:final text) => text,
      // A plugin's own entry type has only paragraphs to offer.
      _ => entry.paragraphs.map((it) => '${'  ' * math.max(0, it.indent)}${it.text}').join('\n\n'),
    };
    // Blank lines only: the first line MAY be indented on purpose.
    return text.replaceFirst(RegExp(r'^(\s*\n)+'), '').trimRight();
  }

}
