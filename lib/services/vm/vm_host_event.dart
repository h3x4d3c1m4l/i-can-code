import 'package:i_can_code/services/vm/vm_runtime.dart';

/// Reads one event of `web/vm/vm_host.js`, already converted to Dart.
///
/// Platform-neutral so `flutter test` can hold it to the host's event shapes;
/// the web runtime converts each JS object with `dartify()` and hands it here.
/// The shapes are the `Vm` class comment in `vm_host.js`.
///
/// [runId] turns the host's run id into the runtime's own; null drops an event
/// about a run this runtime does not know. Returns null for events the app has
/// no use for (`parked`, `log` and the diagnostics) and for anything malformed.
VmEvent? parseHostEvent(Map<Object?, Object?> event, {required int? Function(int hostRunId) runId}) {
  final type = event['type'];

  switch (type) {
    case 'progress':
      final rate = event['rate'];
      final remainingMs = _int(event['remainingMs']);
      return VmLoadProgress(
        _int(event['loaded']) ?? 0,
        _int(event['total']) ?? 0,
        phase: switch (event['phase']) {
          'unpack' => VmLoadPhase.unpack,
          'start' => VmLoadPhase.start,
          // A phase this page does not know is still a load under way.
          _ => VmLoadPhase.download,
        },
        cached: _int(event['cached']) ?? 0,
        bytesPerSecond: rate is num && rate.isFinite && rate > 0 ? rate.toDouble() : null,
        remaining: remainingMs == null || remainingMs < 0 ? null : Duration(milliseconds: remainingMs),
        stalled: event['stalled'] == true,
        keeps: event['keeps'] != false,
        slowConnection: event['slowConnection'] == true,
      );
    case 'ready':
      return VmReady(python: _string(event['python']), tk: _string(event['tk']));
    case 'failed':
      return VmFailed(_failure(event['reason']), _string(event['message']) ?? '');
  }

  final hostRun = _int(event['run']);
  if (hostRun == null) return null;
  final id = runId(hostRun);
  if (id == null) return null;

  switch (type) {
    case 'started':
      return VmRunStarted(id, warm: event['warm'] != false);
    case 'output':
      final text = _string(event['text']);
      if (text == null || text.isEmpty) return null;
      return VmOutput(id, text, fromStderr: event['stream'] == 'stderr');
    case 'window':
      final windows = event['windows'];
      if (windows is! List) return null;
      return VmWindows(id, [
        for (final window in windows)
          if (window is Map) ?_window(window),
      ]);
    case 'hint':
      return switch (event['kind']) {
        'tk_no_mainloop' => VmRunHint(id, VmHint.tkNoMainloop),
        // README 6.8: the host ignores kinds it does not know, and so does this.
        _ => null,
      };
    case 'ended':
      return VmRunEnded(id, exitFromHost(event));
  }
  return null;
}

/// The run-level half of an `ended` event, which is also what the host's
/// `run().ended` promise resolves with.
VmExit exitFromHost(Map<Object?, Object?> event) {
  final ms = _int(event['ms']);

  return VmExit(
    reason: switch (event['reason']) {
      'exit' => VmEndReason.exit,
      'closed' => VmEndReason.closed,
      'oom' => VmEndReason.outOfMemory,
      'stopped' => VmEndReason.stopped,
      'unresponsive' => VmEndReason.unresponsive,
      'fetch' => VmEndReason.fetch,
      // A reason this page does not know is a harness it does not know either,
      // and that MUST NOT read as the student's mistake.
      _ => VmEndReason.broken,
    },
    code: _int(event['code']),
    signal: _int(event['signal']),
    truncated: event['truncated'] == true,
    duration: ms == null ? null : Duration(milliseconds: ms),
    message: _string(event['message']),
  );
}

VmWindow? _window(Map<Object?, Object?> window) {
  final xid = _int(window['xid']);
  if (xid == null) return null;

  return VmWindow(
    xid: xid,
    title: _string(window['title']) ?? '',
    x: _int(window['x']) ?? 0,
    y: _int(window['y']) ?? 0,
    width: _int(window['w']) ?? 0,
    height: _int(window['h']) ?? 0,
    mapped: window['mapped'] == true,
    isRoot: window['root'] == true,
    transientFor: _int(window['transient_for']),
  );
}

VmFailure _failure(Object? reason) => switch (reason) {
  'network' => VmFailure.network,
  'incompatible' => VmFailure.incompatible,
  'fetch' => VmFailure.fetch,
  'unresponsive' => VmFailure.unresponsive,
  'replaced' => VmFailure.replaced,
  _ => VmFailure.broken,
};

/// A JS number comes back as a `double` from `dartify()`, whichever compiler
/// built the page.
int? _int(Object? value) => value is num && value.isFinite ? value.round() : null;

String? _string(Object? value) => value is String ? value : null;
