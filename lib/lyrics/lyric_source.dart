enum LyricSource {
  embedded('embedded', '内嵌歌词', '读取音频文件标签中内嵌的歌词'),
  externalLrc('lrc', '外置LRC文件', '读取歌曲同目录下的同名 .lrc 文件'),
  externalKrc('krc', '外置KRC文件', '读取歌曲同目录下的同名 .krc 文件'),
  externalQrc('qrc', '外置QRC文件', '读取歌曲同目录下的同名 .qrc 文件'),
  externalYrc('yrc', '外置YRC文件', '读取歌曲同目录下的同名 .yrc 文件'),
  online('online', '网络歌词', '搜索选中的歌词源，未启用时不生效');

  const LyricSource(this.id, this.label, this.description);

  // 持久化用的稳定标识，不要随意改动
  final String id;

  final String label;

  final String description;

  // 默认优先级：内嵌->外置LRC->外置KRC->外置QRC->外置YRC->网络
  static const List<LyricSource> defaultOrder = [
    embedded,
    externalLrc,
    externalKrc,
    externalQrc,
    externalYrc,
    online,
  ];

  static const List<String> defaultOrderIds = [
    'embedded',
    'lrc',
    'krc',
    'qrc',
    'yrc',
    'online',
  ];

  // 是否为外置歌词文件来源
  bool get isExternalFile =>
      this == externalLrc ||
      this == externalKrc ||
      this == externalQrc ||
      this == externalYrc;

  // 外置歌词文件使用的扩展名，非外置来源返回 null
  String? get fileExtension => switch (this) {
    externalLrc => 'lrc',
    externalKrc => 'krc',
    externalQrc => 'qrc',
    externalYrc => 'yrc',
    _ => null,
  };

  static LyricSource? fromId(String id) {
    for (final source in LyricSource.values) {
      if (source.id == id) return source;
    }
    return null;
  }

  // 规范化顺序：丢弃未知项、去掉重复项，并把缺失的来源按默认顺序补到末尾
  static List<String> normalizeOrder(Iterable<String> ids) {
    final result = <String>[];
    for (final id in ids) {
      if (fromId(id) != null && !result.contains(id)) {
        result.add(id);
      }
    }
    for (final id in defaultOrderIds) {
      if (!result.contains(id)) {
        result.add(id);
      }
    }
    return result;
  }
}
