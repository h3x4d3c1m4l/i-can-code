import 'package:flutter/widgets.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/services/vm/vm_runtime.dart';
import 'package:i_can_code/views/components/output_card.dart';
import 'package:i_can_code/views/components/vm/run_notice.dart';
import 'package:i_can_code/views/components/vm/vm_session_view_model.dart';

/// What to know about the last run, then what it printed: a [RunNotice] for
/// each of the session's notices, and the output on an [OutputCard]. Nothing
/// before the first run.
///
/// Observes [session] itself. Each part stands 16 clear of what is above it.
class VmRunReport extends StatelessWidget {

  final VmSessionViewModel session;

  const VmRunReport({required this.session, super.key});

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (context) {
        final notices = session.notices;
        final output = session.visibleOutput;
        final incomplete = session.outputIncomplete;
        // Only the end fits on the card; the ellipsis says the start is missing.
        final clipped = output.length < session.output.length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final notice in notices) ...[
              const SizedBox(height: 16),
              RunNotice(text: _noticeText(context, notice), aboutTheProgram: notice.aboutTheProgram),
            ],
            if (output.trim().isNotEmpty) ...[
              const SizedBox(height: 16),
              OutputCard(
                label: context.localizations.tkinterScreen_output,
                // print() ends every line with a newline, which would otherwise
                // leave a blank line inside the card.
                text: '${clipped ? '…\n' : ''}${output.trimRight()}',
                note: incomplete ? context.localizations.tkinterScreen_truncated : null,
              ),
            ],
          ],
        );
      },
    );
  }

  static String _noticeText(BuildContext context, TkinterNotice notice) {
    final l10n = context.localizations;

    return switch (notice) {
      TkinterNotice.noMainloop => l10n.tkinterScreen_noMainloop,
      TkinterNotice.noInput => l10n.tkinterScreen_noInput,
      TkinterNotice.crashed => l10n.tkinterScreen_crashed,
      TkinterNotice.outOfMemory => l10n.tkinterScreen_outOfMemory,
      TkinterNotice.tooLarge => l10n.tkinterScreen_tooLarge(vmScreenSize.width.toInt(), vmScreenSize.height.toInt()),
      TkinterNotice.harnessBroken => l10n.tkinterScreen_harnessBroken,
      TkinterNotice.harnessFetch => l10n.tkinterScreen_harnessFetch,
      TkinterNotice.harnessUnresponsive => l10n.tkinterScreen_harnessUnresponsive,
    };
  }

}
