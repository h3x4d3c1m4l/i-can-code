// Only a browser has the file to fetch. Everything else, the Dart VM a
// `flutter test` runs on included, falls through to the stub.
//
// A conditional import resolves the URI of whichever clause matches, so a clause
// MUST NOT be added before the file it names exists: on the VM the missing file
// would be a compile error for every test that reaches this library.
import 'package:i_can_code/services/rustc_version/rustc_version_stub.dart'
    if (dart.library.js_interop) 'package:i_can_code/services/rustc_version/rustc_version_web.dart'
    as impl;

/// What `rustc -V` printed for the toolchain that built the Rust core, such as
/// "rustc 1.93.0-nightly (1a2b3c4d5 2026-09-15)", or null when this build does
/// not say.
///
/// `just build-rust-core` writes it beside the wasm, so asking does not load the
/// core. Never throws: a build made before that recipe wrote it, or one served
/// from `flutter run` without it, answers null.
Future<String?> loadRustcVersion() => impl.loadRustcVersion();
