import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:forui/forui.dart';
import 'package:get_it/get_it.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/routing/app_router.dart';
import 'package:i_can_code/routing/app_router.gr.dart';
import 'package:i_can_code/services/file_download/file_download.dart';
import 'package:i_can_code/services/locale_controller.dart';
import 'package:i_can_code/services/progress/code_draft_store.dart';
import 'package:i_can_code/services/progress/progress_store.dart';
import 'package:i_can_code/services/theme_mode_controller.dart';
import 'package:i_can_code/services/vm/vm_image.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/views/components/app_button.dart';
import 'package:i_can_code/views/components/app_dialog.dart';
import 'package:i_can_code/views/components/debug_menu.dart';
import 'package:i_can_code/views/components/header_icon_button.dart';
import 'package:i_can_code/views/components/progress_transfer.dart';

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

  /// The menu's tap region, which a [_DisabledReason] joins with its panel.
  final Object _tapGroup = Object();

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
    final openDebugMenu = kDebugMode ? DebugMenu.opener(context) : null;

    return Observer(
      builder: (context) => FPopoverMenu(
        control: FPopoverControl.managed(controller: _controller),
        groupId: _tapGroup,
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
          // Its one setting is about the machine behind the Tkinter page, which a
          // project on `runtime: tkinter` runs on too.
          if (vmImageIncluded)
            FItemGroup(
              children: [
                FItem(
                  title: Text(context.localizations.appHeader_editorSettings),
                  prefix: const Icon(FLucideIcons.squareCode),
                  onPress: () {
                    unawaited(_controller.hide());
                    unawaited(_openEditorSettings());
                  },
                ),
              ],
            ),
          FItemGroup(
            children: [
              // Offered with nothing done too: the file lists every lesson, so
              // it still reports where a student stands.
              if (canDownloadFiles)
                FItem(
                  title: Text(context.localizations.appHeader_exportProgress),
                  prefix: const Icon(FLucideIcons.download),
                  onPress: () {
                    unawaited(_controller.hide());
                    ProgressTransfer.exportFile(context);
                  },
                ),
              FItem(
                title: Text(context.localizations.appHeader_importProgress),
                prefix: const Icon(FLucideIcons.upload),
                onPress: () async {
                  unawaited(_controller.hide());
                  await ProgressTransfer.importFile(context);
                },
              ),
              // Always there, so it can be found before it is needed. Greyed
              // out while there is nothing to clear, and saying so when pressed.
              _DisabledReason(
                enabled: progress.hasProgress || drafts.hasDrafts,
                reason: context.localizations.appHeader_resetProgressNothing,
                tapGroup: _tapGroup,
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
          FItemGroup(
            children: [
              FItem(
                title: Text(context.localizations.appHeader_about),
                prefix: const Icon(FLucideIcons.info),
                onPress: () {
                  unawaited(_controller.hide());
                  unawaited(_openAbout());
                },
              ),
            ],
          ),
          if (openDebugMenu != null)
            FItemGroup(
              children: [
                FItem(
                  title: const Text('Debug'),
                  prefix: const Icon(FLucideIcons.bug),
                  onPress: () {
                    unawaited(_controller.hide());
                    openDebugMenu();
                  },
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

  /// Opens the about screen on top of whatever the reader was on, so the
  /// browser's Back button returns them to it.
  ///
  /// Through the router in GetIt and not `context.router`: the bar sits above
  /// the router, so there is none to find from here.
  Future<void> _openAbout() async {
    final router = GetIt.I<AppRouter>();
    if (router.current.name == AboutRoute.name) return;

    await router.push(const AboutRoute());
  }

  /// Through GetIt, because the cog sits above the router and its context has
  /// no router to find.
  Future<void> _openEditorSettings() async {
    final router = GetIt.I<AppRouter>();
    if (router.stackData.any((route) => route.name == EditorSettingsRoute.name)) return;
    await router.push(const EditorSettingsRoute());
  }

  /// Asks before forgetting. Irreversible.
  Future<void> _confirmReset(BuildContext context, ProgressStore progress, CodeDraftStore drafts) async {
    final confirmed = await showAppDialog<bool>(
      context,
      builder: (context) => AppDialog(
        title: Text(context.localizations.resetProgress_title),
        body: Text(context.localizations.resetProgress_body),
        actions: [
          AppButton(
            tone: AppButtonTone.neutral,
            onPress: () => Navigator.of(context).pop(false),
            child: Text(context.localizations.common_cancel),
          ),
          AppButton(
            onPress: () => Navigator.of(context).pop(true),
            child: Text(context.localizations.resetProgress_confirm),
          ),
        ],
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
///
/// It stands left of the menu where the window has room, so it covers no other
/// item, and under the item where it has not. A press on it closes it and
/// leaves the menu open.
class _DisabledReason extends StatefulWidget with FItemMixin {

  final bool enabled;

  /// What the popover says while the item is disabled. A sentence.
  final String reason;

  /// The menu's `groupId`. The panel is in an overlay of its own, so without
  /// it a press on the panel is outside the menu and closes it.
  final Object tapGroup;

  /// Builds the item itself, enabled or not.
  final Widget Function(bool enabled) builder;

  const _DisabledReason({
    required this.enabled,
    required this.reason,
    required this.tapGroup,
    required this.builder,
  });

  @override
  State<_DisabledReason> createState() => _DisabledReasonState();

}

class _DisabledReasonState extends State<_DisabledReason> with SingleTickerProviderStateMixin {

  /// As narrow as [HintMark]'s, for the same reason.
  static const double _panelWidth = 300;
  static const EdgeInsets _panelPadding = EdgeInsets.symmetric(horizontal: 16, vertical: 12);

  /// Between the panel and the menu, when it stands beside it.
  static const double _gap = 8;

  /// What the panel keeps clear of the window's left edge.
  static const double _margin = 16;

  late final FPopoverController _controller = FPopoverController(vsync: this);

  /// Whether the panel stands left of the menu. Measured on the press, since
  /// the menu's place depends on the window and on the widest item.
  bool _beside = true;

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

  void _explain() {
    // The item is as wide as the menu, so its left edge is the menu's.
    final item = context.findRenderObject()! as RenderBox;
    setState(() => _beside = item.localToGlobal(Offset.zero).dx >= _margin + _panelWidth + _gap);
    unawaited(_controller.show());
  }

  @override
  Widget build(BuildContext context) {
    if (widget.enabled) return widget.builder(true);

    return FPopover(
      popoverAnchor: _beside ? Alignment.topRight : Alignment.topCenter,
      childAnchor: _beside ? Alignment.topLeft : Alignment.bottomCenter,
      spacing: _beside ? const FPortalSpacing(_gap) : const FPortalSpacing(4),
      control: FPopoverControl.managed(controller: _controller),
      popoverBuilder: (context, _) => TapRegion(
        groupId: widget.tapGroup,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: _controller.hide,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _panelWidth),
            child: Padding(
              padding: _panelPadding,
              child: Text(widget.reason, style: context.appTheme.text.bodySmall),
            ),
          ),
        ),
      ),
      child: GestureDetector(
        // Opaque, so a press on the item's padding counts as well.
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: _explain,
        child: widget.builder(false),
      ),
    );
  }

}
