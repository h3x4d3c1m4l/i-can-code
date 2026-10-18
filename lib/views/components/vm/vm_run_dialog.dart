import 'package:flutter/widgets.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/services/vm/vm_runtime.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/views/components/vm/no_window_panel.dart';
import 'package:i_can_code/views/components/vm/program_dialog.dart';
import 'package:i_can_code/views/components/vm/vm_display.dart';
import 'package:i_can_code/views/components/vm/vm_load_panel.dart';
import 'package:i_can_code/views/components/vm/vm_session_controller.dart';
import 'package:i_can_code/views/components/vm/vm_session_view_model.dart';
import 'package:i_can_code/views/components/vm/window_strips.dart';

/// The program while it runs: its windows, the way out of them, and the cross
/// that ends it, in a [ProgramDialog] over the screen.
///
/// A screen MUST build it while, and only while, [session] is running, the
/// download included: a Run pressed then waits, and this says what for. So the
/// display and its platform view exist only while there is something to show
/// in them. Meanwhile the screen MUST leave the rest of its page out of the
/// focus tree, and do that in the same build, before this, so that unfocusing
/// the page comes before the display's own request for focus.
class VmRunDialog extends StatelessWidget {

  final VmSessionViewModel session;

  /// What drives [session]: the display it shows, the stop and the close
  /// buttons on the strips.
  final VmSessionController controller;

  /// The display's. Run asks for focus on it a frame before this is built, and
  /// a node asked while it is out of the tree takes focus as it arrives.
  final FocusNode focusNode;

  /// Builds the platform view. A widget test passes one of its own, because
  /// `HtmlElementView` cannot be built off the web.
  final VmViewBuilder viewBuilder;

  const VmRunDialog({
    required this.session,
    required this.controller,
    required this.focusNode,
    required this.viewBuilder,
    super.key,
  });

  @override
  Widget build(BuildContext context) => Observer(builder: _buildDialog);

  Widget _buildDialog(BuildContext context) {
    final l10n = context.localizations;
    final window = session.framedWindow;
    final title = switch (window) {
      null => l10n.tkinterScreen_programTitle,
      VmWindow(title: '') => l10n.tkinterScreen_windowUntitled,
      VmWindow(:final title) => title,
    };
    final focused = session.displayFocused;
    final ready = session.machine == TkinterMachine.ready;
    final region = ready ? session.shownRegion : null;
    // Read here, in the Observer's build: the frame's builder runs at layout.
    final progress = session.loadProgress;
    final background = context.appTheme.colors.codeBackground;
    final noWindow = l10n.tkinterScreen_noWindowBody;
    final labelled = session.labelledWindows;

    return ProgramDialog(
      title: title,
      stopLabel: l10n.tkinterScreen_stopProgram,
      onStop: controller.stop,
      hint: focused ? l10n.tkinterScreen_leaveHint : null,
      focused: focused,
      region: region?.size,
      builder: (context, box, scale) {
        if (!ready) return VmLoadPanel(progress: progress);

        return Stack(
          fit: StackFit.expand,
          children: [
            VmDisplay(
              // Global, so a display that is rebuilt into another place in the
              // tree keeps its platform view rather than building a second one.
              // A retry builds a new machine, and its screen is a new view.
              key: GlobalObjectKey(controller.display),
              binding: controller.display,
              region: region ?? Offset.zero & box,
              scale: scale,
              focusNode: focusNode,
              semanticsLabel: title,
              background: background,
              onFocusChange: controller.onDisplayFocusChange,
              viewBuilder: viewBuilder,
            ),
            // A press on it still reaches the display beneath and takes the
            // keyboard, as a press on the empty screen did.
            if (region == null) IgnorePointer(child: NoWindowPanel(text: noWindow)),
            if (region != null && labelled.isNotEmpty)
              WindowStrips(
                windows: labelled,
                region: region,
                scale: scale,
                closeLabel: l10n.tkinterScreen_close,
                untitledLabel: l10n.tkinterScreen_windowUntitled,
                onClose: controller.closeWindowById,
              ),
          ],
        );
      },
    );
  }

}
