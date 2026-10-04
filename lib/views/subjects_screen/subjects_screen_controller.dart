import 'package:auto_route/auto_route.dart';
import 'package:i_can_code/routing/app_router.gr.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/views/base/screen_controller_base.dart';
import 'package:i_can_code/views/subjects_screen/subjects_screen_view_model.dart';

class SubjectsScreenController extends ScreenControllerBase<SubjectsScreenViewModel> {

  SubjectsScreenController({required super.viewModel, required super.contextAccessor});

  /// Opens the lessons for [subject].
  Future<void> openSubject(String subject) async {
    if (!contextAccessor.buildContext.mounted) return;
    await contextAccessor.buildContext.router.push(CatalogRoute(subjectSlug: subjectSlug(subject)));
  }

}
