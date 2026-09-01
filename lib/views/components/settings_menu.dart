import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:forui/forui.dart';
import 'package:get_it/get_it.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/services/locale_controller.dart';
import 'package:i_can_code/services/progress/progress_store.dart';
import 'package:i_can_code/services/theme_mode_controller.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/shape_metrics.dart';
import 'package:i_can_code/views/components/app_button.dart';

/// The cog in the header. Holds the language choice and anything else that
/// belongs to the reader rather than to the lesson.
class SettingsMenu extends StatefulWidget {

  const SettingsMenu({super.key});

  @override
  State<SettingsMenu> createState() => _SettingsMenuState();

}

class _SettingsMenuState extends State<SettingsMenu> with SingleTickerProviderStateMixin {

  /// Owned here rather than by `FPopoverControl.managed()`, because **the
  /// popover does not open itself**: `FPopover.defaultBuilder` adds no gesture,
  /// so something MUST call [FPopoverController.toggle].
  late final FPopoverController _controller = FPopoverController(vsync: this);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locales = GetIt.I<LocaleController>();
    final themes = GetIt.I<ThemeModeController>();
    final progress = GetIt.I<ProgressStore>();

    return Observer(
      builder: (context) => FPopoverMenu(
        control: FPopoverControl.managed(controller: _controller),
        menuAnchor: Alignment.topRight,
        childAnchor: Alignment.bottomRight,
        semanticsLabel: context.localizations.appHeader_settings,
        menu: [
          FItemGroup(
            children: [
              FItem(
                title: Text(context.localizations.appHeader_languageSystem),
                prefix: const Icon(FLucideIcons.languages),
                suffix: locales.followsDevice ? const Icon(FLucideIcons.check) : null,
                onPress: () {
                  unawaited(locales.setLocale(null));
                  _controller.hide();
                },
              ),
              for (final locale in LocaleControllerBase.supported)
                FItem(
                  title: Text(_languageName(locale)),
                  suffix: locales.locale == locale ? const Icon(FLucideIcons.check) : null,
                  onPress: () {
                    unawaited(locales.setLocale(locale));
                    _controller.hide();
                  },
                ),
            ],
          ),
          FItemGroup(
            children: [
              for (final mode in AppThemeMode.values)
                FItem(
                  title: Text(_themeName(context, mode)),
                  prefix: Icon(_themeIcon(mode)),
                  suffix: themes.mode == mode ? const Icon(FLucideIcons.check) : null,
                  onPress: () {
                    unawaited(themes.setMode(mode));
                    _controller.hide();
                  },
                ),
            ],
          ),
          // Only offered when there is something to clear.
          if (progress.hasProgress)
            FItemGroup(
              children: [
                FItem(
                  title: Text(context.localizations.appHeader_resetProgress),
                  prefix: const Icon(FLucideIcons.rotateCcw),
                  onPress: () async {
                    // The menu has to be out of the way before the dialog
                    // opens, but the dialog does not wait on its animation.
                    unawaited(_controller.hide());
                    await _confirmReset(context, progress);
                  },
                ),
              ],
            ),
        ],
        child: _CogButton(
          onPress: _controller.toggle,
          semanticsLabel: context.localizations.appHeader_settings,
        ),
      ),
    );
  }

  /// Asks before forgetting. Irreversible.
  Future<void> _confirmReset(BuildContext context, ProgressStore progress) async {
    final confirmed = await showFDialog<bool>(
      context: context,
      builder: (context, style, animation) => FDialog(
        animation: animation,
        builder: (context, style) => Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(context.localizations.resetProgress_title, style: context.appTheme.text.h3),
              const SizedBox(height: 12),
              Text(
                context.localizations.resetProgress_body,
                style: context.appTheme.text.bodySmall.copyWith(fontSize: 17),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppButton(
                    tone: AppButtonTone.neutral,
                    onPress: () => Navigator.of(context).pop(false),
                    child: Text(context.localizations.common_cancel),
                  ),
                  const SizedBox(width: 12),
                  AppButton(
                    onPress: () => Navigator.of(context).pop(true),
                    child: Text(context.localizations.resetProgress_confirm),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed ?? false) await progress.clear();
  }

  /// Each language named in itself, which is what a reader scans for.
  String _languageName(Locale locale) => switch (locale.languageCode) {
    'nl' => 'Nederlands',
    'en' => 'English',
    _ => locale.languageCode.toUpperCase(),
  };

  String _themeName(BuildContext context, AppThemeMode mode) => switch (mode) {
    AppThemeMode.system => context.localizations.appHeader_themeSystem,
    AppThemeMode.light => context.localizations.appHeader_themeLight,
    AppThemeMode.dark => context.localizations.appHeader_themeDark,
  };

  IconData _themeIcon(AppThemeMode mode) => switch (mode) {
    AppThemeMode.system => FLucideIcons.monitor,
    AppThemeMode.light => FLucideIcons.sun,
    AppThemeMode.dark => FLucideIcons.moon,
  };

}

class _CogButton extends StatelessWidget {

  final VoidCallback onPress;
  final String semanticsLabel;

  const _CogButton({required this.onPress, required this.semanticsLabel});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;

    return FTappable(
      onPress: onPress,
      semanticsButton: true,
      semanticsLabel: semanticsLabel,
      builder: (context, states, child) => DecoratedBox(
        decoration: ShapeDecoration(
          color: states.contains(FTappableVariant.hovered) ? theme.colors.secondary : const Color(0x00000000),
          shape: squircleOf(kChipCornerRadius, size: 38),
        ),
        child: Padding(padding: const EdgeInsets.all(9), child: child),
      ),
      child: Icon(FLucideIcons.settings, size: 20, color: theme.colors.foreground),
    );
  }

}
