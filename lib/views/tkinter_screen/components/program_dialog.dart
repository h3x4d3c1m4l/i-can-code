import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/views/components/app_header.dart';
import 'package:i_can_code/views/tkinter_screen/components/window_frame.dart';

/// The running program, over the page: a dim across everything, and the
/// program's windows in a [WindowFrame] in the middle of what is left.
///
/// It is up for exactly as long as a run is, which is what makes the cross on
/// its strip the way to end one: a window the program will not close still
/// goes, and there is one control rather than two.
///
/// **The page behind it is taken out of reach three ways**, and the third is
/// not only good manners:
///
/// - The dim absorbs the pointer, so a click beside the program cannot land in
///   the editor. [VmDisplay] turns the guest's mouse on only for events its own
///   `Listener` saw, so nothing of that click reaches the program either.
/// - The page is left out of the focus tree, so Tab travels from the display to
///   this cross and on into the bar, never into an editor behind a dim.
/// - **[BlockSemantics] hides the page from the semantics tree**, because a
///   semantics element is placed by its rect and the engine puts the semantics
///   host over the platform view. With a screen reader on, the editor's own
///   element covered the display, and v86 drops a mouse event whose target is
///   not inside its screen box (`may_handle` in `libv86`), so every click on
///   the program was lost. The page is behind a modal dialog, so blocking it is
///   what a screen reader wants in any case.
///
/// It clears [AppHeader.height] at the top: the bar is drawn above the router
/// and so over this, and a strip under it is a title nobody can read. The bar
/// is painted after this and keeps its own semantics.
class ProgramDialog extends StatelessWidget {

  /// Room around the frame, so the page is visibly still there behind it.
  static const double margin = 24;

  /// The framed window's title, or what stands in before there is one.
  final String title;

  /// What the cross is for, which is ending the run.
  final String stopLabel;
  final VoidCallback onStop;

  /// The way out of the display, while it has the keyboard.
  final String? hint;

  final bool focused;

  /// The part of the guest's screen shown, in guest pixels. Null while the
  /// program has no window yet.
  final Size? region;

  final WindowFrameBuilder builder;

  const ProgramDialog({
    required this.title,
    required this.stopLabel,
    required this.onStop,
    required this.builder,
    this.hint,
    this.focused = false,
    this.region,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        BlockSemantics(child: AbsorbPointer(child: ColoredBox(color: context.theme.colors.barrier))),
        Padding(
          padding: const EdgeInsets.fromLTRB(margin, AppHeader.height + margin, margin, margin),
          child: WindowFrame(
            title: title,
            closeLabel: stopLabel,
            onClose: onStop,
            hint: hint,
            focused: focused,
            region: region,
            alignment: Alignment.center,
            builder: builder,
          ),
        ),
      ],
    );
  }

}
