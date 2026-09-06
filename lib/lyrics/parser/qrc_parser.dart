// 参考 https://github.com/WisteriaZy/lyricGeter/tree/master/parser/qrc.py

import 'parsed_models.dart';

class QrcParser {
  // XML 包裹的 QRC 内容提取
  static final _qrcPattern = RegExp(
    r'<Lyric_1 LyricType="1" LyricContent="(?<content>.*?)"/>',
    dotAll: true,
  );

  // 标签正则：[key:value]
  static final _tagPattern = RegExp(r'^\[(\w+):([^\]]*)\]$');

  // 行级正则：[开始ms,持续ms]内容
  static final _linePattern = RegExp(r'^\[(\d+),(\d+)\](.*)$');

  // 逐字正则：文字(开始ms,持续ms)
  // 注意 QRC 的字时间戳是绝对时间，不是相对行起始的偏移
  static final _wordPattern = RegExp(
    r'(?:\[\d+,\d+\])?(?<content>(?:(?!\(\d+,\d+\)).)*)\((?<start>\d+),(?<duration>\d+)\)',
  );

  // 纯时间戳行（只有一个时间戳括号，无文字）
  static final _wordTimestampOnly = RegExp(r'^\(\d+,\d+\)$');

  // LRC 时间戳
  static final _lrcStampPattern = RegExp(r'\[(\d+):(\d{1,2})[.:](\d{1,3})\]');

  /// 解析 QRC 歌词（XML 或 LRC 格式）
  ParsedLyrics parse(String lyric) {
    // 尝试 XML 格式
    if (_qrcPattern.hasMatch(lyric)) {
      return _parseQrcXml(lyric);
    }
    // 尝试 LRC 格式
    if (lyric.contains('[') && lyric.contains(']')) {
      try {
        return _parseLrc(lyric);
      } catch (_) {
        //
      }
    }
    // 整段作为纯文本
    return ParsedLyrics(
      lines: [
        ParsedLine(
          startMs: 0,
          endMs: 0,
          words: [ParsedWord(startMs: 0, endMs: 0, text: lyric)],
        ),
      ],
    );
  }

  // 解析 QRC XML 格式
  ParsedLyrics _parseQrcXml(String sQrc) {
    final qrcMatch = _qrcPattern.firstMatch(sQrc);
    if (qrcMatch == null || qrcMatch.namedGroup('content') == null) {
      return const ParsedLyrics(lines: []);
    }

    final tags = <String, String>{};
    final lrcList = <ParsedLine>[];

    for (final rawLine in qrcMatch.namedGroup('content')!.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      final lineMatch = _linePattern.firstMatch(line);
      if (lineMatch != null) {
        final lineStart = int.parse(lineMatch.group(1)!);
        final lineEnd = lineStart + int.parse(lineMatch.group(2)!);
        final lineContent = lineMatch.group(3)!;

        // 跳过纯时间戳行（无歌词文字）
        if (lineContent.startsWith('(') &&
            lineContent.endsWith(')') &&
            _wordTimestampOnly.hasMatch(lineContent)) {
          lrcList.add(
            ParsedLine(startMs: lineStart, endMs: lineEnd, words: []),
          );
          continue;
        }

        // 解析逐字
        final words = <ParsedWord>[];
        for (final wm in _wordPattern.allMatches(lineContent)) {
          final wordContent = wm.namedGroup('content')!;

          if (wordContent == '\r') continue;

          final wordStart = int.parse(wm.namedGroup('start')!);
          final wordEnd = wordStart + int.parse(wm.namedGroup('duration')!);

          words.add(
            ParsedWord(startMs: wordStart, endMs: wordEnd, text: wordContent),
          );
        }

        if (words.isEmpty) {
          words.add(
            ParsedWord(startMs: lineStart, endMs: lineEnd, text: lineContent),
          );
        }

        lrcList.add(
          ParsedLine(startMs: lineStart, endMs: lineEnd, words: words),
        );
      } else {
        // 尝试解析为标签
        final tagMatch = _tagPattern.firstMatch(line);
        if (tagMatch != null) {
          tags[tagMatch.group(1)!] = tagMatch.group(2)!;
        }
      }
    }

    return ParsedLyrics(tags: tags, lines: lrcList);
  }

  // 解析纯 LRC 格式歌词
  ParsedLyrics _parseLrc(String lrcText) {
    final tags = <String, String>{};
    final lines = <ParsedLine>[];

    for (var raw in lrcText.split('\n')) {
      raw = raw.trim();
      if (raw.isEmpty) continue;

      // 提取所有时间戳
      final stamps = <int>[];
      var pos = 0;
      while (pos < raw.length) {
        final m = _lrcStampPattern.matchAsPrefix(raw, pos);
        if (m == null) break;
        final frac = m.group(3)!;
        final msFrac = int.parse(frac.padRight(3, '0').substring(0, 3));
        final ms =
            int.parse(m.group(1)!) * 60000 +
            int.parse(m.group(2)!) * 1000 +
            msFrac;
        stamps.add(ms);
        pos = m.end;
      }

      if (stamps.isNotEmpty) {
        final text = raw.substring(pos);
        for (final ms in stamps) {
          lines.add(
            ParsedLine(
              startMs: ms,
              endMs: ms, // LRC 行级没有 endMs，后续由 converter 处理
              words: [ParsedWord(startMs: ms, endMs: ms, text: text)],
            ),
          );
        }
      } else {
        // 标签行
        final tagMatch = _tagPattern.firstMatch(raw);
        if (tagMatch != null) {
          tags[tagMatch.group(1)!] = tagMatch.group(2)!;
        }
      }
    }

    // 按时间排序
    lines.sort((a, b) => a.startMs.compareTo(b.startMs));

    return ParsedLyrics(tags: tags, lines: lines);
  }
}
