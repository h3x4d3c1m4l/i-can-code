import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/views/base/screen_view_model_base.dart';
import 'package:i_can_code/views/components/code_editor/code_editing_controller.dart';
import 'package:mobx/mobx.dart';

part 'editor_settings_screen_view_model.g.dart';

class EditorSettingsScreenViewModel = EditorSettingsScreenViewModelBase with _$EditorSettingsScreenViewModel;

abstract class EditorSettingsScreenViewModelBase extends ScreenViewModelBase with Store {

  /// The code the machine runs before every program, on the Tkinter page and in
  /// a project on it. Not observable, like every editor's controller: it
  /// notifies its own listeners. Python whatever subject opened the screen, so
  /// it indents like Python.
  final CodeEditingController tkinterSetup = CodeEditingController(indentSize: subjectIndentSize('python'));

  EditorSettingsScreenViewModelBase({
    required super.contextAccessor,
  });

  @override
  void dispose() {
    tkinterSetup.dispose();
    super.dispose();
  }

}
