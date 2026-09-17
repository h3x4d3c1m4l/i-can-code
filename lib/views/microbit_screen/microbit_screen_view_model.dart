import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/microbit/microbit_link.dart';
import 'package:i_can_code/views/base/screen_view_model_base.dart';
import 'package:mobx/mobx.dart';
import 'package:xterm/xterm.dart';

part 'microbit_screen_view_model.g.dart';

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

  /// This browser cannot do it at all: no WebUSB, or a page that is not
  /// cross-origin isolated.
  unavailable,

  /// Permission was granted but nothing came back, usually a charge-only cable.
  noDevice,

  /// Connecting or talking failed. `failureKind` says which.
  failed,

}

class MicrobitScreenViewModel = MicrobitScreenViewModelBase with _$MicrobitScreenViewModel;

abstract class MicrobitScreenViewModelBase extends ScreenViewModelBase with Store {

  /// How much of the session stays scrollable. Generous, because a student who
  /// printed a long list wants to scroll back to it.
  static const int _scrollback = 5000;

  /// The programming language this board belongs to. Empty when the address
  /// named something that is not a language of ours.
  final String language;

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

  MicrobitScreenViewModelBase({required super.contextAccessor, required String languageSlug})
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
  void setFailure(MicrobitFailure kind, String message) {
    _failureKind = kind;
    _failure = message;
    _boardInfo = null;
    _status = MicrobitStatus.failed;
  }

}
