import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/l10n/generated/app_localizations.dart';
import 'package:i_can_code/services/vm/vm_runtime.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/shape_metrics.dart';

/// What stands where the program's screen will be while the machine loads: the
/// step it is on, how much has arrived, how fast and how much longer, and that
/// the editor is already open.
///
/// **Nothing in it moves by itself.** No spinner and no easing: the bar and the
/// numbers are set to each report as it comes, a few a second, and stand still
/// between them. The emulator shares the page's thread, and the bench measured a
/// page that repaints every frame leaving it a few percent of its speed.
///
/// **It does not change size as it goes.** The byte count is laid out before the
/// first report, and the speed and the note each have the room of their longest
/// wording whether they show or not, so nothing the student is reading moves.
class VmLoadPanel extends StatelessWidget {

  static const double _barHeight = 6;
  static final ShapeBorder _barShape = squircleOf(_barHeight / 2, size: _barHeight);

  /// Null before the first report, while the manifest that names the total is
  /// still on its way.
  final VmLoadProgress? progress;

  const VmLoadPanel({this.progress, super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appTheme.colors;
    final text = context.appTheme.text;
    final l10n = context.localizations;

    final progress = this.progress;
    final step = stepOf(progress);
    final measured = progress != null && progress.total > 0;
    final fraction = step > 0 ? 1.0 : (measured ? (progress.loaded / progress.total).clamp(0.0, 1.0) : 0.0);
    final note = noteFor(l10n, progress);
    final noteStyle = text.bodySmall.copyWith(fontSize: 14, height: 1.45, color: colors.codeMuted);
    final lineStyle = text.codeSmall.copyWith(color: colors.codeMuted);
    final speed = speedLine(l10n, progress, step: step);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                switch (step) {
                  0 => l10n.tkinterScreen_downloadTitle,
                  1 => l10n.tkinterScreen_unpackTitle,
                  _ => l10n.tkinterScreen_startingTitle,
                },
                style: text.h3.copyWith(color: colors.codeForeground),
              ),
              const SizedBox(height: 6),
              Text(
                l10n.tkinterScreen_downloadBody,
                style: text.bodySmall.copyWith(fontSize: 15, height: 1.5, color: colors.codeMuted),
              ),
              const SizedBox(height: 14),
              // The title already says which step this is.
              ExcludeSemantics(child: _Steps(current: step)),
              const SizedBox(height: 8),
              SizedBox(
                height: _barHeight,
                // The fill is clipped to the track rather than rounded itself: a
                // squircle narrower than it is tall bows inward.
                child: ClipPath(
                  clipper: ShapeBorderClipper(shape: _barShape),
                  child: ColoredBox(
                    color: colors.codeMuted.withValues(alpha: 0.3),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: FractionallySizedBox(
                        widthFactor: fraction,
                        heightFactor: 1,
                        child: ColoredBox(color: colors.codeForeground),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Visibility.maintain(
                visible: measured,
                child: Text(bytesLine(l10n, progress), style: lineStyle),
              ),
              Stack(
                children: [
                  // Holds the room of the longest speed line in this language.
                  Visibility.maintain(visible: false, child: Text(_longestSpeed(l10n), style: lineStyle)),
                  if (speed != null) Text(speed, style: lineStyle),
                ],
              ),
              const SizedBox(height: 8),
              Stack(
                children: [
                  Visibility.maintain(visible: false, child: Text(_longestNote(l10n), style: noteStyle)),
                  if (note != null) Semantics(liveRegion: true, child: Text(note, style: noteStyle)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Which of the three steps the student waits on: 0 while the bundle arrives,
  /// then 1 while it unpacks and 2 while the machine starts. A download that
  /// has everything is on the next step, which is what comes straight after.
  static int stepOf(VmLoadProgress? progress) => switch (progress) {
    null => 0,
    VmLoadProgress(phase: VmLoadPhase.start) => 2,
    VmLoadProgress(phase: VmLoadPhase.unpack) => 1,
    VmLoadProgress(downloaded: true) => 1,
    _ => 0,
  };

  /// `7,4 van 20,6 MB`.
  static String bytesLine(AppLocalizations l10n, VmLoadProgress? progress) =>
      l10n.tkinterScreen_downloadProgress(_megabytes(progress?.loaded ?? 0), _megabytes(progress?.total ?? 0));

  /// `2,3 MB/s · nog ongeveer 5 seconden`, only while the download runs and
  /// once there is enough of it to measure. A stalled one quotes no speed it
  /// no longer has.
  static String? speedLine(AppLocalizations l10n, VmLoadProgress? progress, {required int step}) {
    if (step != 0 || progress == null || progress.stalled) return null;
    final parts = [
      if (progress.bytesPerSecond case final double rate) rateText(l10n, rate),
      if (progress.remaining case final Duration remaining) remainingText(l10n, remaining),
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// Megabytes a second from 1 MB/s up, kilobytes below: `0,0 MB/s` would read
  /// as a download that stopped.
  static String rateText(AppLocalizations l10n, double bytesPerSecond) => bytesPerSecond >= 1000000
      ? l10n.tkinterScreen_rateMegabytes(bytesPerSecond / 1000000)
      : l10n.tkinterScreen_rateKilobytes(math.max(1, (bytesPerSecond / 1000).round()));

  /// Rounded coarsely, so that a smoothed estimate still moving by a second or
  /// two does not change the words: up to five seconds under a minute, and to
  /// the nearest minute past one.
  static String remainingText(AppLocalizations l10n, Duration remaining) {
    final seconds = remaining.inMilliseconds / 1000;
    if (seconds < 5) return l10n.tkinterScreen_remainingAlmost;
    if (seconds < 57.5) return l10n.tkinterScreen_remainingSeconds(math.min(55, (seconds / 5).ceil() * 5));
    return l10n.tkinterScreen_remainingMinutes(math.max(1, (seconds / 60).round()));
  }

  /// The one thing worth saying about this download, most pressing first.
  static String? noteFor(AppLocalizations l10n, VmLoadProgress? progress) {
    if (progress == null) return null;
    final downloading = stepOf(progress) == 0;
    if (downloading && progress.stalled) return l10n.tkinterScreen_downloadStalled;
    if (!progress.keeps) return l10n.tkinterScreen_downloadNotKept;
    if (downloading && progress.slowConnection && progress.bytesPerSecond == null) return l10n.tkinterScreen_downloadSlow;
    if (downloading && progress.cached > 0 && progress.cached < progress.total) return l10n.tkinterScreen_downloadResumed;
    return null;
  }

  static String _longestSpeed(AppLocalizations l10n) => [
    '${rateText(l10n, 99900000)} · ${remainingText(l10n, const Duration(seconds: 55))}',
    '${rateText(l10n, 99900000)} · ${remainingText(l10n, const Duration(minutes: 55))}',
  ].reduce((a, b) => a.length >= b.length ? a : b);

  static String _longestNote(AppLocalizations l10n) => [
    l10n.tkinterScreen_downloadStalled,
    l10n.tkinterScreen_downloadNotKept,
    l10n.tkinterScreen_downloadSlow,
    l10n.tkinterScreen_downloadResumed,
  ].reduce((a, b) => a.length >= b.length ? a : b);

  /// Decimal megabytes, the unit a download is quoted in.
  static double _megabytes(int bytes) => bytes / 1000000;

}

/// Download, unpack, start: the one under way in the text's own colour and
/// weight, the ones done ticked, and the ones to come muted.
class _Steps extends StatelessWidget {

  final int current;

  const _Steps({required this.current});

  @override
  Widget build(BuildContext context) {
    final colors = context.appTheme.colors;
    final style = context.appTheme.text.bodySmall.copyWith(fontSize: 13, height: 1.3);
    final l10n = context.localizations;
    final names = [l10n.tkinterScreen_stepDownload, l10n.tkinterScreen_stepUnpack, l10n.tkinterScreen_stepStart];

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final (index, name) in names.indexed) ...[
          if (index > 0) Icon(FLucideIcons.chevronRight, size: 14, color: colors.codeMuted),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (index < current) ...[
                Icon(FLucideIcons.check, size: 14, color: colors.codeMuted),
                const SizedBox(width: 4),
              ],
              Text(
                name,
                style: index == current
                    ? style.copyWith(color: colors.codeForeground, fontWeight: FontWeight.w700)
                    : style.copyWith(color: colors.codeMuted),
              ),
            ],
          ),
        ],
      ],
    );
  }

}
