import 'package:flutter/widgets.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:i_can_code/app_info.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/views/base/screen_view_base.dart';
import 'package:i_can_code/views/components/app_header.dart';
import 'package:i_can_code/views/components/app_header_publisher.dart';
import 'package:i_can_code/views/components/catalog_card.dart';
import 'package:i_can_code/views/subjects_screen/subjects_screen_controller.dart';
import 'package:i_can_code/views/subjects_screen/subjects_screen_view_model.dart';

class SubjectsScreenView extends ScreenViewBase<SubjectsScreenViewModel, SubjectsScreenController> {

  const SubjectsScreenView({required super.viewModel, required super.controller, required super.contextAccessor});

  @override
  Widget get body {
    // Home, so the trail is the app's own name and nothing else — and it does
    // not offer to navigate to the screen it is already on.
    return AppHeaderPublisher(
      // The one screen that names the version: it belongs to the app, and this
      // is the screen that is only the app.
      builder: (context) => AppHeaderConfig(version: appVersion),
      child: SingleChildScrollView(child: _buildContent()),
    );
  }

  Widget _buildContent() {
    return Builder(
      builder: (context) {
        final subjects = viewModel.course.subjects;

        return Padding(
          // The bar is over the page, not above it, so the first screenful
          // keeps clear of it here — and the rest scrolls under it.
          padding: const EdgeInsets.fromLTRB(32, AppHeader.height + 60, 32, 100),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    context.localizations.subjectsScreen_title,
                    style: context.appTheme.text.h1.copyWith(fontSize: 42),
                  ),
                  const SizedBox(height: 40),
                  for (final (index, subject) in subjects.indexed) ...[
                    if (index > 0) const SizedBox(height: CatalogCard.spacing),
                    // An Observer of its own rather than a Builder: a Builder's
                    // callback runs after the Observer above has stopped
                    // listening, so a reset left the count where it was.
                    Observer(
                      builder: (context) {
                        final lessons = viewModel.course.lessonsFor(subject);
                        final done = lessons.where(viewModel.progress.isFinished).length;

                        return CatalogCard(
                          // The subject's own initial, rather than its
                          // position in the list.
                          label: subjectLabel(subject).substring(0, 1),
                          emoji: subjectEmoji(subject),
                          title: subjectLabel(subject),
                          finished: done == lessons.length,
                          // The fraction from the first visit on, for the
                          // reason the catalog gives.
                          meta: context.localizations.subjectsScreen_progress(done, lessons.length),
                          onTap: () => controller.openSubject(subject),
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
