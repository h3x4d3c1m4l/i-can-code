import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_code/services/vm/vm_host_event.dart';
import 'package:i_can_code/services/vm/vm_runtime.dart';

/// Host run 7 is this runtime's run 1; any other host run is unknown to it.
int? _runs(int host) => host == 7 ? 1 : null;

VmEvent? _parse(Map<String, Object?> event) => parseHostEvent(event, runId: _runs);

void main() {
  // The shapes below are the ones `web/vm/vm_host.js` documents on its `Vm`
  // class. Numbers are doubles, because that is what `dartify()` hands back for
  // a JS number whichever compiler built the page.

  test('download progress keeps both counts', () {
    final event = _parse({'type': 'progress', 'loaded': 1048576.0, 'total': 20971520.0});

    expect(event, isA<VmLoadProgress>().having((e) => e.loaded, 'loaded', 1048576).having((e) => e.total, 'total', 20971520));
  });

  test('progress without the later fields is a download under way, kept, at no known speed', () {
    final event = _parse({'type': 'progress', 'loaded': 1.0, 'total': 2.0})! as VmLoadProgress;

    expect(event.phase, VmLoadPhase.download);
    expect(event.cached, 0);
    expect(event.bytesPerSecond, isNull);
    expect(event.remaining, isNull);
    expect(event.stalled, isFalse);
    expect(event.keeps, isTrue);
    expect(event.slowConnection, isFalse);
  });

  test('progress carries its phase, what was cached, the speed and the time left', () {
    VmLoadProgress parse(Map<String, Object?> fields) =>
        _parse({'type': 'progress', 'loaded': 5.0, 'total': 10.0, ...fields})! as VmLoadProgress;

    final downloading = parse({
      'phase': 'download',
      'cached': 2.0,
      'rate': 2300000.5,
      'remainingMs': 7400.0,
      'stalled': true,
      'keeps': false,
      'slowConnection': true,
    });
    expect(downloading.cached, 2);
    expect(downloading.bytesPerSecond, 2300000.5);
    expect(downloading.remaining, const Duration(milliseconds: 7400));
    expect(downloading.stalled, isTrue);
    expect(downloading.keeps, isFalse);
    expect(downloading.slowConnection, isTrue);

    expect(parse({'phase': 'unpack'}).phase, VmLoadPhase.unpack);
    expect(parse({'phase': 'start'}).phase, VmLoadPhase.start);
    expect(parse({'phase': 'something-new'}).phase, VmLoadPhase.download);
    expect(parse({'rate': null, 'remainingMs': null}).bytesPerSecond, isNull);
    expect(parse({'rate': 0.0}).bytesPerSecond, isNull, reason: 'no speed is no speed to quote');
  });

  test('ready carries what the guest calls its interpreter and Tk', () {
    final event = _parse({'type': 'ready', 'python': 'Python 3.12.12', 'tk': '8.6.16', 'imageId': 'abc'});

    expect(event, isA<VmReady>().having((e) => e.python, 'python', 'Python 3.12.12').having((e) => e.tk, 'tk', '8.6.16'));
  });

  test('every failure reason the host names is kept apart, and an unknown one is broken', () {
    VmFailure? failure(String reason) => (_parse({'type': 'failed', 'reason': reason, 'message': 'm'}) as VmFailed?)?.failure;

    expect(failure('network'), VmFailure.network);
    expect(failure('incompatible'), VmFailure.incompatible);
    expect(failure('fetch'), VmFailure.fetch);
    expect(failure('unresponsive'), VmFailure.unresponsive);
    expect(failure('replaced'), VmFailure.replaced);
    expect(failure('broken'), VmFailure.broken);
    expect(failure('something-new'), VmFailure.broken);
  });

  test('a run event is renumbered to the runtime\'s own id', () {
    final event = _parse({'type': 'started', 'run': 7.0, 'warm': true, 'pid': 312.0});

    expect(event, isA<VmRunStarted>().having((e) => e.runId, 'runId', 1).having((e) => e.warm, 'warm', isTrue));
  });

  test('an event about a run the runtime does not know is dropped', () {
    // A run from before a retry, or one whose id was never handed out here.
    expect(_parse({'type': 'output', 'run': 3.0, 'stream': 'stdout', 'text': 'hoi'}), isNull);
    expect(_parse({'type': 'ended', 'run': 3.0, 'reason': 'exit', 'code': 0.0}), isNull);
    expect(_parse({'type': 'output', 'stream': 'stdout', 'text': 'no run at all'}), isNull);
  });

  test('output says which stream it came from', () {
    final out = _parse({'type': 'output', 'run': 7.0, 'stream': 'stdout', 'text': 'Hallo\n'});
    final err = _parse({'type': 'output', 'run': 7.0, 'stream': 'stderr', 'text': 'Traceback'});

    expect(out, isA<VmOutput>().having((e) => e.text, 'text', 'Hallo\n').having((e) => e.fromStderr, 'stderr', isFalse));
    expect(err, isA<VmOutput>().having((e) => e.fromStderr, 'stderr', isTrue));
  });

  test('empty output is not an event', () {
    // The host flushes its decoders at a run's end, which can be nothing.
    expect(_parse({'type': 'output', 'run': 7.0, 'stream': 'stdout', 'text': ''}), isNull);
  });

  test('a window list keeps its order, its root and its dialogs', () {
    final event = _parse({
      'type': 'window',
      'run': 7.0,
      'windows': [
        {'xid': 4194310.0, 'title': 'My window', 'x': 0.0, 'y': 0.0, 'w': 320.0, 'h': 200.0, 'mapped': true, 'root': true, 'transient_for': null},
        {'xid': 4194400.0, 'title': 'Question', 'x': 100.0, 'y': 80.0, 'w': 200.0, 'h': 90.0, 'mapped': true, 'root': false, 'transient_for': 4194310.0},
        {'title': 'no xid, so no window'},
      ],
    });

    final windows = (event! as VmWindows).windows;
    expect(windows, hasLength(2));
    expect(windows.first.xid, 4194310);
    expect(windows.first.isRoot, isTrue);
    expect(windows.first.width, 320);
    expect(windows.last.transientFor, 4194310);
    expect(windows.last.title, 'Question');
  });

  test('the one hint v1 has is known, and any other is ignored', () {
    expect(_parse({'type': 'hint', 'run': 7.0, 'kind': 'tk_no_mainloop'}), isA<VmRunHint>().having((e) => e.hint, 'hint', VmHint.tkNoMainloop));
    // README 6.8: the host ignores kinds it does not know.
    expect(_parse({'type': 'hint', 'run': 7.0, 'kind': 'stdin_unavailable'}), isNull);
  });

  group('how a run ended', () {
    VmExit exit(Map<String, Object?> fields) => (_parse({'type': 'ended', 'run': 7.0, ...fields})! as VmRunEnded).exit;

    test('a program that ended by itself keeps its code and time', () {
      final ended = exit({'reason': 'exit', 'code': 0.0, 'signal': null, 'truncated': false, 'ms': 1234.0});

      expect(ended.reason, VmEndReason.exit);
      expect(ended.code, 0);
      expect(ended.duration, const Duration(milliseconds: 1234));
      expect(ended.failed, isFalse);
      expect(ended.stopped, isFalse);
    });

    test('a crash is the program failing, not the machine', () {
      final ended = exit({'reason': 'exit', 'code': 1.0});

      expect(ended.failed, isTrue);
      expect(ended.reason.isHarnessFailure, isFalse);
    });

    test('a stop is neither a failure nor the machine breaking', () {
      final ended = exit({'reason': 'stopped'});

      expect(ended.stopped, isTrue);
      expect(ended.failed, isFalse);
      expect(ended.reason.isHarnessFailure, isFalse);
    });

    test('the three harness reasons are harness failures and nothing else is', () {
      for (final reason in ['unresponsive', 'fetch', 'broken']) {
        final ended = exit({'reason': reason, 'message': 'No PONG to PING.'});
        expect(ended.reason.isHarnessFailure, isTrue, reason: reason);
        expect(ended.failed, isFalse, reason: '$reason is not the program failing');
      }
      for (final reason in ['exit', 'closed', 'oom', 'stopped']) {
        expect(exit({'reason': reason}).reason.isHarnessFailure, isFalse, reason: reason);
      }
    });

    test('an out-of-memory kill and a close are their own reasons', () {
      expect(exit({'reason': 'oom', 'signal': 9.0}).reason, VmEndReason.outOfMemory);
      expect(exit({'reason': 'closed', 'signal': 9.0}).reason, VmEndReason.closed);
      expect(exit({'reason': 'closed', 'signal': 9.0}).signal, 9);
    });

    test('a reason this page does not know is the harness, never the student', () {
      final ended = exit({'reason': 'from-a-newer-host'});

      expect(ended.reason, VmEndReason.broken);
      expect(ended.reason.isHarnessFailure, isTrue);
    });

    test('truncated output is kept', () {
      expect(exit({'reason': 'exit', 'code': 0.0, 'truncated': true}).truncated, isTrue);
    });
  });

  test('events the app has no use for are ignored', () {
    for (final type in ['parked', 'log', 'stop-answered', 'rootfs-fetched', 'fetch-failed', 'something-new']) {
      expect(_parse({'type': type, 'run': 7.0}), isNull, reason: type);
    }
  });
}
