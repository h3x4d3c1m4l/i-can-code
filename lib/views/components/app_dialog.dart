import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/views/components/app_button_row.dart';

/// Opens the dialog [builder] returns, which SHOULD be an [AppDialog], and
/// completes with what it pops.
///
/// It hangs off the outermost Navigator, `OverlayHost`'s, so the barrier covers
/// the bar as well as the page. The router's Navigator is below the bar.
/// [wide] is for a dialog that holds a program or a file.
Future<T?> showAppDialog<T>(BuildContext context, {required WidgetBuilder builder, bool wide = false}) =>
    showFDialog<T>(
      context: context,
      useRootNavigator: true,
      builder: (context, style, animation) => FDialog(
        animation: animation,
        constraints: BoxConstraints(maxWidth: wide ? AppDialog.wideWidth : AppDialog.width),
        builder: (context, style) => builder(context),
      ),
    );

/// The inside of a dialog: a title, a few lines about it, what it shows, and
/// its buttons at the end edge.
class AppDialog extends StatelessWidget {

  /// forui's own default.
  static const double width = 560;

  /// Wider than a question, because a CSV's rows and a program's lines are long.
  static const double wideWidth = 760;

  /// Set in the heading style.
  final Widget? title;

  /// Set in the body style.
  final Widget? body;

  /// What the dialog shows below [body], such as a program or a file.
  ///
  /// The one part that gives way when the dialog is taller than the window, so
  /// a [content] that can grow SHOULD scroll.
  final Widget? content;

  /// The buttons, with the one that carries the question forward last.
  final List<Widget> actions;

  const AppDialog({this.title, this.body, this.content, this.actions = const [], super.key});

  /// What [body] is set in, for text in [content] that reads as more of it.
  static TextStyle bodyStyle(BuildContext context) => context.appTheme.text.bodySmall.copyWith(fontSize: 17);

  @override
  Widget build(BuildContext context) {
    final text = context.appTheme.text;
    final title = this.title;
    final body = this.body;
    final content = this.content;

    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        // Stretched, so the button row is as wide as the dialog. A Wrap as wide
        // as its own buttons has no room to move them to the end.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null) DefaultTextStyle.merge(style: text.h3, child: title),
          if (body != null) ...[
            if (title != null) const SizedBox(height: 12),
            DefaultTextStyle.merge(style: bodyStyle(context), child: body),
          ],
          if (content != null) ...[
            if (body != null)
              const SizedBox(height: 20)
            else if (title != null)
              const SizedBox(height: 12),
            // forui bounds the dialog by the window less its inset.
            Flexible(child: content),
          ],
          if (actions.isNotEmpty) ...[
            if (title != null || body != null || content != null) const SizedBox(height: 24),
            AppButtonRow(alignment: WrapAlignment.end, children: actions),
          ],
        ],
      ),
    );
  }

}
