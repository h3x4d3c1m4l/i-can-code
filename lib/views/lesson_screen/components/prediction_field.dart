import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/theme/app_theme.dart';

/// Where a [SectionKind.predictOutput] step is answered: what the student
/// thinks the program above will print, before it is run.
///
/// Set in the **code** face, at the output card's own size, because the answer
/// is output — spaces and line breaks are part of it, and a proportional face
/// hides exactly the differences this step is about.
class PredictionField extends StatelessWidget {

  final TextEditingController controller;

  final ValueChanged<String> onChange;

  /// Locked once the answer is on the screen. Editing the box afterwards cannot
  /// change a verdict that has already been given — and re-typing the output
  /// that is showing right beside it would be answering a question nobody asked.
  final bool enabled;

  /// Matches [OutputCard]'s text, so a prediction and the output it is compared
  /// against are set identically.
  static const double fontSize = 15;
  static const double lineHeight = 1.7;

  /// Room for a few lines of output without scrolling, and no more: the box
  /// grows with what is typed into it.
  static const int minLines = 3;

  const PredictionField({
    required this.controller,
    required this.onChange,
    this.enabled = true,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTheme;

    return FTextField.multiline(
      control: .managed(controller: controller, onChange: (value) => onChange(value.text)),
      label: Text(context.localizations.lessonScreen_predictYours),
      hint: context.localizations.lessonScreen_predictHint,
      minLines: minLines,
      enabled: enabled,
      // A prediction is not prose: the phone keyboard MUST NOT capitalise it or
      // correct its spelling, both of which quietly rewrite an answer that is
      // compared character by character.
      textCapitalization: TextCapitalization.none,
      autocorrect: false,
      style: FTextFieldStyleDelta.delta(
        contentTextStyle: FVariantsDelta.delta([
          FVariantOperation.all(
            TextStyleDelta.delta(
              fontFamily: tokens.text.code.fontFamily,
              fontFamilyFallback: tokens.text.code.fontFamilyFallback,
              fontSize: fontSize,
              height: lineHeight,
            ),
          ),
        ]),
      ),
    );
  }

}
