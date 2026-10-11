import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/shape_metrics.dart';
import 'package:i_can_code/views/components/lesson/code_sample.dart';
import 'package:i_can_code/views/components/lesson/collapsible_prose_group.dart';
import 'package:i_can_code/views/components/lesson/emoji_bullet_list.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

/// One `###` group of a section's prose: the heading, and every block under it
/// up to the next `###`.
@immutable
class ProseGroup {

  /// The heading's text, or null for the prose that precedes the first `###`.
  final String? heading;

  final String body;

  /// Whether the author asked for this group to start folded, by ending the
  /// heading with `{collapsed}`.
  final bool collapsed;

  const ProseGroup({required this.heading, required this.body, this.collapsed = false});

}

/// [markdown], cut into the prose before the first `###` and one [ProseGroup]
/// per `###` after it.
///
/// A heading may end in `{collapsed}` to ask for its group to start folded. The
/// marker is stripped from the title.
///
/// A `###` line inside a fenced block is code, not a heading, so fences are
/// tracked and skipped. Markdown with no `###` at all comes back as a single
/// group with a null [ProseGroup.heading], which is what keeps a step without
/// subheadings rendering exactly as it did before.
List<ProseGroup> splitProseOnSubheadings(String markdown) {
  final heading = RegExp(r'^###[ \t]+(.*?)[ \t]*$');
  final folded = RegExp(r'^(.*?)[ \t]*\{collapsed\}$');
  final fence = RegExp(r'^\s*(?:```|~~~)');

  final groups = <ProseGroup>[];
  final buffer = <String>[];
  String? current;
  var collapsed = false;
  var inFence = false;

  void flush() {
    final body = buffer.join('\n').trim();
    if (current != null || body.isNotEmpty) {
      groups.add(ProseGroup(heading: current, body: body, collapsed: collapsed));
    }
    buffer.clear();
  }

  for (final line in markdown.split('\n')) {
    if (fence.hasMatch(line)) {
      inFence = !inFence;
    }

    final match = inFence ? null : heading.firstMatch(line);
    if (match == null) {
      buffer.add(line);
      continue;
    }

    flush();

    final title = match.group(1)!;
    final marker = folded.firstMatch(title);
    current = marker?.group(1) ?? title;
    collapsed = marker != null;
  }
  flush();

  return groups.isEmpty ? const [ProseGroup(heading: null, body: '')] : groups;
}

/// One item of a [ProseEmojiList]: its emoji, and its markdown without the
/// list marker or the emoji.
typedef EmojiListItem = ({String emoji, String body});

/// A stretch of a section's prose that is drawn in one piece.
sealed class ProseBlock {

  const ProseBlock();

}

/// Markdown the renderer takes as it is.
class ProseMarkdown extends ProseBlock {

  final String markdown;

  const ProseMarkdown(this.markdown);

}

/// A list whose every item opens with an emoji, drawn where its bullet would
/// be.
class ProseEmojiList extends ProseBlock {

  final List<EmojiListItem> items;

  const ProseEmojiList(this.items);

}

