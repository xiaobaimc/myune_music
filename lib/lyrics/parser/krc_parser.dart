// 参考 https://github.com/WisteriaZy/lyricGeter/tree/master/parser/krc.py

import 'dart:convert';

import 'parsed_models.dart';

class KrcParser {
  // 标签正则：[key:value]
  static final _tagPattern = RegExp(r'^\[(\w+):([^\]]*)\]$');

  // 行级正则：[开始ms,持续ms]内容
  static final _linePattern = RegExp(r'^\[(\d+),(\d+)\](.*)$');

  // 逐字正则：<偏移ms,持续ms,保留字段>文字
  static final _wordPattern = RegExp(r'<(\d+),(\d+),\d+>([^<]*)');

  /// 解析 KRC 内容
  ParsedLyrics parse(String content) {
    final tags = <String, String>{};
    final origLines = <ParsedLine>[];

    for (final rawLine in content.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      // 解析标签
      final tagMatch = _tagPattern.firstMatch(line);
      if (tagMatch != null) {
        tags[tagMatch.group(1)!] = tagMatch.group(2)!;
        continue;
      }

      // 解析歌词行
      final lineMatch = _linePattern.firstMatch(line);
      if (lineMatch == null) continue;

      final lineStart = int.parse(lineMatch.group(1)!);
      final lineDuration = int.parse(lineMatch.group(2)!);
      final lineEnd = lineStart + lineDuration;
      final lineContent = lineMatch.group(3)!;

      // 解析逐字时间戳
      final words = <ParsedWord>[];
      for (final wordMatch in _wordPattern.allMatches(lineContent)) {
        final wordOffset = int.parse(wordMatch.group(1)!); // 相对行起始
        final wordDuration = int.parse(wordMatch.group(2)!);
        final wordText = wordMatch.group(3)!;

        final wordStart = lineStart + wordOffset;
        final wordEnd = wordStart + wordDuration;

        words.add(
          ParsedWord(startMs: wordStart, endMs: wordEnd, text: wordText),
        );
      }

      // 如果没有逐字时间戳，整行作为一个 word
      if (words.isEmpty) {
        words.add(
          ParsedWord(startMs: lineStart, endMs: lineEnd, text: lineContent),
        );
      }

      origLines.add(
        ParsedLine(startMs: lineStart, endMs: lineEnd, words: words),
      );
    }

    // 解析翻译和罗马音（来自 language 标签）
    final (romajiLines, translationLines) = _parseLanguageTag(
      tags['language'],
      origLines,
    );

    return ParsedLyrics(
      tags: tags,
      lines: origLines,
      translationLines: translationLines,
      romajiLines: romajiLines,
    );
  }

  // JSON 结构：
  // {
  //   "content": [
  //     {"type": 0, "lyricContent": [["罗马音1","罗马音2",...], ...]},
  //     {"type": 1, "lyricContent": [["翻译1"], ["翻译2"], ...]}
  //   ]
  // }
  //
  (List<ParsedLine>, List<ParsedLine>) _parseLanguageTag(
    String? languageB64,
    List<ParsedLine> origLines,
  ) {
    final romajiLines = <ParsedLine>[];
    final translationLines = <ParsedLine>[];

    if (languageB64 == null || languageB64.isEmpty) {
      return (romajiLines, translationLines);
    }

    try {
      final decoded = utf8.decode(base64Decode(languageB64.trim()));
      final langJson = jsonDecode(decoded) as Map<String, dynamic>;
      final contentArray = langJson['content'] as List<dynamic>? ?? [];

      for (final langObj in contentArray) {
        final langType = langObj['type'] as int?;
        final lyricContent = langObj['lyricContent'] as List<dynamic>? ?? [];

        if (langType == 0) {
          // 罗马音
          _parseRomaji(origLines, lyricContent, romajiLines);
        } else if (langType == 1) {
          // 翻译
          _parseTranslation(origLines, lyricContent, translationLines);
        }
      }
    } catch (_) {
      //
    }

    return (romajiLines, translationLines);
  }

  // 解析罗马音
  void _parseRomaji(
    List<ParsedLine> origLines,
    List<dynamic> lyricContent,
    List<ParsedLine> romajiLines,
  ) {
    var offset = 0;
    for (var j = 0; j < origLines.length; j++) {
      final origLine = origLines[j];

      // 跳过空行
      if (origLine.words.every((w) => w.text.isEmpty)) {
        offset++;
        continue;
      }

      final adjustedIndex = j - offset;
      if (adjustedIndex >= lyricContent.length) break;

      final romaWordsData = lyricContent[adjustedIndex] as List<dynamic>;
      final romaWords = <ParsedWord>[];

      for (var k = 0; k < origLine.words.length; k++) {
        final word = origLine.words[k];
        final romaText = k < romaWordsData.length
            ? romaWordsData[k].toString()
            : '';
        romaWords.add(
          ParsedWord(startMs: word.startMs, endMs: word.endMs, text: romaText),
        );
      }

      // TODO: 先不附加罗马音，lyrics_widget.dart 顶部的 FIXME 还没解决
      // romajiLines.add(
      //   ParsedLine(
      //     startMs: origLine.startMs,
      //     endMs: origLine.endMs,
      //     words: romaWords,
      //   ),
      // );
    }
  }

  // 解析翻译数据
  void _parseTranslation(
    List<ParsedLine> origLines,
    List<dynamic> lyricContent,
    List<ParsedLine> translationLines,
  ) {
    for (var j = 0; j < origLines.length; j++) {
      if (j >= lyricContent.length) break;

      final origLine = origLines[j];
      final row = lyricContent[j] as List<dynamic>;
      final tsText = row.isNotEmpty ? row[0].toString() : '';

      translationLines.add(
        ParsedLine(
          startMs: origLine.startMs,
          endMs: origLine.endMs,
          words: [
            ParsedWord(
              startMs: origLine.startMs,
              endMs: origLine.endMs,
              text: tsText,
            ),
          ],
        ),
      );
    }
  }
}
