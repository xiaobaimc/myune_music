import 'dart:typed_data';

abstract class PlatformMediaService {
  /// 更新元数据
  Future<void> updateMetadata({
    required String title,
    required String artist,
    String? album,
    Uint8List? albumArt,
  });

  /// 更新播放状态 (播放/暂停)
  Future<void> updateState(bool isPlaying);

  /// 更新时间轴信息
  Future<void> updateTimeline({
    required Duration position,
    required Duration duration,
  });

  /// 释放资源
  Future<void> dispose();
}
