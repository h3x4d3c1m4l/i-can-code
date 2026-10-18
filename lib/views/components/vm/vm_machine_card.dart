import 'package:flutter/widgets.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/services/vm/vm_runtime.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/shape_metrics.dart';
import 'package:i_can_code/views/components/app_button.dart';
import 'package:i_can_code/views/components/notice_card.dart';
import 'package:i_can_code/views/components/vm/vm_load_panel.dart';
import 'package:i_can_code/views/components/vm/vm_session_view_model.dart';

/// What the machine has to say for itself on the page: the download while it
/// runs, and what broke where it did. Nothing at all once it is ready, and
/// nothing while a program runs, which the run's dialog is showing.
///
/// Observes [session] itself. Whatever it shows stands 20 clear of what is
/// above it, and nothing does while it shows nothing.
class VmMachineCard extends StatelessWidget {

  /// The dark card the machine's own panel sits on while it loads, which is the
  /// frame's surface without the frame.
  static const double _loadCardHeight = 300;

  final VmSessionViewModel session;

  /// Builds a new machine in place of the one that failed.
  final VoidCallback onRetry;

  /// What the card says under its title in a build without the machine's image.
  /// The screen's own words, because only the screen knows what still works
  /// there without the machine.
  final String notIncludedBody;

  /// The same, in a browser that cannot host the machine.
  final String unavailableBody;

  const VmMachineCard({
    required this.session,
    required this.onRetry,
    required this.notIncludedBody,
    required this.unavailableBody,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (context) {
        if (session.running) return const SizedBox.shrink();

        final Widget? card = switch (session.machine) {
          TkinterMachine.ready => null,
          TkinterMachine.loading => _buildLoadCard(context),
          // Said rather than hidden: a page that silently is not there reads as
          // a broken app.
          TkinterMachine.unavailable => NoticeCard(
            title: context.localizations.tkinterScreen_unavailableTitle,
            body: unavailableBody,
          ),
          TkinterMachine.notIncluded => NoticeCard(
            title: context.localizations.tkinterScreen_notIncludedTitle,
            body: notIncludedBody,
          ),
          TkinterMachine.failed => _buildFailure(context),
        };
        if (card == null) return const SizedBox.shrink();

        return Padding(padding: const EdgeInsets.only(top: 20), child: card);
      },
    );
  }

  /// The machine's own panel on the surface the frame would have given it, so
  /// the download reads as part of the machine rather than as a page of its own.
  Widget _buildLoadCard(BuildContext context) {
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: context.appTheme.colors.codeBackground,
        shape: squircle(kCardCornerRadius),
      ),
      child: SizedBox(height: _loadCardHeight, child: VmLoadPanel(progress: session.loadProgress)),
    );
  }

  /// Worded for what broke. None of it is the student's doing, and every one of
  /// them says so. The machine's own message is English and for whoever helps,
  /// so it stays folded under the card.
  Widget _buildFailure(BuildContext context) {
    final l10n = context.localizations;
    final message = session.failureMessage;

    final (title, body) = switch (session.failure) {
      VmFailure.network || VmFailure.fetch => (
        l10n.tkinterScreen_downloadFailedTitle,
        l10n.tkinterScreen_downloadFailedBody,
      ),
      VmFailure.incompatible => (l10n.tkinterScreen_incompatibleTitle, l10n.tkinterScreen_incompatibleBody),
      VmFailure.replaced => (l10n.tkinterScreen_replacedTitle, l10n.tkinterScreen_replacedBody),
      VmFailure.unresponsive || VmFailure.broken || null => (
        l10n.tkinterScreen_brokenTitle,
        l10n.tkinterScreen_brokenBody,
      ),
    };

    return NoticeCard(
      title: title,
      body: body,
      detail: message == null || message.isEmpty ? null : message,
      detailLabel: l10n.tkinterScreen_failureDetails,
      action: AppButton(
        tone: AppButtonTone.neutral,
        onPress: onRetry,
        child: Text(l10n.tkinterScreen_retry),
      ),
    );
  }

}
