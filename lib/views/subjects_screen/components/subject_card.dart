import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/services/lessons/course_icon.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/shape_metrics.dart';
import 'package:i_can_code/views/components/bevelled_card.dart';
import 'package:i_can_code/views/components/completed_badge.dart';
import 'package:i_can_code/views/components/duotone_icon.dart';

/// One subject on the home screen: a tile, its name, and how many of its
/// lessons are done.
///
/// An unavailable subject is drawn as an outline rather than hidden, so the
/// shape of the course stays visible.
class SubjectCard extends StatelessWidget {

  /// The gap between two cards in a list, measured from face to face. The
  /// collar under the upper card takes [BevelledCard.collarHeight] of it.
  static const double spacing = 20;

  static const double _tileSize = 58;
  static const double _iconSize = 40;

  /// What the tile shows when there is no [icon]. Short, because the tile is
  /// 58px square.
  final String label;

  /// The subject's own icon, drawn in the tile in place of [label]. Null for a
  /// subject this app has no icon for.
  final CourseIcon? icon;

  final String title;

  /// The count on the right. Replaced by a tick once [finished] is set.
  final String meta;

  /// Every lesson of the subject is done.
  final bool finished;

  /// Null while the subject cannot be opened yet.
  final VoidCallback? onTap;

  const SubjectCard({
    required this.label,
    required this.title,
    required this.meta,
    this.icon,
    this.finished = false,
    this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;

    return BevelledCard(
      onPress: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Row(
          children: [
            _buildTile(context),
            const SizedBox(width: 22),
            Expanded(child: Text(title, style: context.appTheme.text.h3)),
            const SizedBox(width: 16),
            if (finished)
              const CompletedBadge()
            else
              Text(
                meta,
                style: context.appTheme.text.bodySmall.copyWith(fontSize: 16, color: theme.colors.mutedForeground),
              ),
          ],
        ),
      ),
    );
  }

  /// A window onto the page, the way a catalog tile holds its picture.
  Widget _buildTile(BuildContext context) {
    final theme = context.theme;

    return SizedBox.square(
      dimension: _tileSize,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: theme.colors.background,
          shape: squircleOf(kControlCornerRadius - 2, size: _tileSize),
        ),
        child: Center(
          child: switch (icon) {
            final CourseIcon icon => DuotoneIcon(icon, size: _iconSize),
            null => Text(
              label,
              style: context.appTheme.text.code.copyWith(fontSize: 22, height: 1, color: theme.colors.foreground),
            ),
          },
        ),
      ),
    );
  }

}
