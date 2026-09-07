import '../../page/playlist/playlist_models.dart';
import 'parsed_models.dart';

class LyricConverter {
  static List<LyricLine> convert(ParsedLyrics parsed) {
    final lines = <LyricLine>[];

    // 预处理有效的翻译行列表（过滤 '//' 及空文本）
    final validTranslations = <ParsedLine>[];
    for (final tl in parsed.translationLines) {
      final t = tl.text.trim();
      if (t.isNotEmpty &&
          t != '//' &&
          t.replaceAll(RegExp(r'\s+'), '') != '//') {
        validTranslations.add(tl);
      }
    }

    final usedTranslationIndices = <int>{};

    for (var i = 0; i < parsed.lines.length; i++) {
      final parsedLine = parsed.lines[i];
      final texts = <String>[];
      final tokensList = <List<LyricToken>>[];
      final karaokeTextIndices = <int>[];

      // 原文纯文本
      final origText = parsedLine.text.trim();
      if (origText.isNotEmpty) {
        if (parsedLine.hasWordTimestamps) {
          // 有逐字时间戳：加入 tokens，记录在 texts 中的下标
          final tokens = _buildTokensWithPauses(parsedLine.words);
          if (tokens.isNotEmpty) {
            karaokeTextIndices.add(texts.length); // 记录原文将在 texts 中的位置
            texts.add(origText);
            tokensList.add(tokens);
          } else {
            texts.add(origText);
          }
        } else {
          texts.add(origText);
        }
      }

      // 翻译文本严格按时间戳匹配（误差不超过 20 毫秒）
      String? matchedTransText;

      // 1. 如果 translationLines 与 lines 行数相同且同索引时间戳误差 <= 20ms（同源结构对齐，如酷狗 KRC）
      if (parsed.translationLines.length == parsed.lines.length &&
          i < parsed.translationLines.length) {
        final candidate = parsed.translationLines[i];
        if ((candidate.startMs - parsedLine.startMs).abs() <= 20) {
          final directTrans = candidate.text.trim();
          if (directTrans.isNotEmpty &&
              directTrans != '//' &&
              directTrans.replaceAll(RegExp(r'\s+'), '') != '//') {
            matchedTransText = directTrans;
          }
        }
      }

      // 2. 否则在有效翻译列表中寻找时间戳误差 <= 20ms 的最近行（网易云、QQ音乐等独立 LRC）
      if (matchedTransText == null && validTranslations.isNotEmpty) {
        var bestIdx = -1;
        var minDiff = 21;

        for (var j = 0; j < validTranslations.length; j++) {
          if (usedTranslationIndices.contains(j)) continue;
          final diff = (validTranslations[j].startMs - parsedLine.startMs)
              .abs();
          if (diff < minDiff) {
            minDiff = diff;
            bestIdx = j;
          }
        }

        if (bestIdx >= 0) {
          usedTranslationIndices.add(bestIdx);
          matchedTransText = validTranslations[bestIdx].text.trim();
        }
      }

      if (matchedTransText != null && matchedTransText.isNotEmpty) {
        // 翻译行不加入 tokensList，也不加入 karaokeTextIndices
        texts.add(matchedTransText);
      }

      //  3.罗马音（卡拉OK行，排在翻译之后）
      if (i < parsed.romajiLines.length &&
          parsed.romajiLines[i].hasWordTimestamps) {
        final romajiLine = parsed.romajiLines[i];
        final romajiText = romajiLine.text.trim();
        final romaTokens = _buildTokensWithPauses(romajiLine.words);

        if (romaTokens.isNotEmpty && romajiText.isNotEmpty) {
          karaokeTextIndices.add(texts.length); // 记录罗马音将在 texts 中的位置
          texts.add(romajiText);
          tokensList.add(romaTokens);
        }
      }

      lines.add(
        LyricLine(
          timestamp: Duration(milliseconds: parsedLine.startMs),
          texts: texts,
          tokens: tokensList.isNotEmpty ? tokensList : null,
          karaokeTextIndices: karaokeTextIndices.isNotEmpty
              ? karaokeTextIndices
              : null,
        ),
      );
    }

    return lines;
  }

  static List<LyricToken> _buildTokensWithPauses(List<ParsedWord> words) {
    final tokens = <LyricToken>[];

    for (var i = 0; i < words.length; i++) {
      final word = words[i];

      // 跳过空文本的 word（但保留后续停顿检测）
      if (word.text.isNotEmpty) {
        tokens.add(
          LyricToken(
            text: word.text,
            start: Duration(milliseconds: word.startMs),
            end: Duration(milliseconds: word.endMs),
          ),
        );
      }

      // 检查与下一个 word 之间是否有时间间隙
      if (i + 1 < words.length) {
        final nextWord = words[i + 1];
        if (word.endMs < nextWord.startMs) {
          tokens.add(
            LyricToken(
              text: '\u200B', // 零宽字符，不可见但让 UI 知道有停顿
              start: Duration(milliseconds: word.endMs),
              end: Duration(milliseconds: nextWord.startMs),
            ),
          );
        }
      }
    }

    return tokens;
  }
}
