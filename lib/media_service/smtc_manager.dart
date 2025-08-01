import 'dart:io';
import 'package:flutter/foundation.dart';

// 导入我们新创建的文件
import 'platform_media_service.dart';
import 'windows_media_service.dart';
import 'linux_media_service.dart';

class SmtcManager {
  final PlatformMediaService? _service;

  factory SmtcManager({
    Future<void> Function()? onPlay,
    Future<void> Function()? onPause,
    Future<void> Function()? onNext,
    Future<void> Function()? onPrevious,
    // 添加新的回调
    Future<void> Function(Duration position)? onSeek,
    Future<void> Function(String trackId, Duration position)? onSetPosition,
  }) {
    if (kIsWeb) {
      return SmtcManager._internal(null);
    }

    PlatformMediaService? service;
    if (Platform.isWindows) {
      service = WindowsMediaService(
        onPlay: onPlay,
        onPause: onPause,
        onNext: onNext,
        onPrevious: onPrevious,
      );
    } else if (Platform.isLinux) {
      // 确保 onSeek 和 onSetPosition 不为 null
      if (onSeek == null || onSetPosition == null) {
        throw ArgumentError(
          'onSeek and onSetPosition must be provided for Linux.',
        );
      }
      service = LinuxMediaService(
        onPlay: onPlay,
        onPause: onPause,
        onNext: onNext,
        onPrevious: onPrevious,
        onSeek: onSeek,
        onSetPosition: onSetPosition,
      );
    }
    return SmtcManager._internal(service);
  }

  SmtcManager._internal(this._service);

  /// 更新元数据
  Future<void> updateMetadata({
    required String title,
    required String artist,
    String? album,
    Uint8List? albumArt,
  }) async {
    await _service?.updateMetadata(
      title: title,
      artist: artist,
      album: album,
      albumArt: albumArt,
    );
  }

  /// 更新播放状态
  Future<void> updateState(bool isPlaying) async {
    await _service?.updateState(isPlaying);
  }

  /// 更新时间轴信息
  Future<void> updateTimeline({
    required Duration position,
    required Duration duration,
  }) async {
    await _service?.updateTimeline(position: position, duration: duration);
  }

  /// 关闭/释放资源
  Future<void> dispose() async {
    await _service?.dispose();
  }
}
