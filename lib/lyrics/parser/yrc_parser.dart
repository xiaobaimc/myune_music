// 参考 https://github.com/WisteriaZy/lyricGeter/tree/master/parser/yrc.py

import 'parsed_models.dart';

class YrcParser {
  // 行级正则：[行开始ms,行持续ms]内容
  static final _linePattern = RegExp(r'^\[(\d+),(\d+)\](.*)$');

  // 逐字正则：(字开始ms,字持续ms,保留字段)文本
  static final _wordPattern = RegExp(r'\((\d+),(\d+),\d+\)([^\(]*)');

  // 仅用于兜底行去掉逐字时间戳
  static final _wordTimestampPattern = RegExp(r'\(\d+,\d+,\d+\)');

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
      // 行首就遇到空格占位时先攒着，等第一个真正的字出现再拼上去
      var pendingPrefix = '';

      for (final wordMatch in _wordPattern.allMatches(lineContent)) {
        final wordStart = int.parse(wordMatch.group(1)!); // 绝对时间
        final wordDuration = int.parse(wordMatch.group(2)!);
        final wordText = wordMatch.group(3)!;

        // (0,0,0) 是空格占位，没有自己的时间轴
        if (wordStart == 0 && wordDuration == 0) {
          if (wordText.isEmpty) continue;
          if (words.isEmpty) {
            pendingPrefix += wordText;
          } else {
            final last = words.removeLast();
            words.add(
              ParsedWord(
                startMs: last.startMs,
                endMs: last.endMs,
                text: '${last.text}$wordText',
              ),
            );
          }
          continue;
        }

        words.add(
          ParsedWord(
            startMs: wordStart,
            endMs: wordStart + wordDuration,
            text: '$pendingPrefix$wordText',
          ),
        );
        pendingPrefix = '';
      }

      // 没有逐字数据（例如普通文本行）时，整行作为一个 word
      if (words.isEmpty) {
        final text = (pendingPrefix + lineContent)
            .replaceAll(_wordTimestampPattern, '')
            .trim();
        if (text.isNotEmpty) {
          words.add(ParsedWord(startMs: lineStart, endMs: lineEnd, text: text));
        }
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
