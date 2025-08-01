import 'package:uuid/uuid.dart';
import 'dart:typed_data';

class Song {
  final String title;
  final String artist;
  final String album;
  final String filePath;
  final Uint8List? albumArt;

  Song({
    required this.title,
    required this.artist,
    this.album = '未知专辑',
    required this.filePath,
    this.albumArt,
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

  // 保存当前歌单播放歌曲的索引
  int? currentPlayingIndex;

  Playlist({
    String? id,
    required this.name,
    this.isDefault = false,
    List<String>? songFilePaths,
    this.currentPlayingIndex,
  }) : id = id ?? const Uuid().v4(),
       songFilePaths = songFilePaths ?? [];

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'isDefault': isDefault,
      'currentPlayingIndex': currentPlayingIndex,
    };
  }

  factory Playlist.fromJson(Map<String, dynamic> json) {
    return Playlist(
      id: json['id'],
      name: json['name'],
      isDefault: json['isDefault'] ?? false,
      currentPlayingIndex: json['currentPlayingIndex'],
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
