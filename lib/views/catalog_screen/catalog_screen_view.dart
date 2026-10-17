import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/routing/catalog_anchor.dart';
import 'package:i_can_code/services/feature_toggles.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/shape_metrics.dart';
import 'package:i_can_code/views/base/screen_view_base.dart';
import 'package:i_can_code/views/catalog_screen/catalog_screen.dart';
import 'package:i_can_code/views/catalog_screen/catalog_screen_controller.dart';
import 'package:i_can_code/views/catalog_screen/catalog_screen_view_model.dart';
import 'package:i_can_code/views/catalog_screen/components/anchor_target.dart';
import 'package:i_can_code/views/catalog_screen/components/bar_clearance_sliver.dart';
import 'package:i_can_code/views/catalog_screen/components/catalog_anchor_scope.dart';
import 'package:i_can_code/views/catalog_screen/components/copy_link_menu.dart';
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

  /// The air above a card an address asked for, under the bar and under the
  /// heading stuck there.
  static const double _cardClearance = 12;

  const CatalogScreenView({required super.viewModel, required super.controller, required super.contextAccessor});

  @override
  Widget get body {
    // Read off the screen's own widget, as it is at this build. auto_route
    // hands a page new arguments in place, and `ScreenBase` makes the view
    // model once, so the widget is the only place the address of the moment
    // reaches.
    final anchor = (context.widget as CatalogScreen).anchor;

    return AppHeaderPublisher(
      builder: (context) => AppHeaderConfig(
        onTapHome: controller.goHome,
        crumbs: [AppCrumb(subjectLabel(viewModel.subject))],
      ),
      child: CatalogAnchorScope(anchor: anchor, child: _buildContent()),
    );
  }

  /// The address that opens this catalog at [anchor].
  Uri _addressOf(CatalogAnchor anchor) => catalogAddress(subjectSlug: subjectSlug(viewModel.subject), anchor: anchor);

  /// Everything this subject offers beside the course itself.
  ///
  /// Under its own heading on purpose: the cards above are a path with progress
  /// on it, and this is not part of that path. Nothing here is checked and
  /// nothing is recorded.
  Widget _buildExtra(BuildContext context) {
    final windows = _offersWindows;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 48),
        Text(context.localizations.catalogScreen_extra, style: context.appTheme.text.h2),
        const SizedBox(height: 16),
        if (subjectHasRepl(viewModel.subject))
          CatalogCard(
            // A prompt, in the code face the tile already uses. The lessons above
            // are numbered and this is not one of them, so it does not get a
            // number.
            label: '>_',
            title: context.localizations.replScreen_title(subjectLabel(viewModel.subject)),
            subtitle: context.localizations.replScreen_subtitle,
            meta: context.localizations.catalogScreen_extraFreePlay,
            onTap: controller.openRepl,
          ),
        if (windows) ...[
          if (subjectHasRepl(viewModel.subject)) const SizedBox(height: CatalogCard.spacing),
          CatalogCard(
            // A window, for the one page here whose programs open them. Still in
            // the browser, which is why it sits beside the console rather than
            // with the board.
            label: '🪟',
            title: context.localizations.tkinterScreen_title,
            subtitle: context.localizations.tkinterScreen_subtitle,
            meta: context.localizations.catalogScreen_extraFreePlay,
            onTap: controller.openTkinter,
          ),
        ],
        if ((subjectHasRepl(viewModel.subject) || windows) && subjectHasMicrobit(viewModel.subject))
          const SizedBox(height: CatalogCard.spacing),
        if (subjectHasMicrobit(viewModel.subject)) ...[
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
            title: context.localizations.microbitReplScreen_title(subjectLabel(viewModel.subject)),
            subtitle: context.localizations.microbitReplScreen_subtitle,
            meta: context.localizations.catalogScreen_extraHardware,
            onTap: controller.openMicrobitRepl,
          ),
        ],
      ],
    );
  }

  /// Read in the content's [Observer], so a switch of the toggle redraws the
  /// section at once.
  bool get _offersWindows => tkinterShown && subjectHasWindows(viewModel.subject);

  /// One row of the course, for whichever run it belongs to. [group] is the
  /// heading it stands under on this page, which it lights up along with.
  ///
  /// An [Observer] of its own, so a tick redraws one card. Nothing above it is
  /// one.
  Widget _buildLessonCard(CourseLesson courseLesson, String locale, {LessonGroup? group}) {
    final CatalogAnchor anchor = (kind: CatalogAnchorKind.lesson, id: courseLesson.translations.values.first.id);

    return AnchorTarget(
      anchor: anchor,
      alongWith: group == null ? null : (kind: CatalogAnchorKind.group, id: group.id),
      clearance: _cardClearance,
      radius: kCardCornerRadius,
      child: CopyLinkMenu(
        address: () => _addressOf(anchor),
        child: Observer(
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
              // How far in, from the first visit on. A lesson not started
              // reads "0 / 5" rather than "5 stappen", so the number in this
              // position never changes meaning between one row and the next.
              // Finished: the card shows a tick instead.
              meta: context.localizations.catalogScreen_progress(done, lesson.stepCount),
              onTap: () => controller.openLesson(courseLesson),
            );
          },
        ),
      ),
    );
  }

  /// A group's heading, as something an address can name and a right click can
  /// copy the address of.
  Widget _buildGroupHeading(LessonGroup group, String locale) {
    final CatalogAnchor anchor = (kind: CatalogAnchorKind.group, id: group.id);

    return StickyGroupHeading(
      group.titleFor(locale),
      labelBuilder: (heading) => AnchorTarget(
        anchor: anchor,
        // Where the heading stands when nothing holds it up: its own gap
        // under the bar. Any higher and it would arrive stuck.
        clearance: StickyGroupHeading.topGap,
        radius: StickyGroupHeading.labelCornerRadius,
        outset: StickyGroupHeading.labelPadding,
        child: CopyLinkMenu(address: () => _addressOf(anchor), child: heading),
      ),
    );
  }

  /// One run of the course as slivers. A run with a group opens with its
  /// heading, which sticks under the bar while the run's lessons pass under it.
  List<Widget> _buildRun(List<CourseLesson> run, String locale, {required bool first}) {
    final group = run.first.entry.group;
    // A column and not a sliver list, so every card is built, on screen or
    // not. An address scrolls to a card by the scroll extent of what is above
    // it, and a lazy list only estimates the rows it has not laid out.
    final cards = SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, lesson) in run.indexed) ...[
            if (index > 0) const SizedBox(height: CatalogCard.spacing),
            _buildLessonCard(lesson, locale, group: group),
          ],
        ],
      ),
    );

    return switch (group) {
      final LessonGroup group => [
        const SliverToBoxAdapter(child: SizedBox(height: _runGap - StickyGroupHeading.topGap)),
        SliverMainAxisGroup(slivers: [_buildGroupHeading(group, locale), cards]),
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
    // An Observer, so a feature toggle switched in the debug menu adds or takes
    // away lessons under it.
    return Observer(
      // A course that names no toggle reads none, which is normal here.
      warnWhenNoObservables: false,
      builder: (context) {
        final locale = Localizations.localeOf(context).languageCode;
        // Read off the locale on screen, the way every other field of a lesson
        // is. `lesson_test.dart` holds the two translations to the same answer.
        final optional = viewModel.lessons.where((it) => it.forLocale(locale).optional).toList();
        final lessons = viewModel.lessons.where((it) => !it.forLocale(locale).optional).toList();
        final runs = runsBy(lessons, (it) => it.entry.group?.id);
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
                            subjectLabel(viewModel.subject),
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
                  for (final (index, run) in runs.indexed) ..._buildRun(run.items, locale, first: index == 0),
                  if (optional.isNotEmpty) SliverToBoxAdapter(child: _buildDeepDive(context, optional, locale)),
                  if (subjectHasRepl(viewModel.subject) ||
                      _offersWindows ||
                      subjectHasMicrobit(viewModel.subject))
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
