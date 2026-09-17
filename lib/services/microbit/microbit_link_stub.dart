import 'package:i_can_code/services/microbit/microbit_link.dart';

MicrobitLink createMicrobitLink() => UnsupportedMicrobitLink();

/// Stands in where the Rust core cannot run, which is every platform but the
/// web.
///
/// Never throws, so a screen builds and explains itself instead of crashing a
/// widget test.
class UnsupportedMicrobitLink implements MicrobitLink {

  @override
  bool get isSupported => false;

  @override
  Stream<MicrobitEvent> get events => const Stream<MicrobitEvent>.empty();

  @override
  Future<bool> transportAvailable() async => false;

  @override
  Future<bool> requestAccess() async => false;

  @override
  Future<List<MicrobitDevice>> listDevices() async => const [];

  @override
  Future<void> connect({bool interrupt = false}) async {}

  @override
  void write(String text) {}

  @override
  Future<void> flash(String mainPy) async {}

  @override
  Future<void> restart({bool interrupt = false}) async {}

  @override
  Future<void> disconnect() async {}

  @override
  void dispose() {}

}
