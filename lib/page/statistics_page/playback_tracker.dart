import 'dart:async';
import '../playlist/playlist_models.dart';
import 'statistics_manager.dart';
import 'statistics_models.dart';

class PlaybackTracker {
  static final PlaybackTracker _instance = PlaybackTracker._internal();
  factory PlaybackTracker() => _instance;
  PlaybackTracker._internal();

  Song? _currentSong;
  DateTime? _playStartTime;
  Timer? _playTimer;
  bool _hasRecorded = false; // 添加标志位，跟踪是否已记录播放次数

  void startTracking(Song song) {
    // 如果正在跟踪其他歌曲，先停止跟踪
    stopTracking();

    _currentSong = song;
    _playStartTime = DateTime.now();
    _hasRecorded = false; // 新歌曲开始播放，重置标志位

    // 设置一个30秒的定时器
    _playTimer = Timer(
      const Duration(seconds: 30),
      _onPlaybackThresholdReached,
    );
  }

  void stopTracking() {
    _playTimer?.cancel();
    _playTimer = null;
    _currentSong = null;
    _playStartTime = null;
    _hasRecorded = false; // 停止跟踪时重置标志位
  }

  // 暂停跟踪（例如当歌曲暂停时）
  void pauseTracking() {
    _playTimer?.cancel();
  }

  // 恢复跟踪（例如当歌曲恢复播放时）
  void resumeTracking() {
    if (_currentSong != null && _playStartTime != null) {
      final elapsed = DateTime.now().difference(_playStartTime!);
      final remaining = const Duration(seconds: 30) - elapsed;

      if (remaining > Duration.zero) {
        _playTimer = Timer(remaining, _onPlaybackThresholdReached);
      } else if (!_hasRecorded) {
        // 如果已经超过了30秒且尚未记录，则记录播放次数
        _onPlaybackThresholdReached();
      }
    }
  }

  // 当播放达到阈值时调用
  void _onPlaybackThresholdReached() {
    if (_currentSong != null && !_hasRecorded) {
      // 只有未记录时才执行
      final stat = SongPlayStat(
        title: _currentSong!.title,
        artist: _currentSong!.artist,
        album: _currentSong!.album,
        path: _currentSong!.filePath,
      );

      StatisticsManager().recordSongPlayed(stat);
      _hasRecorded = true; // 标记为已记录
    }

    // 清理状态，但保持当前歌曲信息以便可能的继续播放
    _playTimer = null;
  }
}
