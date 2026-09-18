import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/shape_metrics.dart';
import 'package:i_can_code/theme/squircle_input_border.dart';

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

  /// forui's own border for [state], as a squircle.
  ///
  /// The colours are the ones forui picks for each state, read back off the
  /// theme rather than chosen here: a field only has a corner problem, and
  /// picking a border colour at a call site is how a control ends up illegible
  /// in one preset.
  static SquircleInputBorder _border(BuildContext context, Color color) => SquircleInputBorder(
    // The card it is compared against, not forui's `md`: the prediction and the
    // output it is held against sit side by side and are read as a pair.
    radius: kCardCornerRadius,
    borderSide: BorderSide(color: color, width: context.theme.style.borderWidth),
  );

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTheme;
    final colors = context.theme.colors;

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
        // Every rounded corner in the app is a squircle, and a text field is the
        // one control that cannot take a `ShapeBorder` — see
        // `SquircleInputBorder`. Restating all five states is what an override
        // costs here: the border carries its own colour, so replacing one
        // replaces the colour with it.
        border: FVariantsValueDelta.delta([
          FVariantValueDeltaOperation.base(_border(context, colors.border)),
          FVariantValueDeltaOperation.exact(
            {FTextFieldVariantConstraint.focused},
            _border(context, colors.primary),
          ),
          FVariantValueDeltaOperation.exact(
            {FTextFieldVariantConstraint.disabled},
            _border(context, colors.disable(colors.border)),
          ),
          FVariantValueDeltaOperation.exact(
            {FTextFieldVariantConstraint.error},
            _border(context, colors.error),
          ),
          FVariantValueDeltaOperation.exact(
            {FTextFieldVariantConstraint.error, FTextFieldVariantConstraint.disabled},
            _border(context, colors.disable(colors.error)),
          ),
        ]),
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