/// [markdown], cut into the lists an emoji marks and the prose between them.
///
/// A list counts when it starts at the left margin and **every** item opens
/// with an emoji and a space. One item without leaves the whole list to the
/// renderer, bullets and all, so a list is never drawn half each way.
///
/// An item runs on over the lines indented under it, and the list ends at the
/// first line that is neither an item, indented nor blank. A line that
/// continues an item MUST therefore be indented.
///
/// A list inside a fenced block is code and stays where it is. Markdown with no
/// such list comes back as a single [ProseMarkdown], which is what keeps a step
/// without one rendering exactly as it did before.
List<ProseBlock> splitProseOnEmojiLists(String markdown) {
  final fence = RegExp(r'^\s*(?:```|~~~)');
  final marker = RegExp(r'^[-*+][ \t]+');
  // A character that is an emoji only with U+FE0F behind it, such as `©`, is
  // text without one, and a flag is two regional indicators.
  const emoji =
      r'(?:[\u{1F1E6}-\u{1F1FF}]{2}|(?:\p{Emoji_Presentation}|\p{Extended_Pictographic}\u{FE0F})[\u{1F3FB}-\u{1F3FF}]?)';
  final emojiItem = RegExp('^([-*+][ \\t]+)($emoji(?:\\u{200D}$emoji)*)[ \\t]+(\\S.*)\$', unicode: true);

  final blocks = <ProseBlock>[];
  final prose = <String>[];

  void flushProse() {
    final text = prose.join('\n').trim();
    if (text.isNotEmpty) {
      blocks.add(ProseMarkdown(text));
    }
    prose.clear();
  }

  /// The items of the list in [lines], or null when one of them has no emoji.
  List<EmojiListItem>? itemsOf(List<String> lines) {
    final items = <EmojiListItem>[];
    var textStart = 0;

    for (final line in lines) {
      final match = emojiItem.firstMatch(line);
      if (match != null) {
        textStart = match.group(1)!.length;
        items.add((emoji: match.group(2)!, body: match.group(3)!));
      } else if (marker.hasMatch(line)) {
        return null;
      } else {
        // Only as far as the item's own text began, so a nested list or a code
        // block under it keeps the indentation that makes it one.
        final continued = line.replaceFirst(RegExp('^[ \\t]{0,$textStart}'), '');
        final last = items.removeLast();
        items.add((emoji: last.emoji, body: '${last.body}\n$continued'));
      }
    }

    return [for (final item in items) (emoji: item.emoji, body: item.body.trimRight())];
  }

  final lines = markdown.split('\n');
  var inFence = false;
  var index = 0;

  while (index < lines.length) {
    final line = lines[index];
    if (fence.hasMatch(line)) {
      inFence = !inFence;
    }

    if (inFence || !marker.hasMatch(line)) {
      prose.add(line);
      index++;
      continue;
    }

    // Up to the list's last line of text. The blank lines after it stay with
    // the prose: a list handed back to the renderer needs them, or the
    // paragraph below would be read as part of its last item.
    var end = index + 1;
    for (var next = end; next < lines.length; next++) {
      final follows = lines[next];
      if (follows.trim().isEmpty) {
        continue;
      }
      if (!marker.hasMatch(follows) && !follows.startsWith(RegExp(r'[ \t]'))) {
        break;
      }
      end = next + 1;
    }

    final list = lines.sublist(index, end);
    final items = itemsOf(list);
    if (items == null) {
      prose.addAll(list);
    } else {
      flushProse();
      blocks.add(ProseEmojiList(items));
    }
    index = end;
  }
  flushProse();

  return blocks.isEmpty ? const [ProseMarkdown('')] : blocks;
}

/// A section's prose, rendered in the app's type scale.
///
/// `flutter_markdown_plus` cannot read `context.appTheme`, so the tokens are
/// handed to a [MarkdownStyleSheet] piece by piece.
class LessonProse extends StatelessWidget {

  final String markdown;

  /// The body size. The design uses 21px on a full-width text step and 19px in
  /// the narrower column of a task.
  final double fontSize;

  /// Space under each paragraph. Zero for a single-paragraph message, where the
  /// gap would read as padding.
  final double paragraphSpacing;

  /// Whether to keep [CollapsibleProseGroup.gutter] free on the left for a
  /// subheading's chevron.
  ///
  /// The prose is indented by it, so a page that sets this MUST give back the
  /// same amount of its own left padding — otherwise every step's text moves
  /// right by a chevron. Off for prose that is not a step, such as a validator's
  /// message inside its panel.
  final bool hangingGutter;

  /// How each paragraph is set. Centred inside a square tile, where the words
  /// are the whole of what the tile holds; start everywhere prose is read as
  /// prose.
  final WrapAlignment textAlign;

  /// The gap the sheet puts between every pair of sibling blocks — list items
  /// included, which is what this number costs.
  ///
  /// Raised from the package's 8px so that the space above a subheading depends
  /// less on what precedes it. A paragraph carries its own bottom inset and a
  /// list carries none, so the more of the rhythm lives here, the closer those
  /// two cases sit. See [MarkdownStyleSheet.h3Padding] below.
  static const double _blockSpacing = 20;

  /// What the package itself uses, and what [paragraphSpacing] was measured
  /// against.
  static const double _packageBlockSpacing = 8;

