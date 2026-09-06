class ParsedWord {
  final int startMs;
  final int endMs;

  final String text;

  const ParsedWord({
    required this.startMs,
    required this.endMs,
    required this.text,
  });

  @override
  String toString() => 'ParsedWord($startMs-$endMs, "$text")';
}

class ParsedLine {
  final int startMs;
  final int endMs;

  final List<ParsedWord> words;

  const ParsedLine({
    required this.startMs,
    required this.endMs,
    required this.words,
  });

  // 该行是否有逐字时间戳（多于 1 个 word）
  bool get hasWordTimestamps => words.length > 1;

  String get text => words.map((w) => w.text).join();

  @override
  String toString() => 'ParsedLine($startMs-$endMs, ${words.length} words)';
}

// 解析结果（包含原文、翻译、罗马音）
class ParsedLyrics {
  final Map<String, String> tags;

  final List<ParsedLine> lines;
  final List<ParsedLine> translationLines;
  final List<ParsedLine> romajiLines;

  const ParsedLyrics({
    this.tags = const {},
    required this.lines,
    this.translationLines = const [],
    this.romajiLines = const [],
  });

  /// 是否包含逐字时间戳
  bool get hasWordTimestamps => lines.any((l) => l.hasWordTimestamps);
}
