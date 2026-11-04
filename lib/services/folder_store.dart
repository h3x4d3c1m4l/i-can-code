import 'dart:collection';
import 'dart:typed_data';

import 'package:mobx/mobx.dart';

part 'folder_store.g.dart';

/// Names in the interpreter's root that are the app's and not the student's:
/// the standard library, `/tmp`, `/dev` and the program itself. A student's
/// file MUST NOT take one. `NOT_THE_FOLDER` in
/// `web/python/python_repl_worker.js` MUST name the same, because that is what
/// leaves them out of what the worker reports.
const Set<String> kReservedFolderNames = {'lib', 'tmp', 'dev', 'main.py'};

/// Why a name cannot be given to a file the student types.
enum FolderNameProblem {

  empty,

  /// It holds a `/`, which would put the file in a directory.
  slash,

  /// One of [kReservedFolderNames], or `.` or `..`.
  reserved,

  /// Another file in the folder has it.
  taken,

  tooLong,
}

class FolderStore = FolderStoreBase with _$FolderStore;

/// The files the console and the program page share: one folder per subject,
/// for as long as the tab is open.
///
/// Every run on the program page starts with its subject's folder, and every
/// console starts with it and is kept up to date while it runs. What the
/// interpreter writes comes back here (`ReplFiles`), so a file a program wrote
/// is there for the next run, as it would be on a disk.
///
/// **Not persisted**, on purpose: a reload empties it. Nothing a student typed
/// stays behind in the browser, and there is no storage quota to share with
/// progress and drafts. "Voortgang wissen" therefore has nothing to clear here.
abstract class FolderStoreBase with Store {

  /// The largest file the student can type or change by hand. Larger ones,
  /// which only a program can make, are shown and not edited.
  static const int maxEditableBytes = 256 * 1024;

  /// The longest name a typed file can have, in characters.
  static const int maxNameLength = 100;

  final ObservableMap<String, ObservableMap<String, Uint8List>> _folders = ObservableMap();

  /// [subject]'s files, by path relative to the interpreter's root, in the
  /// order they arrived. Tracked when an observer reads it.
  ///
  /// A view, and a live one: it may be held, and it finds the folder again on
  /// every read, so it sees a folder that did not exist yet when it was taken.
  Map<String, Uint8List> filesOf(String subject) => _FolderView(_folders, subject);

  /// Why [name] cannot be given to a typed file in [subject]'s folder, or null
  /// when it can. [current] is the file being renamed, which may keep its own
  /// name even where a new file could not have it.
  FolderNameProblem? problemWith(String subject, String name, {String? current}) {
    if (name == current) return null;
    if (name.trim().isEmpty) return FolderNameProblem.empty;
    if (name.contains('/') || name.contains(r'\')) return FolderNameProblem.slash;
    if (name == '.' || name == '..' || kReservedFolderNames.contains(name)) return FolderNameProblem.reserved;
    if (name.length > maxNameLength) return FolderNameProblem.tooLong;
    if (_folders[subject]?.containsKey(name) ?? false) return FolderNameProblem.taken;
    return null;
  }

  /// Puts [bytes] at [path], in place of what is there. A file that is
  /// replaced keeps its place in the order.
  @action
  void put(String subject, String path, Uint8List bytes) => _folderOf(subject)[path] = bytes;

  @action
  void remove(String subject, String path) => _folders[subject]?.remove(path);

  /// What the interpreter reported, in one go.
  @action
  void apply(String subject, {required Map<String, Uint8List> changed, required Iterable<String> removed}) {
    final folder = _folderOf(subject);
    removed.forEach(folder.remove);
    folder.addAll(changed);
  }

  ObservableMap<String, Uint8List> _folderOf(String subject) => _folders.putIfAbsent(subject, ObservableMap.new);

}

/// One subject's folder, looked up on every read rather than once.
class _FolderView extends UnmodifiableMapBase<String, Uint8List> {

  final ObservableMap<String, ObservableMap<String, Uint8List>> _folders;
  final String _subject;

  _FolderView(this._folders, this._subject);

  Map<String, Uint8List> get _folder => _folders[_subject] ?? const {};

  @override
  Uint8List? operator [](Object? key) => _folder[key];

  @override
  Iterable<String> get keys => _folder.keys;

  @override
  int get length => _folder.length;

}
