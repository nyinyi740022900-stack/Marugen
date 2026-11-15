import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// The small subset of Markdown the care guides actually use — `#`/`##`
/// headings, `-`/`*` bullets, numbered lists, `**bold**`, `*italic*` and
/// blank-line paragraphs — rendered with the app's own type, so a guide
/// written on a phone never shows raw `#` and `**`.
class SimpleMarkdown extends StatelessWidget {
  final String text;
  const SimpleMarkdown(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final body = TextStyle(fontSize: 14.5, height: 1.5, color: palette.text);
    final blocks = <Widget>[];
    final paragraph = <String>[];

    void flush() {
      if (paragraph.isEmpty) return;
      blocks.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text.rich(_inline(paragraph.join(' '), body)),
        ),
      );
      paragraph.clear();
    }

    for (final raw in text.split('\n')) {
      final line = raw.trimRight();
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        flush();
        continue;
      }
      final heading = RegExp(r'^(#{1,3})\s+(.*)$').firstMatch(trimmed);
      // Guides written on a phone often mark a section with a short line
      // in capitals instead of `#`; treat it as a sub-heading so it does
      // not run into the paragraph below.
      final shouting =
          heading == null &&
          trimmed.length <= 60 &&
          !trimmed.endsWith('.') &&
          trimmed == trimmed.toUpperCase() &&
          RegExp(r'[A-Z]{3,}').hasMatch(trimmed);
      if (heading != null || shouting) {
        flush();
        final level = heading?.group(1)!.length ?? 3;
        blocks.add(
          Padding(
            padding: EdgeInsets.only(top: level == 1 ? 6 : 4, bottom: 6),
            child: Text(
              heading?.group(2) ?? trimmed,
              style: TextStyle(
                fontSize: level == 1 ? 18 : (level == 2 ? 16 : 15),
                fontWeight: FontWeight.w700,
                height: 1.25,
                color: palette.text,
              ),
            ),
          ),
        );
        continue;
      }
      final bullet = RegExp(r'^[-*•]\s+(.*)$').firstMatch(trimmed);
      final numbered = RegExp(r'^(\d+)[.)]\s+(.*)$').firstMatch(trimmed);
      if (bullet != null || numbered != null) {
        flush();
        final marker = bullet != null ? '•' : '${numbered!.group(1)}.';
        final content = bullet?.group(1) ?? numbered!.group(2)!;
        blocks.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 4, left: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 22, child: Text(marker, style: body)),
                Expanded(child: Text.rich(_inline(content, body))),
              ],
            ),
          ),
        );
        continue;
      }
      paragraph.add(trimmed);
    }
    flush();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks,
    );
  }

  /// `**bold**` and `*italic*` / `_italic_` within one paragraph.
  static TextSpan _inline(String text, TextStyle base) {
    final spans = <TextSpan>[];
    final pattern = RegExp(r'\*\*(.+?)\*\*|\*(.+?)\*|_(.+?)_');
    var cursor = 0;
    for (final m in pattern.allMatches(text)) {
      if (m.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, m.start)));
      }
      if (m.group(1) != null) {
        spans.add(
          TextSpan(
            text: m.group(1),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        );
      } else {
        spans.add(
          TextSpan(
            text: m.group(2) ?? m.group(3),
            style: const TextStyle(fontStyle: FontStyle.italic),
          ),
        );
      }
      cursor = m.end;
    }
    if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor)));
    return TextSpan(style: base, children: spans);
  }
}

/// Plain text for previews: markers removed, lines joined with a space.
String stripMarkdown(String text) => text
    .split('\n')
    .map(
      (l) => l
          .trim()
          .replaceFirst(RegExp(r'^#{1,6}\s+'), '')
          .replaceFirst(RegExp(r'^([-*•]|\d+[.)])\s+'), '')
          .replaceAllMapped(RegExp(r'\*\*(.+?)\*\*'), (m) => m.group(1)!)
          .replaceAllMapped(
            RegExp(r'\*(.+?)\*|_(.+?)_'),
            (m) => m.group(1) ?? m.group(2)!,
          ),
    )
    .where((l) => l.isNotEmpty)
    .join(' ');
