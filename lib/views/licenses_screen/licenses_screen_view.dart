import 'package:flutter/widgets.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/services/licenses/license_catalog.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/views/base/screen_view_base.dart';
import 'package:i_can_code/views/components/app_button.dart';
import 'package:i_can_code/views/components/app_header.dart';
import 'package:i_can_code/views/components/app_header_publisher.dart';
import 'package:i_can_code/views/components/app_scrollbar.dart';
import 'package:i_can_code/views/components/loading_overlay.dart';
import 'package:i_can_code/views/components/notice_card.dart';
import 'package:i_can_code/views/components/text_link.dart';
import 'package:i_can_code/views/licenses_screen/components/license_detail.dart';
import 'package:i_can_code/views/licenses_screen/components/license_list.dart';
import 'package:i_can_code/views/licenses_screen/license_labels.dart';
import 'package:i_can_code/views/licenses_screen/licenses_screen_controller.dart';
import 'package:i_can_code/views/licenses_screen/licenses_screen_view_model.dart';

class LicensesScreenView extends ScreenViewBase<LicensesScreenViewModel, LicensesScreenController> {

  /// As wide as a lesson's two-column step, the widest page the app lays out.
  static const double _maxWidth = 1146;

  /// The list beside the text. Wide enough for the longest package name the
  /// app ships at the row's type size.
  static const double _listWidth = 340;

  static const double _gap = 26;

  const LicensesScreenView({required super.viewModel, required super.controller, required super.contextAccessor});

  @override
  Widget get body {
    return AppHeaderPublisher(builder: _buildHeader, child: _buildContent());
  }

  /// Below `lg` the list and the text do not fit side by side, and the screen
  /// shows one of them at a time.
  bool _stacked(BuildContext context) => MediaQuery.sizeOf(context).width < context.theme.breakpoints.lg;

  AppHeaderConfig _buildHeader(BuildContext context) {
    final title = context.localizations.licensesScreen_title;
    final picked = viewModel.picked;

    return AppHeaderConfig(
      onTapHome: controller.goHome,
      crumbs: [
        AppCrumb(context.localizations.aboutScreen_title, onTap: controller.openAbout),
        // One at a time, so the open component is a level below the list and
        // the list's own crumb leads back to it.
        if (_stacked(context) && picked != null) ...[
          AppCrumb(title, onTap: controller.showList),
          AppCrumb(componentName(context.localizations, picked)),
        ] else
          AppCrumb(title),
      ],
    );
  }

  Widget _buildContent() {
    return Padding(
      // The panes scroll inside themselves, so nothing here passes under the
      // bar and the page keeps clear of it once, at the top.
      padding: const EdgeInsets.fromLTRB(32, AppHeader.height + 40, 32, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxWidth),
          child: Observer(
            builder: (context) {
              final picked = viewModel.picked;

              // One component fills a narrow window by itself. The title and
              // the introduction would take half of it.
              if (_stacked(context) && picked != null) return _buildPicked(context, picked);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    context.localizations.licensesScreen_title,
                    style: context.appTheme.text.h1.copyWith(fontSize: 42),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.localizations.licensesScreen_intro,
                    style: context.appTheme.text.body.copyWith(
                      fontSize: 19,
                      color: context.theme.colors.mutedForeground,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextLink(
                      label: context.localizations.licensesScreen_source,
                      onPress: controller.openSource,
                      opensTab: true,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Expanded(child: _buildPanes(context)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// The list and the text beside it, or the list alone where they do not fit.
  Widget _buildPanes(BuildContext context) {
    if (viewModel.failed) {
      return Align(
        alignment: AlignmentDirectional.topStart,
        child: NoticeCard(
          title: context.localizations.licensesScreen_failedTitle,
          body: context.localizations.licensesScreen_failedBody,
          action: AppButton(
            tone: AppButtonTone.neutral,
            onPress: controller.load,
            child: Text(context.localizations.licensesScreen_retry),
          ),
        ),
      );
    }

    final catalog = viewModel.catalog;
    if (catalog == null) {
      return Center(child: LoadingOverlay(message: context.localizations.licensesScreen_loading));
    }

    final stacked = _stacked(context);
    final shown = viewModel.shown;
    final list = LicenseList(
      groups: groupsMatching(catalog, viewModel.query, context.localizations),
      // Nothing is open while the list has the window to itself.
      selected: stacked ? null : shown,
      onPick: controller.pick,
      query: viewModel.query,
      onSearch: controller.search,
    );

    if (stacked || shown == null) return list;

    // The list's scrollbar stands in the gap: the list keeps its rows clear of
    // it, and this gives the list the room back.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: _listWidth + AppScrollbar.gutter, child: list),
        const SizedBox(width: _gap - AppScrollbar.gutter),
        Expanded(child: _buildDetail(context, shown)),
      ],
    );
  }

  /// One component with the window to itself, and the way back above it.
  Widget _buildPicked(BuildContext context, LicensedComponent picked) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AppButton(
            tone: AppButtonTone.outline,
            icon: FLucideIcons.chevronLeft,
            onPress: controller.showList,
            child: Text(context.localizations.licensesScreen_back),
          ),
        ),
        const SizedBox(height: 20),
        Expanded(child: _buildDetail(context, picked)),
      ],
    );
  }

  Widget _buildDetail(BuildContext context, LicensedComponent component) {
    return LicenseDetail(
      name: componentName(context.localizations, component),
      origin: originLabel(context.localizations, component.origin),
      texts: component.texts,
    );
  }

}
