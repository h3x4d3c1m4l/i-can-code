import 'package:i_can_code/views/base/screen_view_model_base.dart';
import 'package:mobx/mobx.dart';

part 'about_screen_view_model.g.dart';

class AboutScreenViewModel = AboutScreenViewModelBase with _$AboutScreenViewModel;

/// The versions that have to be asked for. Everything else on the screen is
/// known when the build is made.
abstract class AboutScreenViewModelBase extends ScreenViewModelBase with Store {

  /// What `rustc -V` printed for the toolchain that built the Rust core.
  @readonly
  String? _rustc;

  /// Whether asking for [rustc] has finished, so that null there reads as
  /// "unknown" rather than as "still loading".
  @readonly
  bool _rustcLoaded = false;

  /// What the interpreter in the page calls itself.
  @readonly
  String? _python;

  /// Whether the interpreter has finished loading, or failed to.
  @readonly
  bool _pythonLoaded = false;

  /// The interpreter behind the Tkinter page, as the VM image's manifest names
  /// it.
  @readonly
  String? _tkinter;

  /// Whether reading the manifest has finished, or failed to.
  @readonly
  bool _tkinterLoaded = false;

  AboutScreenViewModelBase({required super.contextAccessor});

  @action
  void setRustc(String? version) {
    _rustc = version;
    _rustcLoaded = true;
  }

  @action
  void setPython(String? version) {
    _python = version;
    _pythonLoaded = true;
  }

  @action
  void setTkinter(String? version) {
    _tkinter = version;
    _tkinterLoaded = true;
  }

}
