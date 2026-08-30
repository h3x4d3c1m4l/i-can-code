import 'package:auto_route/auto_route.dart';
import 'package:i_can_code/routing/app_router.gr.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/views/base/screen_controller_base.dart';
import 'package:i_can_code/views/languages_screen/languages_screen_view_model.dart';

class LanguagesScreenController extends ScreenControllerBase<LanguagesScreenViewModel> {

  LanguagesScreenController({required super.viewModel, required super.contextAccessor});

  /// Opens the lessons for [language].
  Future<void> openLanguage(String language) async {
    if (!contextAccessor.buildContext.mounted) return;
    await contextAccessor.buildContext.router.push(CatalogRoute(languageSlug: languageSlug(language)));
  }

}
