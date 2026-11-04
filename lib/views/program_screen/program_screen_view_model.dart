import 'dart:typed_data';

import 'package:get_it/get_it.dart';
import 'package:i_can_code/services/folder_store.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/views/base/screen_view_model_base.dart';
import 'package:mobx/mobx.dart';
import 'package:re_editor/re_editor.dart';
import 'package:xterm/xterm.dart';

part 'program_screen_view_model.g.dart';

enum ProgramStatus {

  /// Nothing is running. Run starts the program in the editor.
  idle,

  /// Run was pressed and the interpreter is on its way. Stop already works.
  starting,

  /// The program is running, and what is typed in the terminal goes to it.
  running,

  /// This browser cannot host one at all: the page is not cross-origin
  /// isolated, which a program that reads its input cannot do without.
  unavailable,
}

class ProgramScreenViewModel = ProgramScreenViewModelBase with _$ProgramScreenViewModel;

abstract class ProgramScreenViewModelBase extends ScreenViewModelBase with Store {

  /// What the editor holds the first time: a program that asks something and
  /// answers, which is what this page can do and a lesson's run cannot. Dutch,
  /// like the course it sits beside.
  static const String sample = '''
naam = input("Hoe heet je? ")
print(f"Hallo, {naam}!")
''';

  /// How much of a run stays scrollable, the console's own figure.
  static const int _scrollback = 5000;

  /// The subject this page belongs to. Empty when the address named something
  /// that is not a subject of ours.
  final String subject;

  /// The editor's text. Not observable, for the reason the Tkinter page gives:
  /// it notifies its own listeners. Owned here, and disposed with the page.
  final CodeLineEditingController code;

  /// The emulator the program writes to and reads from. Not observable, for
  /// the reason the console gives.
  final Terminal terminal = Terminal(maxLines: _scrollback);

  @readonly
  ProgramStatus _status = ProgramStatus.idle;

  /// What the loaded interpreter calls itself, once it has said so.
  @readonly
  String? _runtimeVersion;

  /// The folder this page shares with the console, which every run starts
  /// with. App-wide, so it outlives the page.
  final FolderStore folder;

  /// [folder] is for tests; the page finds the app's own.
  ProgramScreenViewModelBase({required super.contextAccessor, required String subjectSlug, FolderStore? folder})
    : subject = subjectFromSlug(subjectSlug) ?? '',
      folder = folder ?? GetIt.I<FolderStore>(),
      code = CodeLineEditingController.fromText(
        sample,
        CodeLineOptions(indentSize: subjectIndentSize(subjectFromSlug(subjectSlug) ?? '')),
      );

  /// The page `CodeDraftStore` keeps this page's program under.
  String get draftPage => 'program.$subject';

  /// This subject's files in [folder]. Tracked when an observer reads it.
  Map<String, Uint8List> get files => folder.filesOf(subject);

  /// Whether a program is on its way or running, which is when Run is Stop.
  bool get busy => _status == ProgramStatus.starting || _status == ProgramStatus.running;

  @action
  void setStatus(ProgramStatus status) => _status = status;

  @action
  void setRuntimeVersion(String? version) => _runtimeVersion = version;

  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

}
