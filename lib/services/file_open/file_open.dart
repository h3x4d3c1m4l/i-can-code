import 'dart:convert';

import 'package:file_picker/file_picker.dart';

/// Asks the reader for a file ending in one of [extensions] and reads it as
/// UTF-8 text. Completes with null when they cancel.
///
/// Throws a [FormatException] when the file is larger than [maxBytes] or is not
/// UTF-8. A byte order mark is dropped, which an editor on Windows may add.
Future<String?> openTextFile({required List<String> extensions, required int maxBytes}) async {
  final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: extensions);
  if (file == null) return null;

  final length = file.lengthSync() ?? await file.length();
  if (length == null || length > maxBytes) throw FormatException('Larger than $maxBytes bytes', file.name);

  final text = utf8.decode(await file.readAsBytes());
  return text.startsWith('\uFEFF') ? text.substring(1) : text;
}
