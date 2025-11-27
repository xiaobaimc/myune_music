import 'dart:convert';
import 'package:flutter/foundation.dart';

// 歌曲播放统计信息
class SongPlayStat {
  final String title;
  final String artist;
  final String album;
  final String path; // 唯一标识符
  int playCount;

  SongPlayStat({
    required this.title,
    required this.artist,
    required this.album,
    required this.path,
    this.playCount = 0,
  });

  // 从json创建对象
  factory SongPlayStat.fromJson(Map<String, dynamic> json) {
    return SongPlayStat(
      title: json['title'] as String,
      artist: json['artist'] as String,
      album: json['album'] as String,
      path: json['path'] as String,
      playCount: json['playCount'] as int? ?? 0,
    );
  }

  // 转换为json
  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'artist': artist,
      'album': album,
      'path': path,
      'playCount': playCount,
    };
  }

  // 更新歌曲信息（保留播放次数）
  SongPlayStat copyWithUpdatedInfo({
    String? title,
    String? artist,
    String? album,
  }) {
    return SongPlayStat(
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      path: path,
      playCount: playCount,
    );
  }
}

class StatisticsData extends ChangeNotifier {
  final Map<String, SongPlayStat> _songStats = {};

  StatisticsData();

  Map<String, SongPlayStat> get songStats => Map.unmodifiable(_songStats);

  // 用于更新统计数据的方法
  void updateStats(Map<String, SongPlayStat> newStats) {
    _songStats.clear();
    _songStats.addAll(newStats);
    notifyListeners();
  }

  // 添加或更新歌曲播放统计
  void recordSongPlayed(SongPlayStat stat) {
    final existingStat = _songStats[stat.path];
    if (existingStat != null) {
      // 如果已存在，增加播放次数
      _songStats[stat.path] = SongPlayStat(
        title: stat.title,
        artist: stat.artist,
        album: stat.album,
        path: stat.path,
        playCount: existingStat.playCount + 1,
      );
    } else {
      // 如果不存在，添加新的统计记录（播放次数为1）
      _songStats[stat.path] = SongPlayStat(
        title: stat.title,
        artist: stat.artist,
        album: stat.album,
        path: stat.path,
        playCount: 1,
      );
    }

    notifyListeners();
  }

  // 获取歌曲播放排行榜（前N名）
  List<SongPlayStat> getTopPlayedSongs([int limit = 5]) {
    final sortedSongs = _songStats.values.toList()
      ..sort((a, b) => b.playCount.compareTo(a.playCount));
    return sortedSongs.take(limit).toList();
  }

  // 获取艺术家播放排行榜（前N名）
  List<MapEntry<String, int>> getTopArtists([
    int limit = 5,
    List<String>? separators,
  ]) {
    final artistPlayCounts = <String, int>{};

    for (final stat in _songStats.values) {
      final artists = _splitArtists(stat.artist, separators);
      for (final artist in artists) {
        final cleanArtist = artist.trim();
        if (cleanArtist.isNotEmpty) {
          artistPlayCounts[cleanArtist] =
              (artistPlayCounts[cleanArtist] ?? 0) + stat.playCount;
        }
      }
    }

    final sortedArtists = artistPlayCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sortedArtists.take(limit).toList();
  }

  // 获取专辑播放排行榜（前N名）
  List<MapEntry<String, int>> getTopAlbums([int limit = 5]) {
    final albumPlayCounts = <String, int>{};

    for (final stat in _songStats.values) {
      if (stat.album.trim().isNotEmpty) {
        albumPlayCounts[stat.album] =
            (albumPlayCounts[stat.album] ?? 0) + stat.playCount;
      }
    }

    final sortedAlbums = albumPlayCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sortedAlbums.take(limit).toList();
  }

  // 分割艺术家字符串
  List<String> _splitArtists(String artistString, List<String>? separators) {
    // 使用传入的分隔符或者默认分隔符
    final sepList = separators ?? const [';', '；', ',', '，', '、'];

    var result = [artistString];
    for (final separator in sepList) {
      final newResult = <String>[];
      for (final str in result) {
        newResult.addAll(str.split(separator));
      }
      result = newResult;
    }

    return result;
  }

  // 总歌曲数
  int get totalSongs => _songStats.length;

  // 总播放次数
  int get totalPlays {
    return _songStats.values.fold(0, (sum, stat) => sum + stat.playCount);
  }

  // 从json加载数据
  factory StatisticsData.fromJson(String jsonString) {
    final data = StatisticsData();
    if (jsonString.isNotEmpty) {
      try {
        final json = jsonDecode(jsonString) as Map<String, dynamic>;
        if (json['songs'] != null) {
          final songsJson = json['songs'] as List<dynamic>;
          for (final songJson in songsJson) {
            final stat = SongPlayStat.fromJson(
              songJson as Map<String, dynamic>,
            );
            data._songStats[stat.path] = stat;
          }
        }
      } catch (e) {
        // 流空
      }
    }
    return data;
  }

  // 转换为json
  String toJson() {
    final songsJson = _songStats.values.map((stat) => stat.toJson()).toList();
    return jsonEncode({'songs': songsJson});
  }
}
