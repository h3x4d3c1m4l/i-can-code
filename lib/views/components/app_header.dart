import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/views/components/app_logo.dart';
import 'package:i_can_code/views/components/fade_through.dart';
import 'package:i_can_code/views/components/header_icon_button.dart';
import 'package:i_can_code/views/components/settings_menu.dart';

/// One level of the trail in [AppHeader].
class AppCrumb {

  final String label;

  /// Null for a level that cannot be navigated to — the current page, or a
  /// grouping with no screen of its own.
  final VoidCallback? onTap;

  const AppCrumb(this.label, {this.onTap});

}

/// What one screen puts in the app's header.
///
/// A screen hands over an [AppHeaderBuilder] rather than a built bar, because
/// **the bar is not the screen's to build**: it lives above the router and
/// outlives every screen that fills it. See `app_header_host.dart`.
class AppHeaderConfig {

  /// Levels below the app name: the language, the lesson.
  final List<AppCrumb> crumbs;

  /// Tapping the app name goes home. Null on the screen that *is* home, so it
  /// does not offer to navigate to itself.
  final VoidCallback? onTapHome;

  /// Sits between the trail and the cog. The lesson screen puts its progress
  /// bar here.
  final Widget? trailing;

  /// Whether this screen is one worth reading without the bar above it, which
  /// is what puts the button that hides it in the bar. See
  /// `app_header_host.dart`.
  final bool offersZen;

  /// Shown after the app's own name. Null on every screen but the first, where
  /// it would be a number following the reader around.
  final String? version;

  const AppHeaderConfig({
    this.crumbs = const [],
    this.onTapHome,
    this.trailing,
    this.offersZen = false,
    this.version,
  });

}

/// Resolves a screen's header against the *shell's* context, on every rebuild.
///
/// It runs inside the host's own [Observer], so anything observable it reads —
/// the step a lesson is on, the locale — keeps the bar up to date without the
/// screen having to push anything.
typedef AppHeaderBuilder = AppHeaderConfig Function(BuildContext context);

/// The bar every screen but the initialization screen carries: the mark and the
/// trail on the left, the screen's own chrome and the settings cog on the right.
/// The trail always starts at the app itself.
///
/// Positioned by `AppHeaderHost`, which is what keeps it in place — and on
/// screen — while the screen underneath it is replaced.
class AppHeader extends StatelessWidget {

  /// The bar's height. Read by the host, which reserves exactly this much for
  /// it above the screen.
  static const double height = 76;

  /// The gap that separates the cog, the hide button and the trailing widget
  /// from each other.
  static const double _gap = 20;

  /// The bar's own left and right margin. Public because the button that brings
  /// the bar back stands in the cog's place while it is away, and lines up with
  /// it by taking the same number.
  static const double horizontalPadding = 32;

  /// Levels below the app name: the language, the lesson, the step.
  final List<AppCrumb> crumbs;

  /// Tapping the app name goes home. Null on the screen that *is* home, so it
  /// does not offer to navigate to itself.
  final VoidCallback? onTapHome;

  /// Sits between the trail and the cog. The lesson screen puts its progress
  /// bar here.
  final Widget? trailing;

  /// Puts the bar away. Null on a screen that does not offer zen mode, where
  /// the bar carries no such button at all.
  final VoidCallback? onHide;

  /// The app's version, after the mark. See [AppHeaderConfig.version].
  final String? version;

  const AppHeader({
    this.crumbs = const [],
    this.onTapHome,
    this.trailing,
    this.onHide,
    this.version,
    super.key,
  });

  /// How wide the bar's *contents* are allowed to get.
  ///
  /// forui's breakpoints are Tailwind's, and `xl` is the first one that clears
  /// the widest column the app lays out — a lesson's two-column step, at
  /// `1120 + 26` inside the same padding. So the trail and the cog stop at the
  /// edge of the widest page rather than following the window out to a corner
  /// of a wide monitor. The bar's *surface* is full width all the same: it is
  /// the top of the window, not a card in it.
  static double maxContentWidth(BuildContext context) => context.theme.breakpoints.xl;

