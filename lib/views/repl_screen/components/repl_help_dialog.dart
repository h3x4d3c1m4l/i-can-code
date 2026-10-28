import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/views/components/app_button.dart';
import 'package:i_can_code/views/components/app_dialog.dart';
import 'package:i_can_code/views/components/scroll_card.dart';

/// Opens what the console is and which keys it answers to.
Future<void> showReplHelpDialog(BuildContext context) =>
    showAppDialog<void>(context, wide: true, builder: (context) => const _ReplHelpDialog());

class _ReplHelpDialog extends StatelessWidget {

  const _ReplHelpDialog();

  @override
  Widget build(BuildContext context) {
    final l10n = context.localizations;
    // Ctrl+Arrow switches desktops on a Mac, and Option+Arrow is what reaches
    // the page there.
    final wordModifier = switch (defaultTargetPlatform) {
      TargetPlatform.macOS || TargetPlatform.iOS => 'Option',
      _ => 'Ctrl',
    };

    return AppDialog(
      title: Text(l10n.replHelpDialog_title),
      // The text scrolls with the table rather than standing above it: on a
      // short window, or at a large text size, it left the table no room.
      content: ScrollCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DefaultTextStyle.merge(
              style: AppDialog.bodyStyle(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 10,
                children: [
                  Text(l10n.replHelpDialog_lines),
                  Text(l10n.replHelpDialog_names),
                  Text(l10n.replHelpDialog_blocks),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _KeyTable(
              rows: [
                (['Enter'], l10n.replHelpDialog_enter),
                ([l10n.replHelpDialog_upKey, l10n.replHelpDialog_downKey], l10n.replHelpDialog_history),
                (['Tab'], l10n.replHelpDialog_tab),
                (['Ctrl+A', 'Ctrl+E'], l10n.replHelpDialog_lineEnds),
                (
                  [l10n.replHelpDialog_wordBackKey(wordModifier), l10n.replHelpDialog_wordForwardKey(wordModifier)],
                  l10n.replHelpDialog_words,
                ),
                (['Ctrl+U', 'Ctrl+K', 'Ctrl+W'], l10n.replHelpDialog_erase),
                (['Ctrl+L'], l10n.replHelpDialog_clear),
                (['Ctrl+C'], l10n.replHelpDialog_interrupt),
                (['Ctrl+D'], l10n.replHelpDialog_endInput),
                ([l10n.replHelpDialog_leaveKeys], l10n.replHelpDialog_leave),
              ],
            ),
          ],
        ),
      ),
      actions: [
        AppButton(
          tone: AppButtonTone.neutral,
          onPress: () => Navigator.of(context).pop(),
          child: Text(l10n.replHelpDialog_close),
        ),
      ],
    );
  }

}

/// Keys on the left, one per line, and what they do on the right.
class _KeyTable extends StatelessWidget {

  static const double _fontSize = 16;

  final List<(List<String> keys, String meaning)> rows;

  const _KeyTable({required this.rows});

  @override
  Widget build(BuildContext context) {
    final text = context.appTheme.text;
    final meaningStyle = text.bodySmall.copyWith(fontSize: _fontSize);
    final keysStyle = meaningStyle.copyWith(fontWeight: FontWeight.w600);

    return Table(
      columnWidths: const {0: IntrinsicColumnWidth(), 1: FlexColumnWidth()},
      children: [
        for (final (keys, meaning) in rows)
          TableRow(
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.only(top: 5, bottom: 5, end: 20),
                child: Text(keys.join('\n'), style: keysStyle),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Text(meaning, style: meaningStyle),
              ),
            ],
          ),
      ],
    );
  }

}
