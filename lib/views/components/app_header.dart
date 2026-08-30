import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/views/components/app_logo.dart';
import 'package:i_can_code/views/components/settings_menu.dart';

/// One level of the trail in [AppHeader].
class AppCrumb {

  final String label;

  /// Null for a level that cannot be navigated to — the current page, or a
  /// grouping with no screen of its own.
  final VoidCallback? onTap;

  const AppCrumb(this.label, {this.onTap});

}

/// The bar every screen but the initialization screen carries: the mark and the
/// trail on the left, the screen's own chrome and the settings cog on the right.
/// The trail always starts at the app itself.
class AppHeader extends StatelessWidget {

  /// Levels below the app name: the language, the lesson, the step.
  final List<AppCrumb> crumbs;

  /// Tapping the app name goes home. Null on the screen that *is* home, so it
  /// does not offer to navigate to itself.
  final VoidCallback? onTapHome;

  /// Sits between the trail and the cog. The lesson screen puts its progress
  /// bar here.
  final Widget? trailing;

  const AppHeader({this.crumbs = const [], this.onTapHome, this.trailing, super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 76,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Row(
          children: [
            const AppLogo(),
            const SizedBox(width: 12),
            // MUST be the only flexible child: a second would share the free
            // space and leave its unused half *after* the cog.
            Expanded(
              // A long trail scrolls rather than overflowing. Anchored at the
              // start, so a short trail sits against the logo; `reverse` would
              // park it at the right instead.
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: _buildTrail(context),
              ),
            ),
            if (trailing case final Widget trailing) ...[
              const SizedBox(width: 20),
              trailing,
            ],
            const SizedBox(width: 20),
            const SettingsMenu(),
          ],
        ),
      ),
    );
  }

  Widget _buildTrail(BuildContext context) {
    return DefaultTextStyle(
      style: context.appTheme.text.h3.copyWith(fontSize: 18, fontWeight: FontWeight.w800),
      child: FBreadcrumb(
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
      ),
    );
  }

}
