import 'package:flutter/widgets.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/views/base/screen_view_base.dart';
import 'package:i_can_code/views/catalog_screen/catalog_screen_controller.dart';
import 'package:i_can_code/views/catalog_screen/catalog_screen_view_model.dart';
import 'package:i_can_code/views/components/app_header.dart';
import 'package:i_can_code/views/components/app_header_publisher.dart';
import 'package:i_can_code/views/components/catalog_card.dart';

class CatalogScreenView extends ScreenViewBase<CatalogScreenViewModel, CatalogScreenController> {

  const CatalogScreenView({required super.viewModel, required super.controller, required super.contextAccessor});

  @override
  Widget get body {
    return AppHeaderPublisher(
      builder: (context) => AppHeaderConfig(
        onTapHome: controller.goHome,
        crumbs: [AppCrumb(languageLabel(viewModel.language))],
      ),
      child: SingleChildScrollView(child: _buildContent()),
    );
  }

  Widget _buildContent() {
    return Observer(
      builder: (context) {
        final locale = Localizations.localeOf(context).languageCode;
        final lessons = viewModel.lessons;

        return Padding(
          // Clear of the bar on the first screenful, and under it after that.
          padding: const EdgeInsets.fromLTRB(32, AppHeader.height + 60, 32, 100),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    languageLabel(viewModel.language),
                    style: context.appTheme.text.h1.copyWith(fontSize: 42),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.localizations.catalogScreen_title,
                    style: context.appTheme.text.body.copyWith(
                      fontSize: 19,
                      color: context.theme.colors.mutedForeground,
                    ),
                  ),
                  const SizedBox(height: 40),
                  for (final (index, courseLesson) in lessons.indexed) ...[
                    if (index > 0) const SizedBox(height: 16),
                    Builder(
                      builder: (context) {
                        final lesson = courseLesson.forLocale(locale);
                        final progress = viewModel.progress;
                        final done = progress.completedSteps(courseLesson);

                        return CatalogCard(
                          label: '${courseLesson.entry.order}',
                          emoji: lesson.emoji,
                          title: lesson.title,
                          subtitle: lesson.subtitle,
                          finished: progress.isFinished(courseLesson),
                          // How far in, from the first visit on. A lesson not
                          // started reads "0 / 5" rather than "5 stappen", so
                          // the number in this position never changes meaning
                          // between one row and the next. Finished: the card
                          // shows a tick instead.
                          meta: context.localizations.catalogScreen_progress(done, lesson.stepCount),
                          onTap: () => controller.openLesson(courseLesson),
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
