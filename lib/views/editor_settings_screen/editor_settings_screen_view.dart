import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/services/vm/vm_runtime.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/views/base/screen_view_base.dart';
import 'package:i_can_code/views/components/app_button.dart';
import 'package:i_can_code/views/components/app_button_row.dart';
import 'package:i_can_code/views/components/app_header.dart';
import 'package:i_can_code/views/components/app_header_publisher.dart';
import 'package:i_can_code/views/components/code_editor_card.dart';
import 'package:i_can_code/views/editor_settings_screen/components/restore_default_dialog.dart';
import 'package:i_can_code/views/editor_settings_screen/editor_settings_screen_controller.dart';
import 'package:i_can_code/views/editor_settings_screen/editor_settings_screen_view_model.dart';

class EditorSettingsScreenView extends ScreenViewBase<EditorSettingsScreenViewModel, EditorSettingsScreenController> {

  /// The measure of the page, the other one-column screens' own.
  static const double _pageWidth = 900;

  static const int _setupLines = 14;

  const EditorSettingsScreenView({required super.viewModel, required super.controller, required super.contextAccessor});

  @override
  Widget get body {
    return AppHeaderPublisher(builder: _buildHeader, child: Builder(builder: _buildPage));
  }

  AppHeaderConfig _buildHeader(BuildContext context) {
    return AppHeaderConfig(
      onTapHome: controller.goHome,
      crumbs: [AppCrumb(context.localizations.editorSettingsScreen_crumb)],
    );
  }

  Widget _buildPage(BuildContext context) {
    final text = context.appTheme.text;
    final muted = context.theme.colors.mutedForeground;

    return SingleChildScrollView(
      // Clear of the bar, which is drawn over the page rather than above it.
      padding: const EdgeInsets.fromLTRB(32, AppHeader.height + 40, 32, 60),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _pageWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(context.localizations.editorSettingsScreen_title, style: text.h1.copyWith(fontSize: 42)),
              const SizedBox(height: 8),
              Text(
                context.localizations.editorSettingsScreen_subtitle,
                style: text.body.copyWith(fontSize: 19, color: muted),
              ),
              const SizedBox(height: 40),
              Semantics(
                header: true,
                child: Text(
                  context.localizations.editorSettingsScreen_advanced.toUpperCase(),
                  style: text.label.copyWith(fontSize: 13, color: muted),
                ),
              ),
              const SizedBox(height: 12),
              Semantics(
                header: true,
                child: Text(context.localizations.editorSettingsScreen_tkinterSetupTitle, style: text.h3),
              ),
              const SizedBox(height: 8),
              Text(context.localizations.editorSettingsScreen_tkinterSetupBody, style: text.body),
              const SizedBox(height: 20),
              Observer(
                builder: (context) => CodeEditorCard(
                  controller: viewModel.tkinterSetup,
                  fileName: vmSetupFile,
                  status: controller.tkinterSetupIsDefault
                      ? context.localizations.editorSettingsScreen_statusDefault
                      : context.localizations.editorSettingsScreen_statusChanged,
                  height: CodeEditorCard.heightForLines(_setupLines),
                  // A settings page is read before it is edited.
                  autofocus: false,
                ),
              ),
              const SizedBox(height: 12),
              Observer(
                builder: (context) => AppButtonRow(
                  children: [
                    AppButton(
                      tone: AppButtonTone.outline,
                      icon: FLucideIcons.chevronLeft,
                      onPress: () => unawaited(controller.goBack()),
                      child: Text(context.localizations.editorSettingsScreen_back),
                    ),
                    AppButton(
                      tone: AppButtonTone.neutral,
                      icon: FLucideIcons.rotateCcw,
                      onPress: controller.tkinterSetupIsDefault ? null : () => unawaited(_confirmRestore(context)),
                      child: Text(context.localizations.editorSettingsScreen_restore),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmRestore(BuildContext context) async {
    if (await showRestoreDefaultDialog(context)) controller.restoreTkinterSetup();
  }

}
