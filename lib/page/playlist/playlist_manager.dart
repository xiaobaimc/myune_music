import 'dart:convert';
import 'dart:io';
import 'playlist_models.dart';

class PlaylistManager {
  static const String _playlistMetadataFileName = 'playlists_metadata.json';
  static const String _songsSubdirectory = 'playlist_songs';
  static const String _allSongsOrderFileName = 'all_songs_order.json';

  Future<String> _getLocalPath() async {
    // 当前目录 + list_data 子目录
    final directory = Directory('list_data');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory.path;
  }

  // 获取歌单元数据文件的路径
  Future<File> _getMetadataFile() async {
    final path = await _getLocalPath();
    return File('$path/$_playlistMetadataFileName');
  }

  // 获取单个歌单歌曲路径文件的路径
  Future<File> _getSongFile(String playlistId) async {
    final path = await _getLocalPath();
    final songsDir = Directory('$path/$_songsSubdirectory');
    // 确保歌曲目录存在
    if (!await songsDir.exists()) {
      await songsDir.create(recursive: true);
    }
    return File('${songsDir.path}/$playlistId.json');
  }

  Future<List<Playlist>> loadPlaylists() async {
    final List<Playlist> loadedPlaylists = [];
    try {
      final metadataFile = await _getMetadataFile();
      if (!await metadataFile.exists()) {
        // 如果元数据文件不存在，则创建默认歌单并保存
        final List<Playlist> defaultPlaylists = [
          Playlist(name: '收藏', isDefault: true),
        ];
        // 调用 savePlaylists 会同时保存元数据和歌曲文件
        await savePlaylists(defaultPlaylists);
        return defaultPlaylists;
      }

      final contents = await metadataFile.readAsString();
      final List<dynamic> jsonList = jsonDecode(contents);

      for (final json in jsonList) {
        final playlist = Playlist.fromJson(json);
        try {
          final songFile = await _getSongFile(playlist.id);
          if (await songFile.exists()) {
            final songContents = await songFile.readAsString();
            // 将 JSON 数组反序列化为 List<String>
            playlist.songFilePaths = (jsonDecode(songContents) as List<dynamic>)
                .map((e) => e.toString())
                .toList();
          } else {
            // 如果歌曲文件不存在，则将歌曲列表初始化为空
            playlist.songFilePaths = [];
          }
        } catch (e) {
          playlist.songFilePaths = [];
        }
        loadedPlaylists.add(playlist);
      }
      return loadedPlaylists;
    } catch (e) {
      // 如果主加载过程出现任何错误，则回退到默认歌单并重新保存以确保数据一致性
      final List<Playlist> defaultPlaylists = [
        Playlist(name: '默认歌单', isDefault: true),
      ];
      await savePlaylists(defaultPlaylists);
      return defaultPlaylists;
    }
  }

  Future<void> savePlaylists(List<Playlist> playlists) async {
    try {
      // 保存歌单元数据
      final metadataFile = await _getMetadataFile();
      final List<Map<String, dynamic>> metadataJsonList = playlists
          .map((playlist) => playlist.toJson()) // 调用 toJson 只包含 ID
          .toList();
      await metadataFile.writeAsString(jsonEncode(metadataJsonList));

      // 保存每个歌单的歌曲路径文件
      final existingSongFileIds = <String>{}; // 用于追踪当前存在的歌单ID
      for (final playlist in playlists) {
        final songFile = await _getSongFile(playlist.id);
        await songFile.writeAsString(
          jsonEncode(playlist.songFilePaths),
        ); // 将歌曲路径列表保存到文件
        existingSongFileIds.add(playlist.id);
      }

      // 清理已删除歌单的歌曲路径文件
      final path = await _getLocalPath();
      final songsDir = Directory('$path/$_songsSubdirectory');
      if (await songsDir.exists()) {
        await for (final entity in songsDir.list()) {
          // 遍历目录中的所有文件
          if (entity is File && entity.path.endsWith('.json')) {
            // 提取文件名为歌单 ID
            final id = entity.uri.pathSegments.last.replaceAll('.json', '');
            // 如果这个 ID 不在当前歌单列表中，则删除对应的歌曲文件
            if (!existingSongFileIds.contains(id)) {
              await entity.delete();
            }
          }
        }
      }
      // print('歌单已保存');
    } catch (e) {
      // print('保存歌单失败: $e');
    }
  }

  // 获取全部歌曲顺序文件的路径
  Future<File> _getAllSongsOrderFile() async {
    final path = await _getLocalPath();
    return File('$path/$_allSongsOrderFileName');
  }

  // 加载全部歌曲的顺序（一个文件路径列表）
  Future<List<String>> loadAllSongsOrder() async {
    try {
      final file = await _getAllSongsOrderFile();
      if (await file.exists()) {
        final contents = await file.readAsString();
        // 将 JSON 数组转换为 List<String>
        return (jsonDecode(contents) as List<dynamic>).cast<String>();
      }
    } catch (e) {
      // TODO something
    }
    return []; // 如果文件不存在或出错，返回空列表
  }

  // 新增：保存“全部歌曲”的顺序
  Future<void> saveAllSongsOrder(List<String> songFilePaths) async {
    try {
      final file = await _getAllSongsOrderFile();
      await file.writeAsString(jsonEncode(songFilePaths));
    } catch (e) {
      // TODO something
    }
  }
}
