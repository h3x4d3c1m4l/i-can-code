import 'package:i_can_code/l10n/generated/app_localizations.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/views/components/vm/vm_session_view_model.dart';

/// The strip over the editor whose program [session] runs: what the machine is
/// doing, and once it is ready, what it runs.
///
/// It reads [session], so a caller MUST call it inside an Observer's build.
String vmStatusLabel(AppLocalizations l10n, VmSessionViewModel session) {
  final machine = session.machine;

  if (session.running) {
    return machine == TkinterMachine.ready ? l10n.tkinterScreen_statusRunning : l10n.tkinterScreen_statusWaiting;
  }

  final progress = session.loadProgress;
  return switch (machine) {
    TkinterMachine.loading when progress != null && progress.downloaded => l10n.tkinterScreen_statusStarting,
    TkinterMachine.loading => l10n.tkinterScreen_statusLoading,
    // The machine names itself; until it has, the subject stands in.
    TkinterMachine.ready => session.interpreterLabel ?? subjectLabel(session.subject),
    TkinterMachine.failed || TkinterMachine.unavailable || TkinterMachine.notIncluded =>
      subjectLabel(session.subject),
  };
}
