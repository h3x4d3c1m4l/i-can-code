import 'package:get_it/get_it.dart';
import 'package:i_can_code/services/feature_toggles.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/progress/code_draft_store.dart';
import 'package:i_can_code/services/progress/progress_store.dart';
import 'package:i_can_code/views/base/screen_view_model_base.dart';
import 'package:mobx/mobx.dart';

part 'catalog_screen_view_model.g.dart';

class CatalogScreenViewModel = CatalogScreenViewModelBase with _$CatalogScreenViewModel;

abstract class CatalogScreenViewModelBase extends ScreenViewModelBase with Store {

  /// The subject whose lessons this catalog lists. Empty when the
  /// address named something that is not a subject of ours.
  final String subject;

  /// This subject's lessons as the feature toggles let them through, read
  /// straight from the singleton the initialization screen registered — so this
  /// screen has no loading state. A getter, so an observer that reads it
  /// follows the toggles.
  List<CourseLesson> get lessons => visibleCourse.lessonsFor(subject);

  /// Observed by the view, so a tick appears the moment a lesson is finished.
  final ProgressStore progress = GetIt.I<ProgressStore>();

  /// Read so a lesson's menu knows whether there is code to forget.
  final CodeDraftStore drafts = GetIt.I<CodeDraftStore>();

  CatalogScreenViewModelBase({required super.contextAccessor, required String subjectSlug})
    : subject = subjectFromSlug(subjectSlug) ?? '';

}
