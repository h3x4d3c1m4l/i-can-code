import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/services/microbit/microbit_link.dart';
import 'package:i_can_code/theme/app_theme.dart';

/// That a board is connected, which one, and everything else behind an icon.
///
/// One line, because the terminal below it is what the reader came for. Every
/// field is optional: a browser may withhold the serial number, which takes the
/// board id with it.
class MicrobitBoardSummary extends StatelessWidget {

  /// How wide the tooltip may get.
  ///
  /// forui can slide a tooltip along the edge but not shrink it, so one wider
  /// than the window is clipped.
  static const double _tipWidth = 340;

  final MicrobitDevice device;

  /// What the board answered over CMSIS-DAP, once it has.
  final MicrobitBoardInfo? info;

  const MicrobitBoardSummary({required this.device, this.info, super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final details = _details(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            context.localizations.microbitScreen_connectedTo(_boardName(context)),
            overflow: TextOverflow.ellipsis,
            style: context.appTheme.text.body.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 6),
        Icon(FLucideIcons.check, size: 16, color: context.appTheme.colors.success),
        if (details.isNotEmpty) ...[
          const SizedBox(width: 10),
          FTooltip(
            tipBuilder: (context, _) => ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _tipWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (label, value) in details)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text('$label: $value', style: context.appTheme.text.bodySmall),
                    ),
                ],
              ),
            ),
            child: Semantics(
              label: context.localizations.microbitScreen_deviceDetails,
              child: Icon(FLucideIcons.info, size: 16, color: colors.mutedForeground),
            ),
          ),
        ],
      ],
    );
  }

  /// The board's generation where that is known, and otherwise "micro:bit".
  String _boardName(BuildContext context) {
    final l10n = context.localizations;

    return switch (info?.boardVersion ?? device.boardVersion) {
      MicrobitBoardVersion.v2 => l10n.microbitScreen_deviceV2,
      MicrobitBoardVersion.v1 => l10n.microbitScreen_deviceV1,
      null => l10n.microbitScreen_deviceUnnamed,
    };
  }

  /// Everything the board reported, as label-and-value pairs.
  List<(String, String)> _details(BuildContext context) {

    final l10n = context.localizations;
    final info = this.info;
    final boardId = info?.boardId ?? device.boardId;
    final firmware = [info?.vendor, info?.product, info?.protocolVersion].nonNulls.join(' ');
    final serial = info?.uniqueId ?? device.serialNumber;

    return [
      if (device.product != null) (l10n.microbitScreen_deviceName, device.product!),
      if (boardId != null) (l10n.microbitScreen_deviceBoardId, boardId),
      if (firmware.isNotEmpty) (l10n.microbitScreen_deviceFirmware, firmware),
      if ((info?.flashBytes ?? 0) > 0)
        (
          l10n.microbitScreen_deviceFlash,
          '${info!.pageCount} × ${info.pageSize} B = ${info.flashBytes ~/ 1024} KB',
        ),
      if (serial != null) (l10n.microbitScreen_deviceSerial, groupSerial(serial)),
      // Which of the two sources answered, because only the vendor command
      // survives a browser anonymizing the USB serial number.
      if (info != null && info.idSource != MicrobitIdSource.unknown)
        (
          l10n.microbitScreen_deviceIdSource,
          switch (info.idSource) {
            MicrobitIdSource.vendorCommand => l10n.microbitScreen_idFromWire,
            MicrobitIdSource.usbSerial => l10n.microbitScreen_idFromDescriptor,
            MicrobitIdSource.unknown => '',
          },
        ),
    ];
  }

}

/// Breaks a serial number into groups of eight.
///
/// A `Text` wraps only at whitespace, so 48 unbroken hex characters would push
/// the tooltip past its maximum width and out of the window.
@visibleForTesting
String groupSerial(String serial) {
  final groups = <String>[];

  for (var at = 0; at < serial.length; at += 8) {
    groups.add(serial.substring(at, (at + 8).clamp(0, serial.length)));
  }

  return groups.join(' ');
}
