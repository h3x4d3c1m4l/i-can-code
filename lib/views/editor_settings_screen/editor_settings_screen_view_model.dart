import 'package:i_can_code/views/base/screen_view_model_base.dart';
import 'package:mobx/mobx.dart';
import 'package:re_editor/re_editor.dart';

part 'editor_settings_screen_view_model.g.dart';

class EditorSettingsScreenViewModel = EditorSettingsScreenViewModelBase with _$EditorSettingsScreenViewModel;

abstract class EditorSettingsScreenViewModelBase extends ScreenViewModelBase with Store {

  /// The code the Tkinter page runs before every program. Not observable, like
  /// every editor's controller: it notifies its own listeners.
  final CodeLineEditingController tkinterSetup = CodeLineEditingController();

  EditorSettingsScreenViewModelBase({
    required super.contextAccessor,
  });

  @override
  void dispose() {
    tkinterSetup.dispose();
    super.dispose();
  }

}
