import 'package:flutter/widgets.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/views/base/screen_view_base.dart';
import 'package:i_can_code/views/components/app_header.dart';
import 'package:i_can_code/views/components/catalog_card.dart';
import 'package:i_can_code/views/languages_screen/languages_screen_controller.dart';
import 'package:i_can_code/views/languages_screen/languages_screen_view_model.dart';

class LanguagesScreenView extends ScreenViewBase<LanguagesScreenViewModel, LanguagesScreenController> {

  const LanguagesScreenView({required super.viewModel, required super.controller, required super.contextAccessor});

  @override
  Widget get body {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AppHeader(),
        Expanded(child: SingleChildScrollView(child: _buildContent())),
      ],
    );
  }

  Widget _buildContent() {
    return Observer(
      builder: (context) {
        final languages = viewModel.course.languages;

        return Padding(
          padding: const EdgeInsets.fromLTRB(32, 60, 32, 100),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    context.localizations.languagesScreen_title,
                    style: context.appTheme.text.h1.copyWith(fontSize: 42),
                  ),
                  const SizedBox(height: 40),
                  for (final (index, language) in languages.indexed) ...[
                    if (index > 0) const SizedBox(height: 16),
                    Builder(
                      builder: (context) {
                        final lessons = viewModel.course.lessonsFor(language);
                        final done = lessons.where(viewModel.progress.isFinished).length;

                        return CatalogCard(
                          // The language's own initial, rather than its
                          // position in the list.
                          label: languageLabel(language).substring(0, 1),
                          title: languageLabel(language),
                          finished: done == lessons.length,
                          meta: done == 0
                              ? context.localizations.languagesScreen_lessons(lessons.length)
                              : context.localizations.languagesScreen_progress(done, lessons.length),
                          onTap: () => controller.openLanguage(language),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

}