  /// How far the cog's right edge sits from the window's own.
  ///
  /// [horizontalPadding] and no more until the bar stops filling the window,
  /// after which the capped content is centred and takes the rest. The host
  /// stands the button that brings a hidden bar back on this same number, which
  /// is what keeps it in the cog's column at every width.
  static double chromeInset(BuildContext context) {
    final available = MediaQuery.sizeOf(context).width - horizontalPadding * 2;
    return horizontalPadding + math.max(0, available - maxContentWidth(context)) / 2;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: horizontalPadding),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxContentWidth(context)),
            child: Row(
              children: [
                const AppLogo(),
                const SizedBox(width: 12),
                // MUST be the only flexible child: a second would share the free
                // space and leave its unused half *after* the cog.
                Expanded(
                  child: FadeThrough(
                    child: KeyedSubtree(
                      // Keyed on what the trail *says*. A screen that rebuilds
                      // without changing its trail hands over an equal key, which
                      // is an update rather than a swap and so does not fade.
                      key: ValueKey('$version/${crumbs.map((crumb) => crumb.label).join('›')}'),
                      // A long trail scrolls rather than overflowing. Anchored at
                      // the start, so a short trail sits against the logo;
                      // `reverse` would park it at the right instead.
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: _buildTrail(context),
                      ),
                    ),
                  ),
                ),
                // The screen's own chrome and the hide button fade as one group, and
                // the group's width is animated: a bar that changed width the
                // instant the last of it faded out would jump the cog sideways.
                AnimatedSize(
                  duration: context.motion(FadeThrough.duration),
                  curve: Curves.easeOutCubic,
                  child: FadeThrough(child: _buildChrome(context)),
                ),
                const SizedBox(width: _gap),
                const SettingsMenu(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Everything between the trail and the cog, or null when this screen has
  /// nothing to put there.
  Widget? _buildChrome(BuildContext context) {
    if (trailing == null && onHide == null) return null;

    return Row(
      key: ValueKey('${trailing != null}/${onHide != null}'),
      mainAxisSize: MainAxisSize.min,
      children: [
        if (trailing case final Widget trailing) ...[
          const SizedBox(width: _gap),
          trailing,
        ],
        if (onHide case final VoidCallback onHide) ...[
          const SizedBox(width: _gap),
          HeaderIconButton(
            // The glyph names what pressing it does: closing the top panel away.
            icon: FLucideIcons.panelTopClose,
            semanticsLabel: context.localizations.appHeader_hideBar,
            onPress: onHide,
          ),
        ],
      ],
    );
  }

  Widget _buildTrail(BuildContext context) {
    return DefaultTextStyle(
      style: context.appTheme.text.h3.copyWith(fontSize: 18, fontWeight: FontWeight.w800),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        // The version is a second word on the same line, so it sits on the same
        // baseline. Centring is what the row does by default, and centring two
        // boxes of different type sizes lines up neither the letters nor the
        // tops — it leaves the smaller one sitting a little low.
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          _buildCrumbs(context),
          // Beside the trail rather than inside the first crumb: the crumb is
          // the app's *name*, and a version tacked onto it would be read out as
          // part of it and carried into every screen's trail.
          if (version case final String version) ...[
            const SizedBox(width: 10),
            Text(
              'v$version',
              style: context.appTheme.text.bodySmall.copyWith(
                fontSize: 14,
                color: context.theme.colors.mutedForeground,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCrumbs(BuildContext context) {
    return FBreadcrumb(
      children: [
        FBreadcrumbItem(
          current: crumbs.isEmpty,
          onPress: onTapHome,
          child: Text(context.localizations.app_title),
        ),
        for (final (index, crumb) in crumbs.indexed)
          FBreadcrumbItem(
            current: index == crumbs.length - 1,
            onPress: crumb.onTap,
            child: Text(crumb.label),
          ),
      ],
    );
  }

}
