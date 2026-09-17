import 'dart:async';
import 'dart:convert';

import 'package:i_can_code/services/microbit/microbit_firmware.dart';
import 'package:i_can_code/services/microbit/microbit_link.dart';
import 'package:i_can_code/services/microbit/microbit_usb_web.dart';
import 'package:i_can_code/src/rust/api/microbit.dart' as core;
import 'package:i_can_code/src/rust/api/types.dart' as core_types;
import 'package:i_can_code/src/rust/frb_generated.dart';
import 'package:web/web.dart' as web;

MicrobitLink createMicrobitLink() => WebMicrobitLink();

/// The Rust core, running as wasm on a flutter_rust_bridge worker.
///
/// Owns `RustLib.init()`, which no other layer may call. Loading the core is not
/// an initialization step: a student who never plugs in a board should neither
/// wait for it nor see it fail.
class WebMicrobitLink implements MicrobitLink {

  /// Numbers the sessions this page has started.
  ///
  /// The core's command queue is shared by every link on the page, so a stop has
  /// to name the session it means. Two screens are alive at once whenever one
  /// replaces the other.
  static int _sessions = 0;

  final StreamController<MicrobitEvent> _events = StreamController<MicrobitEvent>.broadcast();

  /// Which session this link runs, and the only one its stop may end.
  final int _sessionId = ++_sessions;

  /// Loading the core, shared by every link on the page.
  ///
  /// Static because the core is loaded once per page and `RustLib.init()` throws
  /// on a second call. Two screens hold a link at the same time whenever one
  /// replaces the other.
  static Future<void>? _starting;
  StreamSubscription<core_types.MicrobitEvent>? _session;
  bool _disposed = false;

  /// Turns the session's bytes into text.
  ///
  /// Chunked because MicroPython can split one UTF-8 sequence across two reads.
  /// `allowMalformed` keeps a broken byte from throwing mid-session.
  late final ByteConversionSink _decoder = const Utf8Decoder(allowMalformed: true).startChunkedConversion(
    _DecodedSink(_onText),
  );

  /// The core needs a cross-origin isolated page for its shared memory, and the
  /// transport needs `navigator.usb`. Either one missing is answered here rather
  /// than at a button press.
  @override
  bool get isSupported => web.window.crossOriginIsolated && webUsbAvailable;

  @override
  Stream<MicrobitEvent> get events => _events.stream;

  @override
  Future<bool> transportAvailable() async {
    if (!isSupported || !await _load()) {
      return false;
    }

    return core.microbitTransportAvailable();
  }

  /// Stays on the main thread: `requestDevice()` exists only in `Window` scope.
  /// The core sees the effect through `getDevices()`, not the call.
  @override
  Future<bool> requestAccess() => requestMicrobitAccess();

  @override
  Future<List<MicrobitDevice>> listDevices() async {
    if (!isSupported || !await _load()) {
      return const [];
    }

    final devices = await core.microbitListDevices();

    return devices
        .map(
          (d) => MicrobitDevice(
            product: d.product,
            serialNumber: d.serialNumber,
            boardId: d.boardId,
            boardVersion: _version(d.boardVersion),
          ),
        )
        .toList();
  }

  @override
  Future<void> connect({bool interrupt = false}) async {
    if (!isSupported) {
      _emit(const MicrobitFailed(MicrobitFailure.noDevice, 'no USB transport in this browser'));
      return;
    }

    if (!await _load()) {
      return;
    }

    await _ensureSession();

    await core.microbitSendCommand(command: core_types.MicrobitCommand.connect(interrupt: interrupt));
  }

  @override
  void write(String text) {
    if (_session == null) {
      return;
    }

    unawaited(
      core.microbitSendCommand(
        command: core_types.MicrobitCommand.write(data: utf8.encode(text)),
      ),
    );
  }

  @override
  Future<void> flash(String mainPy) async {

    if (_session == null) {
      return;
    }

    // The firmware is read here rather than in the core, which has no way to
    // reach a Flutter asset.
    final firmware = await loadMicrobitFirmware();

    await core.microbitSendCommand(
      command: core_types.MicrobitCommand.flash(firmware: firmware, mainPy: mainPy),
    );
  }

  @override
  Future<void> restart({bool interrupt = false}) async {
    if (_session == null) {
      return;
    }

    await core.microbitSendCommand(command: core_types.MicrobitCommand.restart(interrupt: interrupt));
  }

  @override
  Future<void> disconnect() async {
    if (_session == null) {
      return;
    }

    await core.microbitSendCommand(command: const core_types.MicrobitCommand.disconnect());
  }

