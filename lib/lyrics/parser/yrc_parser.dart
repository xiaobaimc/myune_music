// 参考 https://github.com/WisteriaZy/lyricGeter/tree/master/parser/yrc.py

import 'parsed_models.dart';

class YrcParser {
  // 行级正则：[行开始ms,行持续ms]内容
  static final _linePattern = RegExp(r'^\[(\d+),(\d+)\](.*)$');

  // 逐字正则：(字偏移ms,字持续ms,保留字段)文本
  static final _wordPattern = RegExp(r'\((\d+),(\d+),\d+\)([^\(]*)');

  // 解析 YRC 文本
  ParsedLyrics parse(String content) {
    final lines = <ParsedLine>[];

    for (final rawLine in content.split('\n')) {
      final line = rawLine.trim();
      if (!line.startsWith('[')) continue;

      final match = _linePattern.firstMatch(line);
      if (match == null) continue;

      final lineStart = int.parse(match.group(1)!);
      final lineDuration = int.parse(match.group(2)!);
      final lineEnd = lineStart + lineDuration;
      final lineContent = match.group(3)!;

      // 解析逐字时间戳
      final words = <ParsedWord>[];
      for (final wordMatch in _wordPattern.allMatches(lineContent)) {
        final wordOffset = int.parse(wordMatch.group(1)!); // 相对行起始
        final wordDuration = int.parse(wordMatch.group(2)!);
        final wordText = wordMatch.group(3)!;

        final wordStartAbs = lineStart + wordOffset;
        final wordEndAbs = wordStartAbs + wordDuration;

        words.add(
          ParsedWord(startMs: wordStartAbs, endMs: wordEndAbs, text: wordText),
        );
      }

      // 如果没有逐字数据，整行作为一个 word
      if (words.isEmpty) {
        words.add(
          ParsedWord(startMs: lineStart, endMs: lineEnd, text: lineContent),
        );
      }

      lines.add(ParsedLine(startMs: lineStart, endMs: lineEnd, words: words));
    }

    return ParsedLyrics(lines: lines);
  }

  // 检测内容是否包含 YRC 逐字时间戳
  bool hasWordTimestamps(String content) {
    for (final line in content.split('\n')) {
      if (_wordPattern.hasMatch(line)) return true;
    }
    return false;
  }
}
