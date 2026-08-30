import 'package:flutter/widgets.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/shape_metrics.dart';
import 'package:i_can_code/views/base/screen_view_base.dart';
import 'package:i_can_code/views/components/app_button.dart';
import 'package:i_can_code/views/components/app_logo.dart';
import 'package:i_can_code/views/components/loading_overlay.dart';
import 'package:i_can_code/views/initialization_screen/initialization_screen_controller.dart';
import 'package:i_can_code/views/initialization_screen/initialization_screen_view_model.dart';

class InitializationScreenView extends ScreenViewBase<InitializationScreenViewModel, InitializationScreenController> {

  const InitializationScreenView({required super.viewModel, required super.controller, required super.contextAccessor});

  @override
  Widget get body {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Observer(
          builder: (context) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppLogo(size: 118),
              const SizedBox(height: 34),
              Text(context.localizations.app_title, style: context.appTheme.text.display),
              const SizedBox(height: 40),
              if (viewModel.error case final String error) _buildError(context, error) else _buildProgress(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgress(BuildContext context) {
    final localizations = context.localizations;

    return LoadingOverlay(
      message: switch (viewModel.step) {
        InitializationStep.loadingCourse => localizations.initializationScreen_loadingCourse,
        InitializationStep.startingRuntime => localizations.initializationScreen_startingRuntime,
        null => localizations.initializationScreen_loading,
      },
      // Only shown once something has gone wrong, so a normal cold start stays
      // a single quiet line.
      detail: viewModel.retries > 0 ? localizations.initializationScreen_retrying(viewModel.retries) : null,
    );
  }

  Widget _buildError(BuildContext context, String error) {
    final theme = context.theme;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: ShapeDecoration(
              color: context.appTheme.colors.errorSurface,
              shape: squircle(kCardCornerRadius),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.localizations.initializationScreen_failed,
                    style: context.appTheme.text.h3.copyWith(fontSize: 20),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    error,
                    style: context.appTheme.text.bodySmall.copyWith(
                      fontSize: 15,
                      color: theme.colors.mutedForeground,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          AppButton(onPress: controller.initialize, child: Text(context.localizations.initializationScreen_retry)),
        ],
      ),
    );
  }

}
