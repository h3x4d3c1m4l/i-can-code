import 'package:flutter/widgets.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/shape_metrics.dart';
import 'package:i_can_code/views/base/screen_view_base.dart';
import 'package:i_can_code/views/components/app_button.dart';
import 'package:i_can_code/views/components/app_header.dart';
import 'package:i_can_code/views/components/app_header_publisher.dart';
import 'package:i_can_code/views/components/repl_terminal.dart';
import 'package:i_can_code/views/repl_screen/repl_screen_controller.dart';
import 'package:i_can_code/views/repl_screen/repl_screen_view_model.dart';

class ReplScreenView extends ScreenViewBase<ReplScreenViewModel, ReplScreenController> {

  const ReplScreenView({required super.viewModel, required super.controller, required super.contextAccessor});

  @override
  Widget get body {
    return AppHeaderPublisher(builder: _buildHeader, child: _buildContent());
  }

  AppHeaderConfig _buildHeader(BuildContext context) {
    return AppHeaderConfig(
      onTapHome: controller.goHome,
      crumbs: [
        AppCrumb(languageLabel(viewModel.language), onTap: controller.goToCatalog),
        AppCrumb(context.localizations.replScreen_crumb),
      ],
    );
  }

  Widget _buildContent() {
    return Builder(
      builder: (context) {
        final title = context.localizations.replScreen_title(languageLabel(viewModel.language));

        return Padding(
          padding: const EdgeInsets.fromLTRB(32, AppHeader.height + 40, 32, 40),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title, style: context.appTheme.text.h1.copyWith(fontSize: 42)),
                  const SizedBox(height: 8),
                  Text(
                    context.localizations.replScreen_subtitle,
                    style: context.appTheme.text.body.copyWith(
                      fontSize: 19,
                      color: context.theme.colors.mutedForeground,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Expanded(
                    child: Observer(
                      builder: (context) => switch (viewModel.status) {
                        ReplStatus.unavailable => _buildUnavailable(context),
                        _ => ReplTerminal(terminal: viewModel.terminal),
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildFooter(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFooter() {
    return Observer(
      builder: (context) {
        final starting = viewModel.status == ReplStatus.starting;

        return Row(
          children: [
            Expanded(
              child: Text(
                starting
                    ? context.localizations.replScreen_starting
                    // Only worth reading once there is something to type into.
                    : context.localizations.replScreen_hint,
                style: context.appTheme.text.bodySmall.copyWith(color: context.theme.colors.mutedForeground),
              ),
            ),
            const SizedBox(width: 16),
            if (viewModel.status != ReplStatus.unavailable)
              AppButton(
                tone: AppButtonTone.neutral,
                busy: starting,
                onPress: starting ? null : controller.restart,
                child: Text(context.localizations.replScreen_restart),
              ),
          ],
        );
      },
    );
  }

  /// Shown where the page is not cross-origin isolated, which is the only thing
  /// an interactive session cannot do without. Stated plainly rather than hidden:
  /// a console that silently is not there reads as a broken app.
  Widget _buildUnavailable(BuildContext context) {
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: squircle(kCardCornerRadius, side: BorderSide(color: context.theme.colors.border, width: 2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.localizations.replScreen_unavailableTitle, style: context.appTheme.text.h3),
            const SizedBox(height: 12),
            Text(
              context.localizations.replScreen_unavailableBody,
              style: context.appTheme.text.body.copyWith(color: context.theme.colors.mutedForeground),
            ),
          ],
        ),
      ),
    );
  }

}
