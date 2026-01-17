import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'statistics_models.dart';

class StatisticsManager {
  static final StatisticsManager _instance = StatisticsManager._internal();
  factory StatisticsManager() => _instance;
  StatisticsManager._internal();

  final StatisticsData _statisticsData = StatisticsData();
  StatisticsData get statisticsData => _statisticsData;

  late String _statisticsFilePath;

  // 初始化统计管理器
  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    final appDir = Directory(p.join(dir.path, 'myune_music'));
    if (!await appDir.exists()) {
      await appDir.create(recursive: true);
    }
    _statisticsFilePath = p.join(appDir.path, 'statistics.json');
    await _loadStatistics();
  }

  // 加载统计数据
  Future<void> _loadStatistics() async {
    try {
      final file = File(_statisticsFilePath);
      if (await file.exists()) {
        final jsonString = await file.readAsString();
        final newData = StatisticsData.fromJson(jsonString);

        // 将加载的数据复制到当前实例
        _statisticsData.updateStats(newData.songStats);
      }
    } catch (e) {
      //
    }
  }

  // 保存统计数据
  Future<void> _saveStatistics() async {
    try {
      final jsonString = _statisticsData.toJson();
      final file = File(_statisticsFilePath);
      await file.writeAsString(jsonString);
    } catch (e) {
      //
    }
  }

  // 记录歌曲播放（超过30秒）
  void recordSongPlayed(SongPlayStat stat) {
    _statisticsData.recordSongPlayed(stat);
    // 异步保存，不影响播放体验
    _saveStatistics();
  }

  // 获取歌曲播放排行榜
  List<SongPlayStat> getTopPlayedSongs([int limit = 5]) {
    return _statisticsData.getTopPlayedSongs(limit);
  }

  // 获取艺术家播放排行榜
  List<MapEntry<String, int>> getTopArtists([
    int limit = 5,
    List<String>? separators,
  ]) {
    return _statisticsData.getTopArtists(limit, separators);
  }

  // 获取专辑播放排行榜
  List<MapEntry<String, int>> getTopAlbums([int limit = 5]) {
    return _statisticsData.getTopAlbums(limit);
  }

  // 总歌曲数
  int get totalSongs => _statisticsData.totalSongs;

  // 总播放次数
  int get totalPlays => _statisticsData.totalPlays;

  // 清空所有统计数据
  Future<void> clearAllStats() async {
    _statisticsData.clearStats();
    await _saveStatistics();
  }
}
