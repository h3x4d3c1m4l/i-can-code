import 'package:flutter/widgets.dart';
import 'package:i_can_code/services/lessons/lesson.dart';
import 'package:i_can_code/theme/app_theme.dart';

/// The title every step opens with. One size for all three kinds, so the steps
/// read as one lesson.
class SectionHeading extends StatelessWidget {

  /// Every step's title, whatever kind it is.
  static const double titleSize = 34;

  final LessonSection section;

  const SectionHeading({required this.section, super.key});

  @override
  Widget build(BuildContext context) {
    return Text(section.title, style: context.appTheme.text.h2.copyWith(fontSize: titleSize));
  }

}