  /// Air above a subheading, so it reads as belonging to what follows it rather
  /// than to the block above.
  static const double _headingSpacing = 28;

  const LessonProse({
    required this.markdown,
    this.fontSize = 21,
    this.paragraphSpacing = 18,
    this.hangingGutter = false,
    this.textAlign = WrapAlignment.start,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final tokens = context.appTheme;
    final body = tokens.text.body.copyWith(fontSize: fontSize, height: 1.6);

    // [paragraphSpacing] is the space *on top of* the package's own block gap.
    // Widening that gap therefore has to come off the paragraph's own inset, or
    // every paragraph would drift apart by the difference.
    final paragraphBottom = math.max(0.0, paragraphSpacing - (_blockSpacing - _packageBlockSpacing));

    final sheet = MarkdownStyleSheet(
        p: body,
        textAlign: textAlign,
        pPadding: EdgeInsets.only(bottom: paragraphBottom),
        blockSpacing: _blockSpacing,
        h1: tokens.text.h2,
        h2: tokens.text.h3,
        h3: tokens.text.h3.copyWith(fontSize: 20),
        // Only reached by a `###` the splitter does not hoist — one nested
        // inside a blockquote or a list item. A subheading in the ordinary flow
        // becomes a [CollapsibleProseGroup], which draws its own heading and
        // owns the space around it.
        h3Padding: const EdgeInsets.only(top: _headingSpacing, bottom: 4),
        listBullet: body,
        strong: body.copyWith(fontWeight: FontWeight.w700),
        em: body.copyWith(fontStyle: FontStyle.italic),
        // `link`, not `primary`: a preset's accent is a fill and may be
        // unreadable as text. Underlined as well as coloured, because the
        // THUAS scheme has no link colour distinct enough on its own.
        a: body.copyWith(color: tokens.colors.link, decoration: TextDecoration.underline),
        // A touch smaller than the prose around it, or the line height jumps.
        code: tokens.text.code.copyWith(fontSize: fontSize - 4, color: theme.colors.foreground),
        // The card is drawn by [_CodeBlockBuilder], not here: a decoration set
        // on the sheet lands *inside* the package's own container, leaving no
        // way to put space beneath it.
        codeblockPadding: EdgeInsets.zero,
        // Transparent, and it MUST stay set.
        //
        // `MarkdownBody` merges this sheet onto a **Material** one built from
        // the ambient `ThemeData` (`fallbackStyleSheet.merge(styleSheet)`), and
        // merge keeps the fallback wherever this sheet leaves a null. There is
        // no Material ancestor, so that fallback is a default light `ThemeData`
        // and this slot came back as `cardColor` — a fixed `#FEF7FF` that never
        // follows the app's theme. It paints behind the whole `pre`, padding
        // included, which on the dark page read as a white halo around the
        // code card.
        codeblockDecoration: const BoxDecoration(),
        // Same trap: the fallback's is Material's `dividerColor`.
        horizontalRuleDecoration: BoxDecoration(
          border: Border(top: BorderSide(color: theme.colors.border, width: 2)),
        ),
        blockquoteDecoration: ShapeDecoration(
          color: theme.colors.secondary,
          shape: squircle(kChipCornerRadius),
        ),
      );

    // A worked example, drawn on the same dark surface as the editor.
    //
    // MUST be keyed on `pre`, not `code`: `styleSheet.code` is shared by inline
    // code, which sits on the page's light surface, and a builder keyed on
    // `code` silently never fires.
    //
    // A fresh builder per [MarkdownBody]: [_CodeBlockBuilder] carries the fence's
    // language between two visitor calls, so one instance MUST NOT be shared by
    // two trees.
    MarkdownBody render(String data, {MarkdownStyleSheet? styleSheet}) => MarkdownBody(
      data: data,
      styleSheet: styleSheet ?? sheet,
      // Without it the package draws a link and ignores the press. A new tab,
      // because leaving the app's own tab throws away the step in progress.
      onTapLink: (_, href, _) {
        if (href != null) launchUrl(Uri.parse(href));
      },
      builders: {
        'pre': _CodeBlockBuilder(
          style: tokens.text.code.copyWith(color: tokens.colors.codeForeground),
          labelStyle: tokens.text.codeSmall.copyWith(color: tokens.colors.codeMuted),
          surface: tokens.colors.codeBackground,
          trailingSpace: paragraphBottom,
        ),
      },
    );

    // A [CollapsibleProseGroup] holds its own gutter open, because the chevron
    // in it has to be inside the box that receives the press. Everything else
    // is indented to match.
    Widget aligned(Widget child) => hangingGutter
        ? Padding(padding: const EdgeInsets.only(left: CollapsibleProseGroup.gutter), child: child)
        : child;

    // What the package's own list item has: text straight inside it, without
    // the inset a paragraph carries below itself.
    final itemSheet = sheet.copyWith(pPadding: EdgeInsets.zero);

    // An emoji list is drawn here and not by the package. Its `bulletBuilder`
    // is told an item's index and never its text, so it cannot know which
    // emoji to draw.
    Widget blocks(String data) {
      final parts = splitProseOnEmojiLists(data);
      if (parts case [ProseMarkdown(markdown: final only)]) {
        return render(only);
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (index, part) in parts.indexed) ...[
            // The package spaces sibling blocks inside one body only.
            if (index > 0) const SizedBox(height: _blockSpacing),
            switch (part) {
              ProseMarkdown(markdown: final prose) => render(prose),
              ProseEmojiList(:final items) => EmojiBulletList(
                items: [for (final item in items) (emoji: item.emoji, child: render(item.body, styleSheet: itemSheet))],
                style: body,
                spacing: _blockSpacing,
              ),
            },
          ],
        ],
      );
    }

