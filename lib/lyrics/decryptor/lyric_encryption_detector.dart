class LyricEncryptionDetector {
  LyricEncryptionDetector._();

  // Base64("krc1" + ...) 的前 4 个字符恒为 "a3Jj"
  // 所以只比较 4 个字符就能判定是不是加密 KRC，无需 base64 解码
  static const String _krcBase64MagicPrefix = 'a3Jj';

  // 头部采样长度：判定是否纯十六进制/Base64 时最多看这么多字符
  static const int _probeLength = 64;

  // 疑似编码内容的最小长度：太短的字符串更可能是正常歌词
  static const int _minBlobLength = 128;

  // 加密 KRC（Base64 文本，解码后以 "krc1" 魔数开头）
  static bool isEncryptedKrc(String content) {
    return _skipLeadingNoise(content).startsWith(_krcBase64MagicPrefix);
  }

  // 加密 QRC（3DES + zlib 后的十六进制文本）
  static bool isEncryptedQrc(String content) {
    final text = _skipLeadingNoise(content);
    if (text.isEmpty) return false;

    final first = text.codeUnitAt(0);
    // '<' => XML 明文，'[' => 裸 QRC / LRC 明文
    if (first == 0x3C || first == 0x5B) return false;

    return _isHexBlob(text);
  }

  // YRC 是否处于「无法直接解析」的形态（未知加密/二进制）
  static bool isEncryptedYrc(String content) {
    final text = _skipLeadingNoise(content);
    if (text.isEmpty) return false;
    return _isBase64Blob(text) || _isHexBlob(text);
  }

  // 去掉 UTF-8 BOM 与行首空白（Windows 编辑器保存的歌词文件常见 BOM）
  static String _skipLeadingNoise(String content) {
    var start = 0;
    while (start < content.length) {
      final c = content.codeUnitAt(start);
      if (c == 0xFEFF || c == 0x0A || c == 0x0D || c == 0x20 || c == 0x09) {
        start++;
      } else {
        break;
      }
    }
    return content.substring(start);
  }

  // 采样头部判断是否为足够长的纯十六进制文本（允许换行/空格）
  static bool _isHexBlob(String text) {
    return _scanBlob(text, _isHexDigit);
  }

  // 采样头部判断是否为足够长的纯 Base64 文本（允许换行/空格）
  static bool _isBase64Blob(String text) {
    return _scanBlob(text, _isBase64Char);
  }

  static bool _scanBlob(String text, bool Function(int codeUnit) accept) {
    if (text.length < _minBlobLength) return false;

    var matched = 0;
    for (var i = 0; i < text.length && matched < _probeLength; i++) {
      final c = text.codeUnitAt(i);
      if (accept(c)) {
        matched++;
        continue;
      }
      // 编码后的文本常被按固定宽度折行，允许换行与空格
      if (c == 0x0A || c == 0x0D || c == 0x20 || c == 0x09) continue;
      return false;
    }
    return matched >= _probeLength;
  }

  static bool _isHexDigit(int c) {
    return (c >= 0x30 && c <= 0x39) || // 0-9
        (c >= 0x41 && c <= 0x46) || // A-F
        (c >= 0x61 && c <= 0x66); // a-f
  }

  static bool _isBase64Char(int c) {
    return (c >= 0x41 && c <= 0x5A) || // A-Z
        (c >= 0x61 && c <= 0x7A) || // a-z
        (c >= 0x30 && c <= 0x39) || // 0-9
        c == 0x2B || // +
        c == 0x2F || // /
        c == 0x3D; // =
  }
}
