import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/views/base/screen_view_base.dart';
import 'package:i_can_code/views/catalog_screen/catalog_screen_controller.dart';
import 'package:i_can_code/views/catalog_screen/catalog_screen_view_model.dart';
import 'package:i_can_code/views/catalog_screen/components/bar_clearance_sliver.dart';
import 'package:i_can_code/views/catalog_screen/components/sticky_group_heading.dart';
import 'package:i_can_code/views/catalog_screen/lesson_runs.dart';
import 'package:i_can_code/views/components/app_header.dart';
import 'package:i_can_code/views/components/app_header_publisher.dart';
import 'package:i_can_code/views/components/catalog_card.dart';
import 'package:i_can_code/views/components/hint_mark.dart';

class CatalogScreenView extends ScreenViewBase<CatalogScreenViewModel, CatalogScreenController> {

  /// The widest the column of cards gets. Past it, the column is centred.
  static const double _maxWidth = 820;
  static const double _gutter = 32;

  /// Between the page's title and the first run, and between a run and the
  /// heading of the next. More than one card sits from the next, so the gap
  /// itself says where one group ends.
  static const double _runGap = 40;

  const CatalogScreenView({required super.viewModel, required super.controller, required super.contextAccessor});

  @override
  Widget get body {
    return AppHeaderPublisher(
      builder: (context) => AppHeaderConfig(
        onTapHome: controller.goHome,
        crumbs: [AppCrumb(languageLabel(viewModel.language))],
      ),
      child: _buildContent(),
    );
  }

  /// Everything this language offers beside the course itself.
  ///
  /// Under its own heading on purpose: the cards above are a path with progress
  /// on it, and this is not part of that path. Nothing here is checked and
  /// nothing is recorded.
  Widget _buildExtra(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 48),
        Text(context.localizations.catalogScreen_extra, style: context.appTheme.text.h2),
        const SizedBox(height: 16),
        if (languageHasRepl(viewModel.language))
          CatalogCard(
            // A prompt, in the code face the tile already uses. The lessons above
            // are numbered and this is not one of them, so it does not get a
            // number.
            label: '>_',
            title: context.localizations.replScreen_title(languageLabel(viewModel.language)),
            subtitle: context.localizations.replScreen_subtitle,
            meta: context.localizations.catalogScreen_extraFreePlay,
            onTap: controller.openRepl,
          ),
        if (languageHasRepl(viewModel.language) && languageHasMicrobit(viewModel.language))
          const SizedBox(height: CatalogCard.spacing),
        if (languageHasMicrobit(viewModel.language)) ...[
          CatalogCard(
            // What the board is for: a program of your own, written here and
            // run there. Not a number, and not a prompt.
            label: '⚡',
            title: context.localizations.microbitProgramScreen_title,
            subtitle: context.localizations.microbitProgramScreen_subtitle,
            meta: context.localizations.catalogScreen_extraHardware,
            onTap: controller.openMicrobitProgram,
          ),
          const SizedBox(height: CatalogCard.spacing),
          CatalogCard(
            // A prompt again, but this one leaves the browser.
            label: '🔌',
            title: context.localizations.microbitReplScreen_title(languageLabel(viewModel.language)),
            subtitle: context.localizations.microbitReplScreen_subtitle,
            meta: context.localizations.catalogScreen_extraHardware,
            onTap: controller.openMicrobitRepl,
          ),
        ],
      ],
    );
  }

  /// One row of the course, for whichever run it belongs to.
  ///
  /// An [Observer] of its own, because a sliver list builds its rows during
  /// layout, after the screen's own build has stopped listening. A tick would
  /// then wait for the next visit.
  Widget _buildLessonCard(CourseLesson courseLesson, String locale) {
    return Observer(
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
          // How far in, from the first visit on. A lesson not started reads
          // "0 / 5" rather than "5 stappen", so the number in this position
          // never changes meaning between one row and the next. Finished: the
          // card shows a tick instead.
          meta: context.localizations.catalogScreen_progress(done, lesson.stepCount),
          onTap: () => controller.openLesson(courseLesson),
        );
      },
    );
  }

  /// One run of the course as slivers. A run with a group opens with its
  /// heading, which sticks under the bar while the run's lessons pass under it.
  List<Widget> _buildRun(({String? key, List<CourseLesson> items}) run, String locale, {required bool first}) {
    final cards = SliverList.separated(
      itemCount: run.items.length,
      itemBuilder: (_, position) => _buildLessonCard(run.items[position], locale),
      separatorBuilder: (_, _) => const SizedBox(height: CatalogCard.spacing),
    );

    return switch (run.key) {
      final String group => [
        const SliverToBoxAdapter(child: SizedBox(height: _runGap - StickyGroupHeading.topGap)),
        SliverMainAxisGroup(slivers: [StickyGroupHeading(group), cards]),
      ],
      _ => [
        SliverToBoxAdapter(child: SizedBox(height: first ? _runGap : CatalogCard.spacing)),
        cards,
      ],
    };
  }

  /// The lessons nothing else depends on, under a heading of their own.
  ///
  /// Kept out of the numbered run for the reason [_buildExtra] is: the cards
  /// above are one path, and a student who skips every one of these has still
  /// finished the course.
  Widget _buildDeepDive(BuildContext context, List<CourseLesson> lessons, String locale) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 48),
        Align(
          // Keeps the row around the words and the mark. Stretched to the column
          // it sits in, the mark would drift to the far edge of the page.
          alignment: AlignmentDirectional.centerStart,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(context.localizations.catalogScreen_deepDive, style: context.appTheme.text.h2),
              const SizedBox(width: 8),
              HintMark(
                message: context.localizations.catalogScreen_deepDiveExplained,
                semanticsLabel: context.localizations.catalogScreen_deepDiveWhat,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        for (final (index, lesson) in lessons.indexed) ...[
          if (index > 0) const SizedBox(height: CatalogCard.spacing),
          _buildLessonCard(lesson, locale),
        ],
      ],
    );
  }

  Widget _buildContent() {
    return Builder(
      builder: (context) {
        final locale = Localizations.localeOf(context).languageCode;
        // Read off the locale on screen, the way every other field of a lesson
        // is. `lesson_test.dart` holds the two translations to the same answer.
        final optional = viewModel.lessons.where((it) => it.forLocale(locale).optional).toList();
        final lessons = viewModel.lessons.where((it) => !it.forLocale(locale).optional).toList();
        final runs = runsBy(lessons, (it) => it.forLocale(locale).group);
        // A sliver has no box to centre, so the column is centred by its gutters.
        final gutter = math.max(_gutter, (MediaQuery.sizeOf(context).width - _maxWidth) / 2);

        return CustomScrollView(
          slivers: [
            // Clear of the bar on the first screenful, and under it after that.
            const BarClearanceSliver(),
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: gutter),
              sliver: SliverMainAxisGroup(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 60),
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
                        ],
                      ),
                    ),
                  ),
                  for (final (index, run) in runs.indexed) ..._buildRun(run, locale, first: index == 0),
                  if (optional.isNotEmpty) SliverToBoxAdapter(child: _buildDeepDive(context, optional, locale)),
                  if (languageHasRepl(viewModel.language) || languageHasMicrobit(viewModel.language))
                    SliverToBoxAdapter(child: _buildExtra(context)),
                  const SliverToBoxAdapter(child: SizedBox(height: 100)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

}
