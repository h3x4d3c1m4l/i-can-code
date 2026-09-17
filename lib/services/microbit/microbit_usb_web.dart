import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// DAPLink on a micro:bit. Vendor 0x0D28 is Arm; product 0x0204 is the board.
/// The same pair the Rust core filters on.
const int _microbitVendorId = 0x0D28;
const int _microbitProductId = 0x0204;

/// `navigator.usb`, typed by hand because `package:web` 1.1.1 ships no WebUSB
/// bindings.
///
/// Only the members the page needs. Everything else about a device is the Rust
/// core's business.
extension type _Usb(JSObject _) implements JSObject {

  external JSPromise<JSObject> requestDevice(_UsbRequestOptions options);

}

extension type _UsbRequestOptions._(JSObject _) implements JSObject {

  external factory _UsbRequestOptions({JSArray<_UsbDeviceFilter> filters});

}

extension type _UsbDeviceFilter._(JSObject _) implements JSObject {

  external factory _UsbDeviceFilter({int vendorId, int productId});

}

extension type _NavigatorWithUsb(JSObject _) implements JSObject {

  external _Usb? get usb;

}

_NavigatorWithUsb get _navigator => web.window.navigator as _NavigatorWithUsb;

/// Whether this browser has WebUSB at all. False in Firefox and Safari.
bool get webUsbAvailable => _navigator.usb != null;

/// Asks the reader to pick their micro:bit, granting this origin permission.
///
/// MUST be called from a user gesture on the main thread, and MUST NOT move into
/// the Rust core: `requestDevice()` exists only in `Window` scope. The resolved
/// device is thrown away, because holding it open makes the worker's `open()`
/// fail. False means the reader dismissed the picker.
Future<bool> requestMicrobitAccess() async {
  final usb = _navigator.usb;
  if (usb == null) {
    return false;
  }

  final options = _UsbRequestOptions(
    filters: <_UsbDeviceFilter>[
      _UsbDeviceFilter(vendorId: _microbitVendorId, productId: _microbitProductId),
    ].toJS,
  );

  try {
    await usb.requestDevice(options).toDart;
    return true;
  } on Object {
    // `NotFoundError` when dismissed, `SecurityError` when the call did not
    // come from a gesture. Neither needs a different answer: nothing was chosen.
    return false;
  }
}
