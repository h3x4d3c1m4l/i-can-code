// The web host is the only one that exists. Everything else, including the Dart
// VM that `flutter test` runs on, falls through to the stub.
import 'package:i_can_code/services/microbit/microbit_link_stub.dart'
    if (dart.library.js_interop) 'package:i_can_code/services/microbit/microbit_link_web.dart' as impl;

/// Which generation of micro:bit a board id names.
enum MicrobitBoardVersion { v1, v2 }

/// Where a board id came from.
///
/// Only the vendor command survives a browser anonymizing the USB serial
/// number, so which answered says whether that is happening.
enum MicrobitIdSource {

  /// Read over CMSIS-DAP, from the interface chip itself.
  vendorCommand,

  /// The USB descriptor's serial number, used when the vendor command is
  /// silent.
  usbSerial,

  /// Neither answered anything a board id could be read out of.
  unknown,

}

/// Why talking to a board did not work. Each case needs different words on
/// screen.
enum MicrobitFailure {

  /// Nothing to talk to: unplugged, or permission never granted.
  noDevice,

  /// Another tab, MakeCode or a stray `pyocd` holds the debug interface.
  busy,

  /// Most likely a micro:bit V1, which cannot run the MicroPython this app
  /// flashes.
  unsupportedBoard,

  /// The conversation itself went wrong.
  protocol,

}

/// A micro:bit this origin has permission for, as the USB descriptor describes
/// it.
///
/// Every field is nullable: a browser may withhold the serial number, which
/// takes the board id with it, and the screen still has to name the device.
class MicrobitDevice {

  /// What the device calls itself, such as "BBC micro:bit CMSIS-DAP".
  final String? product;

  /// The full DAPLink serial as reported over USB.
  final String? serialNumber;

  /// Four hex characters, e.g. `9906`.
  final String? boardId;

  final MicrobitBoardVersion? boardVersion;

  const MicrobitDevice({this.product, this.serialNumber, this.boardId, this.boardVersion});

}

/// What an opened board answered about itself, read over the wire rather than
/// out of the USB descriptor.
class MicrobitBoardInfo {

  /// `DAP_Info` vendor name, such as "Arm".
  final String? vendor;

  /// `DAP_Info` product name, such as "DAPLink CMSIS-DAP".
  final String? product;

  /// The CMSIS-DAP protocol version the firmware implements.
  final String? protocolVersion;

  /// The full 48-character DAPLink unique id.
  final String? uniqueId;

  /// Four hex characters, e.g. `9906`.
  final String? boardId;

  final MicrobitBoardVersion? boardVersion;

  final MicrobitIdSource idSource;

  /// Bytes in one flash page, read out of Nordic's FICR over SWD. 4096 on the
  /// nRF52833 in a micro:bit V2.
  final int pageSize;

  /// How many pages the target's flash has. 128 on an nRF52833.
  final int pageCount;

  const MicrobitBoardInfo({
    required this.idSource,
    this.pageSize = 0,
    this.pageCount = 0,
    this.vendor,
    this.product,
    this.protocolVersion,
    this.uniqueId,
    this.boardId,
    this.boardVersion,
  });

  /// The whole flash, in bytes. 512 KB on a micro:bit V2.
  int get flashBytes => pageSize * pageCount;

}

/// Something the session has to tell the screen.
sealed class MicrobitEvent {

  const MicrobitEvent();

}

/// A board is open and has answered.
class MicrobitConnected extends MicrobitEvent {

  final MicrobitBoardInfo info;

  const MicrobitConnected(this.info);

}

/// Text the target printed, decoded incrementally so a UTF-8 sequence split
/// across two reads arrives as one character.
class MicrobitOutput extends MicrobitEvent {

  final String text;

  const MicrobitOutput(this.text);

}

/// The board was let go of, by request or because the cable came out. The
/// session is still running and can connect again.
class MicrobitDisconnected extends MicrobitEvent {

  const MicrobitDisconnected();

}

/// Connecting or talking failed.
///
/// Arrives here, never as a stream error: a stream that ends on the first
/// problem cannot report the next one.
class MicrobitFailed extends MicrobitEvent {

  final MicrobitFailure failure;

  /// Untranslated, for whoever is debugging. The screen picks its sentence from
  /// [failure].
  final String message;

  const MicrobitFailed(this.failure, this.message);

}

/// The app's side of a BBC micro:bit on the other end of a USB cable.
///
/// Created by the screen that uses it rather than registered in
/// `setupServices()`, like `PythonRepl`: connecting needs a user gesture and may
/// never happen.
abstract class MicrobitLink {

  /// False where this browser cannot host the Rust core at all.
  ///
  /// The core is wasm with shared memory, so it needs a cross-origin isolated
  /// page. See `web/coi-serviceworker.js`.
  bool get isSupported;

  /// Everything the session produces. Broadcast, and closed on dispose.
  Stream<MicrobitEvent> get events;

  /// Whether this browser has a USB transport at all.
  ///
  /// On the web that is `navigator.usb`, which Firefox and Safari lack. Says
  /// nothing about a board being plugged in or permitted; both of those are an
  /// empty device list.
  Future<bool> transportAvailable();

  /// Asks the reader to pick their micro:bit, granting this origin permission.
  ///
  /// The caller MUST invoke this from a user gesture; WebUSB otherwise refuses
  /// in a way that looks like a cancellation. False means the reader dismissed
  /// the picker, which is not a failure.
  Future<bool> requestAccess();

  /// Every micro:bit this origin already has permission for.
  ///
  /// Empty until [requestAccess] has succeeded once. Opens nothing, so a board
  /// another tab is holding still appears.
  Future<List<MicrobitDevice>> listDevices();

  /// Opens the first board and holds it for the session.
  ///
  /// Returns once the request is queued. The outcome arrives on [events] as
  /// [MicrobitConnected] or [MicrobitFailed].
  Future<void> connect();

  /// Sends [text] to the target's UART, verbatim.
  ///
  /// The caller MUST include the newline that ends a line. Nothing is written to
  /// the screen here; MicroPython echoes, and that echo arrives as output.
  void write(String text);

  /// Starts the board over with a hard reset, so it boots and runs `main.py`
  /// again.
  ///
  /// The boot output arrives on [events]. This is also what produces a
  /// connection's first output, since MicroPython says nothing unasked.
  Future<void> restart();

  /// Lets the board go without ending the session.
  Future<void> disconnect();

  void dispose();

}

/// The link for this platform.
MicrobitLink createMicrobitLink() => impl.createMicrobitLink();
