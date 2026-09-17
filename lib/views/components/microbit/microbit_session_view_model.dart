import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/microbit/microbit_link.dart';
import 'package:i_can_code/views/base/screen_view_model_base.dart';
import 'package:mobx/mobx.dart';
import 'package:re_editor/re_editor.dart';
import 'package:xterm/xterm.dart';

part 'microbit_session_view_model.g.dart';

/// Where the connection is, as the screen has to show it. The board has no idea
/// it is connected.
enum MicrobitStatus {

  /// Nothing has been asked for yet. WebUSB only offers its picker inside a
  /// user gesture, so the reader has to press Connect.
  disconnected,

  /// The picker is open, or the session is opening the board.
  connecting,

  /// A board is open and answering.
  connected,

  /// A program is being written to the board.
  flashing,

  /// This browser cannot do it at all: no WebUSB, or a page that is not
  /// cross-origin isolated.
  unavailable,

  /// Permission was granted but nothing came back, usually a charge-only cable.
  noDevice,

  /// Connecting or talking failed. `failureKind` says which.
  failed,

}

class MicrobitSessionViewModel = MicrobitSessionViewModelBase with _$MicrobitSessionViewModel;

abstract class MicrobitSessionViewModelBase extends ScreenViewModelBase with Store {

  /// How much of the session stays scrollable. Generous, because a student who
  /// printed a long list wants to scroll back to it.
  static const int _scrollback = 5000;

  /// The programming language this board belongs to. Empty when the address
  /// named something that is not a language of ours.
  final String language;

  /// What the reader is about to flash.
  ///
  /// Not observable, like the terminal: it keeps its own state and notifies its
  /// own listeners, and a MobX observable over every keystroke would rebuild the
  /// screen on each one.
  final CodeLineEditingController code = CodeLineEditingController.fromText(
    'from microbit import *\n\ndisplay.scroll("Hello")\n',
  );

  /// The emulator the view hands to a `TerminalView`.
  ///
  /// Not observable: it notifies its own listeners, and a MobX observable over
  /// thousands of cells would rebuild the screen on every character.
  final Terminal terminal = Terminal(maxLines: _scrollback);

  @readonly
  MicrobitStatus _status = MicrobitStatus.disconnected;

  /// The boards this origin can see. A classroom machine may have two plugged
  /// in, and the screen says so rather than silently picking.
  @readonly
  List<MicrobitDevice> _devices = const [];

  /// What the open board answered about itself.
  @readonly
  MicrobitBoardInfo? _boardInfo;

  /// Which failure, for [MicrobitStatus.failed]. Picks the sentence the screen
  /// shows.
  @readonly
  MicrobitFailure? _failureKind;

  /// What broke, untranslated. For whoever is looking, not for the student.
  @readonly
  String? _failure;

  /// How far the flash has got, between 0 and 1.
  @readonly
  double _flashProgress = 0;

  /// How many of the board's pages the program being written would change, and
  /// how many it has. Null until the board has been asked, which a flash does
  /// before it writes anything.
  @readonly
  ({int changed, int total})? _flashPlan;

  /// Why the board could not be asked, for whoever is debugging. Null unless the
  /// last flash asked and got nowhere.
  @readonly
  String? _flashPlanFailure;

  MicrobitSessionViewModelBase({required super.contextAccessor, required String languageSlug})
    : language = languageFromSlug(languageSlug) ?? '';

  @action
  void setStatus(MicrobitStatus status) => _status = status;

  @action
  void setDevices(List<MicrobitDevice> devices) => _devices = devices;

  @action
  void setConnected(MicrobitBoardInfo info) {
    _boardInfo = info;
    _failureKind = null;
    _failure = null;
    _status = MicrobitStatus.connected;
  }

  /// The board is gone.
  @action
  void setDisconnected() {
    _boardInfo = null;
    _status = MicrobitStatus.disconnected;
  }

  @action
  void setFlashing(double fraction) {
    _flashProgress = fraction;
    _status = MicrobitStatus.flashing;
  }

  @action
  void setFlashPlan(int changed, int total) {
    _flashPlan = (changed: changed, total: total);
    _flashPlanFailure = null;
  }

  @action
  void setFlashPlanUnknown(String message) {
    _flashPlan = null;
    _flashPlanFailure = message;
  }

  @action
  void clearFlashPlan() {
    _flashPlan = null;
    _flashPlanFailure = null;
  }

  /// The board is written and back on its feet.
  @action
  void setFlashed() {
    _flashProgress = 1;
    _status = MicrobitStatus.connected;
  }

  @action
  void setFailure(MicrobitFailure kind, String message) {
    _failureKind = kind;
    _failure = message;
    _boardInfo = null;
    _status = MicrobitStatus.failed;
  }

}
