// Only a browser can hand the reader a file to save. Everything else, the Dart
// VM a `flutter test` runs on included, falls through to the stub.
//
// A conditional import resolves the URI of whichever clause matches, so a clause
// MUST NOT be added before the file it names exists: on the VM the missing file
// would be a compile error for every test that reaches this library.
import 'package:i_can_code/services/file_download/file_download_stub.dart'
    if (dart.library.js_interop) 'package:i_can_code/services/file_download/file_download_web.dart'
    as impl;

/// Whether [downloadTextFile] does anything here. A control that offers it
/// SHOULD be left out where it does not.
bool get canDownloadFiles => impl.canDownloadFiles;

/// Offers [text] to the reader as a UTF-8 file called [name], the way a link to
/// a file would.
void downloadTextFile(String name, String text) => impl.downloadTextFile(name, text);
