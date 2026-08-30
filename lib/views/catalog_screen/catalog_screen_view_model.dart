import 'package:get_it/get_it.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/progress/progress_store.dart';
import 'package:i_can_code/views/base/screen_view_model_base.dart';
import 'package:mobx/mobx.dart';

part 'catalog_screen_view_model.g.dart';

class CatalogScreenViewModel = CatalogScreenViewModelBase with _$CatalogScreenViewModel;

abstract class CatalogScreenViewModelBase extends ScreenViewModelBase with Store {

  /// The programming language whose lessons this catalog lists. Empty when the
  /// address named something that is not a language of ours.
  final String language;

  /// This language's lessons, read straight from the singleton the
  /// initialization screen registered — so this screen has no loading state.
  late final List<CourseLesson> lessons = GetIt.I<Course>().lessonsFor(language);

  /// Observed by the view, so a tick appears the moment a lesson is finished.
  final ProgressStore progress = GetIt.I<ProgressStore>();

  CatalogScreenViewModelBase({required super.contextAccessor, required String languageSlug})
    : language = languageFromSlug(languageSlug) ?? '';

}
