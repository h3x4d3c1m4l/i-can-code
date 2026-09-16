import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/views/base/screen_view_model_base.dart';
import 'package:mobx/mobx.dart';
import 'package:xterm/xterm.dart';

part 'repl_screen_view_model.g.dart';

/// Where the session is. Not the interpreter's own idea of itself — it has none
/// past "running" — but what the screen has to show around it.
enum ReplStatus {

  /// The worker is compiling CPython. Nothing is on the terminal yet.
  starting,

  /// A prompt is up. Whether it is waiting or busy is the REPL's business, not
  /// this screen's.
  running,

  /// `exit()`, or Ctrl-D. The terminal keeps what was on it; only Restart gets
  /// a new interpreter.
  exited,

  /// This browser cannot host one at all.
  unavailable,

  /// The harness broke. Distinct from [exited], which is the session ending the
  /// way it is supposed to.
  failed,
}

class ReplScreenViewModel = ReplScreenViewModelBase with _$ReplScreenViewModel;

abstract class ReplScreenViewModelBase extends ScreenViewModelBase with Store {

  /// How much of the session stays scrollable. Generous, because a student who
  /// printed a long list wants to scroll back to it, and cheap, because a line
  /// is a line of characters.
  static const int _scrollback = 5000;

  /// The programming language this console runs. Empty when the address named
  /// something that is not a language of ours.
  final String language;

  /// The emulator itself, which the view hands to a `TerminalView`.
  ///
  /// Not observable, and deliberately so: it keeps its own state and notifies
  /// its own listeners, and wrapping thousands of screen cells in a MobX
  /// observable would rebuild the whole screen on every character.
  final Terminal terminal = Terminal(maxLines: _scrollback);

  @readonly
  ReplStatus _status = ReplStatus.starting;

  /// What broke, for [ReplStatus.failed]. Untranslated — it comes from the
  /// worker and is for whoever is looking at the console, not for the student.
  @readonly
  String? _failure;

  ReplScreenViewModelBase({required super.contextAccessor, required String languageSlug})
    : language = languageFromSlug(languageSlug) ?? '';

  @action
  void setStatus(ReplStatus status) => _status = status;

  @action
  void setFailure(String message) {
    _failure = message;
    _status = ReplStatus.failed;
  }

}
