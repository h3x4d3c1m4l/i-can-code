import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/shape_metrics.dart';

/// A sentence about how the last run went.
///
/// Two looks, and which one is the whole point: something about the student's
/// program ([aboutTheProgram]) sits on the warning surface, and a failure of
/// the machine sits on a plain card, because it MUST NOT read as the student's
/// mistake. Neither is a verdict; nothing on this page is checked.
class RunNotice extends StatelessWidget {

  final String text;

  final bool aboutTheProgram;

  const RunNotice({required this.text, required this.aboutTheProgram, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final tokens = context.appTheme;

    return DecoratedBox(
      decoration: ShapeDecoration(
        color: aboutTheProgram ? tokens.colors.warningSurface : theme.colors.card,
        shape: squircle(
          kCardCornerRadius,
          side: aboutTheProgram ? BorderSide.none : BorderSide(color: theme.colors.border),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        child: Text(text, style: tokens.text.bodySmall.copyWith(fontSize: 16, color: theme.colors.foreground)),
      ),
    );
  }

}
