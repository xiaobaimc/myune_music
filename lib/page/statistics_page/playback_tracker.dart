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
  Duration _accumulatedPlayTime = Duration.zero; // 累计播放时间

  void startTracking(Song song) {
    // 如果正在跟踪其他歌曲，先停止跟踪
    stopTracking();

    _currentSong = song;
    _playStartTime = DateTime.now();
    _hasRecorded = false; // 新歌曲开始播放，重置标志位
    _accumulatedPlayTime = Duration.zero; // 重置累计播放时间

    // 设置一个30秒的定时器
    _updateTimer();
  }

  void stopTracking() {
    _playTimer?.cancel();
    _playTimer = null;
    _currentSong = null;
    _playStartTime = null;
    _hasRecorded = false; // 停止跟踪时重置标志位
    _accumulatedPlayTime = Duration.zero; // 重置累计播放时间
  }

  // 暂停跟踪（例如当歌曲暂停时）
  void pauseTracking() {
    if (_playTimer != null && _playStartTime != null) {
      // 累加本次播放时间
      _accumulatedPlayTime += DateTime.now().difference(_playStartTime!);
      _playTimer?.cancel();
      _playTimer = null;
      _playStartTime = null;
    }
  }

  // 恢复跟踪（例如当歌曲恢复播放时）
  void resumeTracking() {
    if (_currentSong != null && !_hasRecorded) {
      _playStartTime = DateTime.now();
      _updateTimer();
    }
  }

  // 更新定时器
  void _updateTimer() {
    if (_playStartTime == null) return;

    final remaining = const Duration(seconds: 30) - _accumulatedPlayTime;

    if (remaining > Duration.zero) {
      _playTimer?.cancel();
      _playTimer = Timer(remaining, _onPlaybackThresholdReached);
    } else if (!_hasRecorded) {
      // 如果累计播放时间已经超过30秒且尚未记录，则立即记录播放次数
      _onPlaybackThresholdReached();
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
