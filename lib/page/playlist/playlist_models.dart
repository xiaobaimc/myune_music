import 'package:uuid/uuid.dart';
import 'dart:typed_data';

class Song {
  final String title;
  final String artist;
  final String album;
  final String filePath;
  final Uint8List? albumArt;
  final Duration? duration;

  Song({
    required this.title,
    required this.artist,
    this.album = '未知专辑',
    required this.filePath,
    this.albumArt,
    this.duration,
  });

  Map<String, dynamic> toJson() {
    return {'title': title, 'artist': artist, 'filePath': filePath};
  }

  factory Song.fromJson(Map<String, dynamic> json) {
    return Song(
      title: json['title'],
      artist: json['artist'],
      filePath: json['filePath'],
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

  LyricLine({required this.timestamp, required this.texts});
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
