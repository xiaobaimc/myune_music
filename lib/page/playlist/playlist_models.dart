import 'dart:convert';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

class Song {
  final String title;
  final String artist;
  final String album;
  final String filePath;
  final String normalizedPath; // 缓存归一化路径，避免热路径上重复调用 p.normalize
  final Uint8List? albumArt;
  final Duration? duration;
  final int? trackNumber;
  final String? genre;

  Song({
    required this.title,
    required this.artist,
    this.album = '未知专辑',
    required this.filePath,
    this.albumArt,
    this.duration,
    this.trackNumber,
    this.genre,
  }) : normalizedPath = _normalizeForCache(filePath);

  /// 网络媒体（WebDAV / FTP）的 filePath 是本机流代理 URL，不能被 `p.normalize`
  /// 当成文件路径处理（它会把 `http://` 的斜杠折叠成反斜杠，破坏 URL 语义）。
  /// 这类地址本身就是唯一标识，直接原样返回；本地路径仍走原来的归一化。
  static String _normalizeForCache(String filePath) {
    if (filePath.contains('://')) return filePath;
    return p.normalize(filePath);
  }

  /// 封面写入 JSON，让播放队列 / 歌单里的网络媒体在应用重启后仍能直接显示
  /// 封面（网络流没有本地文件可读）。设置上限避免偏好存储被超大图撑爆。
  static const int _maxPersistedArtworkBytes = 512 * 1024;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'title': title,
      'artist': artist,
      'album': album,
      'filePath': filePath,
      'genre': genre,
      if (duration != null) 'durationMs': duration!.inMilliseconds,
      if (trackNumber != null) 'trackNumber': trackNumber,
      if (albumArt != null &&
          albumArt!.isNotEmpty &&
          albumArt!.length <= _maxPersistedArtworkBytes)
        'albumArt': base64Encode(albumArt!),
    };
  }

  factory Song.fromJson(Map<String, dynamic> json) {
    Uint8List? art;
    final rawArt = json['albumArt'];
    if (rawArt is String && rawArt.isNotEmpty) {
      try {
        art = base64Decode(rawArt);
      } catch (_) {
        art = null;
      }
    }
    final rawDuration = json['durationMs'];
    final durationMs =
        rawDuration is num ? rawDuration.toInt() : int.tryParse('$rawDuration');
    final rawTrack = json['trackNumber'];
    return Song(
      title: (json['title'] ?? '未知歌曲').toString(),
      artist: (json['artist'] ?? '未知歌手').toString(),
      album: (json['album'] ?? '未知专辑').toString(),
      filePath: (json['filePath'] ?? '').toString(),
      genre: json['genre'] as String?,
      albumArt: art,
      duration: (durationMs != null && durationMs > 0)
          ? Duration(milliseconds: durationMs)
          : null,
      trackNumber: rawTrack is num ? rawTrack.toInt() : null,
    );
  }
}

// 歌单歌曲元数据缓存
class SongMetadataCacheEntry {
  final String title;
  final String artist;
  final String album;
  final int? durationMs;
  final int modifiedMs;
  final String? genre;

  // 是否已经读取过扩展标签
  // 旧版本缓存没有这个字段，需要按 false 处理并在之后补读一次
  final bool extraTagsLoaded;

  const SongMetadataCacheEntry({
    required this.title,
    required this.artist,
    required this.album,
    required this.modifiedMs,
    this.durationMs,
    this.genre,
    this.extraTagsLoaded = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'artist': artist,
      'album': album,
      'durationMs': durationMs,
      'modifiedMs': modifiedMs,
      'genre': genre,
      'extraTagsLoaded': extraTagsLoaded,
    };
  }

  factory SongMetadataCacheEntry.fromJson(Map<String, dynamic> json) {
    return SongMetadataCacheEntry(
      title: json['title'] ?? '',
      artist: json['artist'] ?? '',
      album: json['album'] ?? '',
      durationMs: json['durationMs'],
      modifiedMs: json['modifiedMs'] ?? 0,
      genre: json['genre'] as String?,
      extraTagsLoaded: json['extraTagsLoaded'] ?? false,
    );
  }
}

class Playlist {
  final String id;
  String name;
  final bool isDefault;
  List<String> songFilePaths;
  List<Song>? songs; // 直接在歌单对象中存储已解析的歌曲

  // 保存当前歌单播放歌曲的索引
  int? currentPlayingIndex;

  // 标识是否为文件夹播放列表
  bool isFolderBased;
  // 存储相关文件夹路径
  List<String> folderPaths;

  Playlist({
    String? id,
    required this.name,
    this.isDefault = false,
    List<String>? songFilePaths,
    this.currentPlayingIndex,
    this.songs,
    this.isFolderBased = false,
    List<String>? folderPaths,
  }) : id = id ?? const Uuid().v4(),
       songFilePaths = songFilePaths ?? [],
       folderPaths = folderPaths ?? [];

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'isDefault': isDefault,
      'currentPlayingIndex': currentPlayingIndex,
      'isFolderBased': isFolderBased,
      'folderPaths': folderPaths,
    };
  }

  factory Playlist.fromJson(Map<String, dynamic> json) {
    return Playlist(
      id: json['id'],
      name: json['name'],
      isDefault: json['isDefault'] ?? false,
      currentPlayingIndex: json['currentPlayingIndex'],
      isFolderBased: json['isFolderBased'] ?? false,
      folderPaths: json['folderPaths'] != null
          ? List<String>.from(json['folderPaths'])
          : [],
    );
  }
}

class LyricLine {
  final Duration timestamp;
  final List<String> texts;

  final List<List<LyricToken>>? tokens;

  // 为 null 时表示无卡拉OK行
  final List<int>? karaokeTextIndices;

  final bool isInterlude;
  final Duration? interludeDuration;

  LyricLine({
    required this.timestamp,
    required this.texts,
    this.tokens,
    this.karaokeTextIndices,
    this.isInterlude = false,
    this.interludeDuration,
  });

  bool get isKaraoke => tokens != null && tokens!.isNotEmpty;
}

class LyricToken {
  final String text;
  final Duration start;
  final Duration end;

  LyricToken({required this.text, required this.start, required this.end});
}

class SongDetails {
  final String? title;
  final String? artist;
  final String? album;
  final Duration? duration;
  final Uint8List? albumArt;
  final int? bitrate;
  final int? sampleRate;
  final String filePath;
  final DateTime? created;
  final DateTime? modified;
  final int? year;
  final String? genre;
  final String? albumArtist;

  SongDetails({
    this.title,
    this.artist,
    this.album,
    this.duration,
    this.albumArt,
    this.bitrate,
    this.sampleRate,
    required this.filePath,
    this.created,
    this.modified,
    this.year,
    this.genre,
    this.albumArtist,
  });
}

class PlaybackState {
  final String? playlistId;
  final int songIndex;

  PlaybackState({this.playlistId, required this.songIndex});

  Map<String, dynamic> toJson() {
    return {'playlistId': playlistId, 'songIndex': songIndex};
  }

  factory PlaybackState.fromJson(Map<String, dynamic> json) {
    return PlaybackState(
      playlistId: json['playlistId'],
      songIndex: json['songIndex'],
    );
  }
}
