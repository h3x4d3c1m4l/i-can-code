import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/services/python/python_attempt_runner.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/shape_metrics.dart';

/// One row per test of a pytest run: whether it passed, and pytest's reason
/// when it did not. On the same card as the output below it, which holds the
/// full report this summarises.
class TestResultList extends StatelessWidget {

  final List<TestOutcome> tests;

  const TestResultList({required this.tests, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final tokens = context.appTheme;

    return DecoratedBox(
      decoration: ShapeDecoration(
        color: theme.colors.card,
        shape: squircle(kCardCornerRadius, side: BorderSide(color: theme.colors.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.localizations.lessonScreen_tests.toUpperCase(),
              style: tokens.text.label.copyWith(fontSize: 12, color: theme.colors.mutedForeground),
            ),
            for (final test in tests) ...[
              const SizedBox(height: 12),
              _TestRow(test: test),
            ],
          ],
        ),
      ),
    );
  }

}

class _TestRow extends StatelessWidget {

  final TestOutcome test;

  const _TestRow({required this.test});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final tokens = context.appTheme;
    final l10n = context.localizations;

    final (icon, color, outcome) = switch (test.kind) {
      TestOutcomeKind.passed => (FLucideIcons.circleCheck, tokens.colors.success, l10n.lessonScreen_testPassed),
      TestOutcomeKind.failed => (FLucideIcons.circleX, tokens.colors.warning, l10n.lessonScreen_testFailed),
      TestOutcomeKind.error => (FLucideIcons.circleAlert, theme.colors.error, l10n.lessonScreen_testError),
      TestOutcomeKind.skipped => (FLucideIcons.circleDashed, theme.colors.mutedForeground, l10n.lessonScreen_testSkipped),
    };

    return MergeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Icon(icon, size: 18, color: color, semanticLabel: outcome),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(test.name, style: tokens.text.code.copyWith(fontSize: 15, height: 1.5)),
                if (test.message case final String message)
                  Text(
                    message,
                    style: tokens.text.code.copyWith(fontSize: 13, height: 1.5, color: theme.colors.mutedForeground),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

}