  /// Starts the session loop, once.
  ///
  /// Subscribing starts it: the Rust side runs for as long as this stream has a
  /// listener.
  Future<void> _ensureSession() async {
    if (_session != null) {
      return;
    }

    _session = core.microbitRunSession(session: BigInt.from(_sessionId)).listen(
      _onCoreEvent,
      // The session reports its own failures as events, so an error here is the
      // bridge giving up rather than the board.
      onError: (Object error) => _emit(MicrobitFailed(MicrobitFailure.protocol, error.toString())),
      onDone: () => _emit(const MicrobitDisconnected()),
    );
  }

  void _onCoreEvent(core_types.MicrobitEvent event) {
    switch (event) {
      case core_types.MicrobitEvent_Connected(:final info):
        _emit(
          MicrobitConnected(
            MicrobitBoardInfo(
              vendor: info.vendor,
              product: info.product,
              protocolVersion: info.protocolVersion,
              uniqueId: info.uniqueId,
              boardId: info.boardId,
              boardVersion: _version(info.boardVersion),
              idSource: switch (info.idSource) {
                core_types.MicrobitIdSource.vendorCommand => MicrobitIdSource.vendorCommand,
                core_types.MicrobitIdSource.usbSerial => MicrobitIdSource.usbSerial,
                core_types.MicrobitIdSource.unknown => MicrobitIdSource.unknown,
              },
              pageSize: info.pageSize,
              pageCount: info.pageCount,
            ),
          ),
        );
      case core_types.MicrobitEvent_Serial(:final data):
        _decoder.add(data);
      case core_types.MicrobitEvent_FlashPlan(:final changed, :final total):
        _emit(MicrobitFlashPlan(changed, total));
      case core_types.MicrobitEvent_FlashPlanUnknown(:final message):
        _emit(MicrobitFlashPlanUnknown(message));
      case core_types.MicrobitEvent_FlashProgress(:final fraction):
        _emit(MicrobitFlashProgress(fraction));
      case core_types.MicrobitEvent_Flashed():
        _emit(const MicrobitFlashed());
      case core_types.MicrobitEvent_Disconnected():
        _emit(const MicrobitDisconnected());
      case core_types.MicrobitEvent_Failed(:final failure, :final message):
        _emit(
          MicrobitFailed(
            switch (failure) {
              core_types.MicrobitFailure.noDevice => MicrobitFailure.noDevice,
              core_types.MicrobitFailure.busy => MicrobitFailure.busy,
              core_types.MicrobitFailure.unsupportedBoard => MicrobitFailure.unsupportedBoard,
              core_types.MicrobitFailure.protocol => MicrobitFailure.protocol,
            },
            message,
          ),
        );
    }
  }

  void _onText(String text) => _emit(MicrobitOutput(text));

  void _emit(MicrobitEvent event) {
    if (!_disposed && !_events.isClosed) {
      _events.add(event);
    }
  }

  /// Loads the core, and says whether it is there.
  ///
  /// False means it is not, and the reason has already gone out as a failure.
  /// Nothing may call into the core afterwards. A hot restart is the case that
  /// makes this worth having: the wasm keeps running while Dart starts over, so
  /// the core refuses to be initialized a second time and every call after that
  /// would throw into whoever happened to be awaiting it.
  Future<bool> _load() async {
    try {
      await _ensureStarted();
      return true;
    } catch (error) {
      _emit(MicrobitFailed(MicrobitFailure.protocol, 'the core could not be loaded: $error'));
      return false;
    }
  }

  /// Loads the core once for the page, however many links ask.
  ///
  /// `RustLib.init()` throws `StateError` on a second call, so the future is
  /// shared. A failed one is dropped: flutter_rust_bridge only marks itself
  /// initialized once the wasm has loaded, so a retry is allowed.
  Future<void> _ensureStarted() async {
    final starting = _starting ??= RustLib.init();

    try {
      await starting;
    } catch (_) {
      _starting = null;
      rethrow;
    }
  }

  @override
  void dispose() {
    _disposed = true;

    // Before unsubscribing: the loop checks its queue every pass, so this is
    // what makes it return promptly.
    if (_session != null) {
      unawaited(core.microbitSendCommand(command: core_types.MicrobitCommand.stop(session: BigInt.from(_sessionId))));
    }

    unawaited(_session?.cancel());
    _session = null;
    unawaited(_events.close());
  }

  static MicrobitBoardVersion? _version(core_types.MicrobitBoardVersion? version) => switch (version) {
    core_types.MicrobitBoardVersion.v1 => MicrobitBoardVersion.v1,
    core_types.MicrobitBoardVersion.v2 => MicrobitBoardVersion.v2,
    null => null,
  };

}

/// Where the incremental decoder puts what it finished decoding.
class _DecodedSink implements Sink<String> {

  final void Function(String) _onText;

  const _DecodedSink(this._onText);

  @override
  void add(String data) => _onText(data);

  @override
  void close() {}

}
