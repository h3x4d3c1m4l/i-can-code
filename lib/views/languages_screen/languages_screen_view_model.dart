import 'package:get_it/get_it.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/progress/progress_store.dart';
import 'package:i_can_code/views/base/screen_view_model_base.dart';
import 'package:mobx/mobx.dart';

part 'languages_screen_view_model.g.dart';

class LanguagesScreenViewModel = LanguagesScreenViewModelBase with _$LanguagesScreenViewModel;

abstract class LanguagesScreenViewModelBase extends ScreenViewModelBase with Store {

  /// Read straight from the singleton the initialization screen registered; the
  /// route guard guarantees it is there.
  final Course course = GetIt.I<Course>();

  /// Observed by the view, so finishing a lesson updates this screen too.
  final ProgressStore progress = GetIt.I<ProgressStore>();

  LanguagesScreenViewModelBase({required super.contextAccessor});

}
