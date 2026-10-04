import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:forui/forui.dart';
import 'package:get_it/get_it.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/services/locale_controller.dart';
import 'package:i_can_code/services/progress/code_draft_store.dart';
import 'package:i_can_code/services/progress/progress_store.dart';
import 'package:i_can_code/services/theme_mode_controller.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/views/components/app_button.dart';
import 'package:i_can_code/views/components/header_icon_button.dart';

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
    final drafts = GetIt.I<CodeDraftStore>();

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
          FItemGroup(
            children: [
              // Always there, so it can be found before it is needed. Greyed
              // out while there is nothing to clear, and saying so when pressed.
              _DisabledReason(
                enabled: progress.hasProgress || drafts.hasDrafts,
                reason: context.localizations.appHeader_resetProgressNothing,
                builder: (enabled) => FItem(
                  enabled: enabled,
                  title: Text(context.localizations.appHeader_resetProgress),
                  prefix: const Icon(FLucideIcons.rotateCcw),
                  semanticsTooltip: enabled ? null : context.localizations.appHeader_resetProgressNothing,
                  onPress: () async {
                    // The menu has to be out of the way before the dialog
                    // opens, but the dialog does not wait on its animation.
                    unawaited(_controller.hide());
                    await _confirmReset(context, progress, drafts);
                  },
                ),
              ),
            ],
          ),
        ],
        child: HeaderIconButton(
          icon: FLucideIcons.settings,
          semanticsLabel: context.localizations.appHeader_settings,
          onPress: _controller.toggle,
        ),
      ),
    );
  }

  /// Asks before forgetting. Irreversible.
  Future<void> _confirmReset(BuildContext context, ProgressStore progress, CodeDraftStore drafts) async {
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

    if (confirmed ?? false) await (progress.clear(), drafts.clear()).wait;
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

/// A menu item that says why it cannot be used when it is pressed anyway.
///
/// forui's [FItem] hands its [FTappable] no callback at all while disabled, and
/// has no `onDisabledPress` to pass on, although the tappable has one. A
/// tappable without callbacks claims no pointer, so the [GestureDetector]
/// around it is the only thing that sees the press.
///
/// The reason is an [FPopover] and not an [FTooltip] for the reason [HintMark]
/// gives: forui's tooltip hides itself on every pointer down.
class _DisabledReason extends StatefulWidget with FItemMixin {

  final bool enabled;

  /// What the popover says while the item is disabled. A sentence.
  final String reason;

  /// Builds the item itself, enabled or not.
  final Widget Function(bool enabled) builder;

  const _DisabledReason({required this.enabled, required this.reason, required this.builder});

  @override
  State<_DisabledReason> createState() => _DisabledReasonState();

}

class _DisabledReasonState extends State<_DisabledReason> with SingleTickerProviderStateMixin {

  /// As narrow as [HintMark]'s, for the same reason.
  static const double _panelWidth = 300;
  static const EdgeInsets _panelPadding = EdgeInsets.symmetric(horizontal: 16, vertical: 12);

  late final FPopoverController _controller = FPopoverController(vsync: this);

  @override
  void didUpdateWidget(_DisabledReason oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled) unawaited(_controller.hide());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.enabled) return widget.builder(true);

    return FPopover(
      popoverAnchor: Alignment.topCenter,
      childAnchor: Alignment.bottomCenter,
      control: FPopoverControl.managed(controller: _controller),
      popoverBuilder: (context, _) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _panelWidth),
        child: Padding(
          padding: _panelPadding,
          child: Text(widget.reason, style: context.appTheme.text.bodySmall),
        ),
      ),
      child: GestureDetector(
        // Opaque, so a press on the item's padding counts as well.
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: _controller.show,
        child: widget.builder(false),
      ),
    );
  }

}
