import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/views/components/lesson/selectable_code.dart';
import 'package:i_can_code/views/components/scroll_card.dart';

/// A file's text on the page's own light card, the one a program's output is
/// shown on, for reading rather than editing. Scrolls inside the card.
class FileContents extends StatelessWidget {

  final String text;

  const FileContents({required this.text, super.key});

  @override
  Widget build(BuildContext context) {
    return ScrollCard(
      child: SelectableCode(
        child: Text(
          // `csv.writer` ends its rows in \r\n, which would draw as a blank
          // line under each. Copied and downloaded, the text is as written.
          const LineSplitter().convert(text).join('\n'),
          style: context.appTheme.text.code.copyWith(fontSize: 15, height: 1.7),
        ),
      ),
    );
  }

}
