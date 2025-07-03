import 'dart:io';

import 'package:flutter/foundation.dart';
import 'src/rust/api/smtc.dart';

class SmtcManager {
  final SmtcFlutter? _smtc;

  final Future<void> Function()? onPlay;
  final Future<void> Function()? onPause;
  final Future<void> Function()? onNext;
  final Future<void> Function()? onPrevious;

  SmtcManager({this.onPlay, this.onPause, this.onNext, this.onPrevious})
    : _smtc = Platform.isWindows ? SmtcFlutter() : null {
    _subscribeEvents();
  }

  /// 订阅控制按钮事件
  void _subscribeEvents() {
    if (_smtc == null) return;

    _smtc.subscribeToControlEvents().listen((event) async {
      switch (event) {
        case SMTCControlEvent.play:
          if (onPlay != null) await onPlay!();
          break;
        case SMTCControlEvent.pause:
          if (onPause != null) await onPause!();
          break;
        case SMTCControlEvent.next:
          if (onNext != null) await onNext!();
          break;
        case SMTCControlEvent.previous:
          if (onPrevious != null) await onPrevious!();
          break;
        default:
          break;
      }
    });
  }

  /// 更新元数据
  Future<void> updateMetadata({
    required String title,
    required String artist,
    Uint8List? albumArt,
  }) async {
    if (_smtc == null) return;

    try {
      debugPrint(
        'SMTC 更新元数据: title=$title, artist=$artist, albumArt=${albumArt != null ? "${albumArt.length} bytes" : "null"}',
      );
      await _smtc.updateDisplay(
        title: title,
        artist: artist,
        imagePath: null,
        imageData: albumArt,
      );
    } catch (e) {
      debugPrint('更新SMTC元数据失败: $e');
    }
  }

  /// 更新播放状态
  Future<void> updateState(bool isPlaying) async {
    if (_smtc == null) return;

    try {
      await _smtc.updateState(
        state: isPlaying ? SMTCState.playing : SMTCState.paused,
      );
    } catch (e) {
      // debugPrint('更新SMTC状态失败: $e');
    }
  }

  /// 关闭SMTC
  Future<void> close() async {
    if (_smtc == null) return;

    try {
      await _smtc.close();
    } catch (e) {
      // debugPrint('关闭SMTC失败: $e');
    }
  }
}
