import 'dart:async';
import 'package:flutter/foundation.dart';
import '../src/rust/api/smtc.dart';
import 'platform_media_service.dart';

class WindowsMediaService implements PlatformMediaService {
  final SmtcFlutter _smtc;
  Timer? _timelineUpdateTimer;
  int? _lastPosition;
  int? _lastDuration;

  WindowsMediaService({
    Future<void> Function()? onPlay,
    Future<void> Function()? onPause,
    Future<void> Function()? onNext,
    Future<void> Function()? onPrevious,
  }) : _smtc = SmtcFlutter() {
    _subscribeEvents(onPlay, onPause, onNext, onPrevious);
  }

  void _subscribeEvents(
    Future<void> Function()? onPlay,
    Future<void> Function()? onPause,
    Future<void> Function()? onNext,
    Future<void> Function()? onPrevious,
  ) {
    _smtc.subscribeToControlEvents().listen((event) async {
      switch (event) {
        case SMTCControlEvent.play:
          await onPlay?.call();
          break;
        case SMTCControlEvent.pause:
          await onPause?.call();
          break;
        case SMTCControlEvent.next:
          await onNext?.call();
          break;
        case SMTCControlEvent.previous:
          await onPrevious?.call();
          break;
        default:
          break;
      }
    });
  }

  @override
  Future<void> updateMetadata({
    required String title,
    required String artist,
    String? album, // Windows SMTC 不直接支持 album 字段
    Uint8List? albumArt,
  }) async {
    try {
      await _smtc.updateDisplay(
        title: title,
        artist: artist,
        imagePath: null,
        imageData: albumArt ?? Uint8List(0),
      );
    } catch (e) {
      debugPrint('更新SMTC元数据失败: $e');
    }
  }

  @override
  Future<void> updateState(bool isPlaying) async {
    try {
      await _smtc.updateState(
        state: isPlaying ? SMTCState.playing : SMTCState.paused,
      );
    } catch (e) {
      debugPrint('更新SMTC状态失败: $e');
    }
  }

  @override
  Future<void> updateTimeline({
    required Duration position,
    required Duration duration,
  }) async {
    // 防抖
    final positionMs = position.inMilliseconds;
    final durationMs = duration.inMilliseconds;
    if (_lastPosition == positionMs && _lastDuration == durationMs) return;

    _lastPosition = positionMs;
    _lastDuration = durationMs;

    if (_timelineUpdateTimer?.isActive ?? false) return;
    _timelineUpdateTimer = Timer(const Duration(milliseconds: 500), () async {
      try {
        // SmtcFlutter 需要的是 int，这里要做转换
        await _smtc.updateTimeline(position: positionMs, duration: durationMs);
      } catch (e) {
        debugPrint('更新SMTC时间轴失败: $e');
      }
    });
  }

  @override
  Future<void> dispose() async {
    _timelineUpdateTimer?.cancel();
    try {
      await _smtc.close();
    } catch (e) {
      debugPrint('关闭SMTC失败: $e');
    }
  }
}