    final groups = splitProseOnSubheadings(markdown);
    if (groups.length == 1 && groups.single.heading == null) {
      return aligned(blocks(groups.single.body));
    }

    final headingStyle = tokens.text.h3.copyWith(fontSize: 20);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (index, group) in groups.indexed)
          if (group.heading case final String heading)
            CollapsibleProseGroup(
              heading: heading,
              headingStyle: headingStyle,
              initiallyCollapsed: group.collapsed,
              // The first group opens the step, so it has nothing to be spaced
              // from. The rest carry the gap the style sheet used to.
              headingPadding: EdgeInsets.only(top: index == 0 ? 0 : _headingSpacing, bottom: 4),
              child: blocks(group.body),
            )
          else
            aligned(blocks(group.body)),
      ],
    );
  }

}

class _CodeBlockBuilder extends MarkdownElementBuilder {

  /// Extra space *outside* the card, on top of the sheet's own rhythm.
  static const double _extra = 8;

  final TextStyle style;

  /// The language name in the card's top corner.
  final TextStyle labelStyle;

  /// The card's fill.
  final Color surface;

  /// Space left under the card.
  ///
  /// A paragraph carries its spacing *below itself* (`pPadding`), so the gap
  /// above a block is that plus the sheet's 8px `blockSpacing` while the gap
  /// below is the 8px alone. Repeating it here makes the two sides match.
  final double trailingSpace;

  /// Read in [visitElementBefore], because [visitText] is handed the code
  /// without its fence.
  String? _language;

  _CodeBlockBuilder({
    required this.style,
    required this.labelStyle,
    required this.surface,
    required this.trailingSpace,
  });

  @override
  void visitElementBefore(md.Element element) {
    // `pre > code`, with the fence's language as a class on the inner element.
    final code = element.children?.whereType<md.Element>().firstOrNull;
    final declared = code?.attributes['class'] ?? '';
    _language = declared.startsWith('language-') ? declared.substring('language-'.length) : null;
  }

  @override
  Widget? visitText(md.Text text, TextStyle? preferredStyle) {
    return Padding(
      // Top is bare [_extra] because the paragraph above already contributes
      // its spacing; the bottom has to supply that itself.
      padding: EdgeInsets.only(top: _extra, bottom: trailingSpace + _extra),
      // The corner is left to [CodeSample], which names the language the way a
      // reader writes it rather than as the fence's own lower-case word — and
      // without a version, because this code is static and no interpreter ran
      // it.
      child: CodeSample(
        source: text.text,
        language: _language,
        style: style,
        labelStyle: labelStyle,
        surface: surface,
      ),
    );
  }

}
