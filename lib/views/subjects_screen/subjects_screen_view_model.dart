import 'package:get_it/get_it.dart';
import 'package:i_can_code/services/feature_toggles.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/progress/progress_store.dart';
import 'package:i_can_code/views/base/screen_view_model_base.dart';
import 'package:mobx/mobx.dart';

part 'subjects_screen_view_model.g.dart';

class SubjectsScreenViewModel = SubjectsScreenViewModelBase with _$SubjectsScreenViewModel;

abstract class SubjectsScreenViewModelBase extends ScreenViewModelBase with Store {

  /// What the feature toggles let through of the singleton the initialization
  /// screen registered; the route guard guarantees it is there. A getter, so
  /// an observer that reads it follows the toggles.
  Course get course => visibleCourse;

  /// Observed by the view, so finishing a lesson updates this screen too.
  final ProgressStore progress = GetIt.I<ProgressStore>();

  SubjectsScreenViewModelBase({required super.contextAccessor});

}
