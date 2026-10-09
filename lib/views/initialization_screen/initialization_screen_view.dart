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
      // Scrolls, because the mobile warning is taller than a phone on its side.
      child: SingleChildScrollView(
        child: Observer(
          builder: (context) => Padding(
            // Tighter on a phone, where 48 a side leaves the warning's button
            // less room than its label needs.
            padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < context.theme.breakpoints.sm ? 24 : 48),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppLogo(size: 118),
                const SizedBox(height: 34),
                Text(context.localizations.app_title, style: context.appTheme.text.display, textAlign: TextAlign.center),
                const SizedBox(height: 40),
                if (viewModel.error case final String error)
                  _buildError(context, error)
                else if (viewModel.mobileWarning)
                  _buildMobileWarning(context)
                else
                  _buildProgress(context),
              ],
            ),
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
        null => localizations.initializationScreen_loading,
      },
      // Only shown once something has gone wrong, so a normal cold start stays
      // a single quiet line.
      detail: viewModel.retries > 0 ? localizations.initializationScreen_retrying(viewModel.retries) : null,
    );
  }

  Widget _buildError(BuildContext context, String error) {
    return _buildNotice(
      context,
      surface: context.appTheme.colors.errorSurface,
      title: context.localizations.initializationScreen_failed,
      body: error,
      bodyStyle: context.appTheme.text.bodySmall.copyWith(fontSize: 15, color: context.theme.colors.mutedForeground),
      actionLabel: context.localizations.initializationScreen_retry,
      onPress: controller.initialize,
    );
  }

  /// Shown in place of going on, in a browser on a phone or a tablet. The
  /// detection can be wrong, so it asks and does not refuse.
  Widget _buildMobileWarning(BuildContext context) {
    return _buildNotice(
      context,
      surface: context.appTheme.colors.warningSurface,
      title: context.localizations.initializationScreen_mobileTitle,
      body: context.localizations.initializationScreen_mobileBody,
      bodyStyle: context.appTheme.text.bodySmall.copyWith(fontSize: 17),
      actionLabel: context.localizations.initializationScreen_mobileContinue,
      onPress: controller.continueAnyway,
    );
  }

  /// A tinted card with one button under it, which is what the screen shows
  /// whenever it stops for the reader.
  Widget _buildNotice(
    BuildContext context, {
    required Color surface,
    required String title,
    required String body,
    required TextStyle bodyStyle,
    required String actionLabel,
    required VoidCallback onPress,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: ShapeDecoration(color: surface, shape: squircle(kCardCornerRadius)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: context.appTheme.text.h3.copyWith(fontSize: 20), textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(body, style: bodyStyle, textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          AppButton(onPress: onPress, child: Text(actionLabel)),
        ],
      ),
    );
  }

}
