import 'dart:convert';
import 'dart:typed_data';

/// Every compiled icon in one asset, so the app fetches one file for all of
/// them rather than one per icon.
///
/// Written by `bin/bundle_icons.dart` during the build and read by
/// `DuotoneIcon`. Plain Dart, because the bundler runs on the Dart VM.
///
/// The layout, little-endian: a `uint16` count, then per icon a `uint8` key
/// length, the key in ASCII and a `uint32` byte length, then every icon's bytes
/// in that same order.
class IconBundle {

  /// Where the app finds the bundle. Declared in `pubspec.yaml`.
  static const String asset = 'assets/icons.bin';

  final Map<String, ByteData> _icons;

  const IconBundle._(this._icons);

  /// Reads a bundle [encode] wrote.
  ///
  /// Throws a [FormatException] when [data] is not one, which is a broken build
  /// rather than anything a retry could fix.
  factory IconBundle.decode(ByteData data) {
    try {
      var offset = 0;
      final count = data.getUint16(offset, Endian.little);
      offset += 2;

      final entries = <(String, int)>[];
      for (var i = 0; i < count; i++) {
        final keyLength = data.getUint8(offset);
        offset += 1;
        final key = ascii.decode(Uint8List.sublistView(data, offset, offset + keyLength));
        offset += keyLength;
        entries.add((key, data.getUint32(offset, Endian.little)));
        offset += 4;
      }

      final icons = <String, ByteData>{};
      for (final (key, length) in entries) {
        // Copied into a buffer of its own: vector_graphics views a picture's
        // floats in place, which needs them aligned to the start of a buffer,
        // and an icon starts wherever the one before it ended.
        icons[key] = ByteData.sublistView(Uint8List.fromList(Uint8List.sublistView(data, offset, offset + length)));
        offset += length;
      }
      if (offset != data.lengthInBytes) throw const FormatException('The icon bundle runs on past its last icon.');

      return IconBundle._(icons);
    } on RangeError {
      throw const FormatException('The icon bundle ends part way through.');
    }
  }

  /// Lays [icons] out the way [IconBundle.decode] reads them. Each key MUST be
  /// ASCII and shorter than 256 bytes.
  static Uint8List encode(Map<String, Uint8List> icons) {
    final header = BytesBuilder()..add(_uint16(icons.length));
    final body = BytesBuilder(copy: false);
    for (final MapEntry(:key, :value) in icons.entries) {
      final name = ascii.encode(key);
      header
        ..addByte(name.length)
        ..add(name)
        ..add(_uint32(value.length));
      body.add(value);
    }

    return (header..add(body.takeBytes())).takeBytes();
  }

  static Uint8List _uint16(int value) => Uint8List(2)..buffer.asByteData().setUint16(0, value, Endian.little);

  static Uint8List _uint32(int value) => Uint8List(4)..buffer.asByteData().setUint32(0, value, Endian.little);

  Iterable<String> get keys => _icons.keys;

  /// The compiled picture under [key], or null when the bundle has none.
  ByteData? operator [](String key) => _icons[key];

}
