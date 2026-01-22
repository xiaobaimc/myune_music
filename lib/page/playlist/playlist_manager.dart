import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'playlist_models.dart';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PlaylistManager {
  static const String _playlistMetadataFileName = 'playlists_metadata.json';
  static const String _songsSubdirectory = 'playlist_songs';
  static const String _allSongsOrderFileName = 'all_songs_order.json';
  static const String _artistSortOrderFileName = 'artist_sort_order.json';
  static const String _albumSortOrderFileName = 'album_sort_order.json';
  static const String _songMetadataCacheFileName = 'song_metadata_cache.json';
  static const String _migrationFlagKey = 'data_migrated_to_app_support';

  Future<String> _getLocalPath() async {
    // 文档目录
    final appDocDir = await getApplicationDocumentsDirectory();
    final appDir = Directory(
      p.join(appDocDir.path, 'myune_music', 'list_data'),
    );

    // 检查是否需要迁移旧数据
    await _migrateOldDataIfNeeded(appDir.path);

    // 确保目录存在
    if (!await appDir.exists()) {
      await appDir.create(recursive: true);
    }

    return appDir.path;
  }

  // 检查并迁移旧数据
  Future<void> _migrateOldDataIfNeeded(String newPath) async {
    final prefs = await SharedPreferences.getInstance();
    final isMigrated = prefs.getBool(_migrationFlagKey) ?? false;

    // 如果已经迁移过，则直接返回
    if (isMigrated) {
      return;
    }

    // 检查旧目录是否存在
    final oldDir = Directory('list_data');
    final newDir = Directory(newPath);

    // 如果旧目录不存在，则无需迁移
    if (!await oldDir.exists()) {
      // 标记为已迁移并返回
      await prefs.setBool(_migrationFlagKey, true);
      return;
    }

    // 检查新目录是否已存在且包含文件
    bool newDirHasFiles = false;
    if (await newDir.exists()) {
      final entities = await newDir.list().toList();
      newDirHasFiles = entities.isNotEmpty;
    }

    // 只有当新目录为空或不存在且旧目录存在时才进行迁移
    if (!newDirHasFiles) {
      // 确保新目录存在
      if (!await newDir.exists()) {
        await newDir.create(recursive: true);
      }
      await _performMigration(oldDir, newDir);
    }

    // 标记为已迁移
    await prefs.setBool(_migrationFlagKey, true);
  }

  // 执行实际的数据迁移操作
  Future<void> _performMigration(Directory oldDir, Directory newDir) async {
    // 迁移元数据文件
    final oldMetadataFile = File(
      p.join(oldDir.path, _playlistMetadataFileName),
    );
    if (await oldMetadataFile.exists()) {
      final newMetadataFile = File(
        p.join(newDir.path, _playlistMetadataFileName),
      );
      await oldMetadataFile.copy(newMetadataFile.path);
    }

    // 迁移所有歌曲排序文件
    final oldAllSongsOrderFile = File(
      p.join(oldDir.path, _allSongsOrderFileName),
    );
    if (await oldAllSongsOrderFile.exists()) {
      final newAllSongsOrderFile = File(
        p.join(newDir.path, _allSongsOrderFileName),
      );
      await oldAllSongsOrderFile.copy(newAllSongsOrderFile.path);
    }

    // 迁移艺术家排序文件
    final oldArtistSortOrderFile = File(
      p.join(oldDir.path, _artistSortOrderFileName),
    );
    if (await oldArtistSortOrderFile.exists()) {
      final newArtistSortOrderFile = File(
        p.join(newDir.path, _artistSortOrderFileName),
      );
      await oldArtistSortOrderFile.copy(newArtistSortOrderFile.path);
    }

    // 迁移专辑排序文件
    final oldAlbumSortOrderFile = File(
      p.join(oldDir.path, _albumSortOrderFileName),
    );
    if (await oldAlbumSortOrderFile.exists()) {
      final newAlbumSortOrderFile = File(
        p.join(newDir.path, _albumSortOrderFileName),
      );
      await oldAlbumSortOrderFile.copy(newAlbumSortOrderFile.path);
    }

    // 迁移歌单歌曲目录及其中的所有文件
    final oldSongsDir = Directory(p.join(oldDir.path, _songsSubdirectory));
    if (await oldSongsDir.exists()) {
      final newSongsDir = Directory(p.join(newDir.path, _songsSubdirectory));
      if (!await newSongsDir.exists()) {
        await newSongsDir.create(recursive: true);
      }

      // 复制所有歌单文件
      await for (final entity in oldSongsDir.list()) {
        if (entity is File) {
          final fileName = p.basename(entity.path);
          final newFile = File(p.join(newSongsDir.path, fileName));
          await entity.copy(newFile.path);
        }
      }
    }
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

  Future<File> getSongMetadataCacheFile() async {
    final path = await _getLocalPath();
    return File('$path/$_songMetadataCacheFileName');
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
      //
    }
    return []; // 如果文件不存在或出错，返回空列表
  }

  // 保存“全部歌曲”的顺序
  Future<void> saveAllSongsOrder(List<String> songFilePaths) async {
    try {
      final file = await _getAllSongsOrderFile();
      await file.writeAsString(jsonEncode(songFilePaths));
    } catch (e) {
      //
    }
  }

  Future<File> _getArtistSortOrderFile() async {
    final path = await _getLocalPath();
    return File(p.join(path, _artistSortOrderFileName));
  }

  // 获取专辑排序文件的路径
  Future<File> _getAlbumSortOrderFile() async {
    final path = await _getLocalPath();
    return File(p.join(path, _albumSortOrderFileName));
  }

  // 加载歌手的排序配置
  Future<Map<String, List<String>>> loadArtistSortOrders() async {
    try {
      final file = await _getArtistSortOrderFile();
      if (await file.exists()) {
        final contents = await file.readAsString();
        final json = jsonDecode(contents) as Map<String, dynamic>;
        return json.map(
          (key, value) => MapEntry(key, List<String>.from(value)),
        );
      }
    } catch (e) {
      // print('加载歌手排序失败: $e');
    }
    return {};
  }

  // 保存歌手的排序配置
  Future<void> saveArtistSortOrders(Map<String, List<String>> orders) async {
    try {
      final file = await _getArtistSortOrderFile();
      await file.writeAsString(jsonEncode(orders));
    } catch (e) {
      // print('保存歌手排序失败: $e');
    }
  }

  // 加载专辑的排序配置
  Future<Map<String, List<String>>> loadAlbumSortOrders() async {
    try {
      final file = await _getAlbumSortOrderFile();
      if (await file.exists()) {
        final contents = await file.readAsString();
        final json = jsonDecode(contents) as Map<String, dynamic>;
        return json.map(
          (key, value) => MapEntry(key, List<String>.from(value)),
        );
      }
    } catch (e) {
      // print('加载专辑排序失败: $e');
    }
    return {};
  }

  // 保存专辑的排序配置
  Future<void> saveAlbumSortOrders(Map<String, List<String>> orders) async {
    try {
      final file = await _getAlbumSortOrderFile();
      await file.writeAsString(jsonEncode(orders));
    } catch (e) {
      // print('保存专辑排序失败: $e');
    }
  }

  // 获取播放状态文件路径
  Future<File> _getPlaybackStateFile() async {
    final path = await _getLocalPath();
    return File('$path/playback_state.json');
  }

  // 获取播放队列文件路径
  Future<File> _getPlaybackQueueFile() async {
    final path = await _getLocalPath();
    return File('$path/playback_queue.json');
  }

  // 保存播放状态
  Future<void> savePlaybackState(PlaybackState state) async {
    try {
      final file = await _getPlaybackStateFile();
      await file.writeAsString(jsonEncode(state.toJson()));
    } catch (e) {
      //
    }
  }

  // 加载播放状态
  Future<PlaybackState?> loadPlaybackState() async {
    try {
      final file = await _getPlaybackStateFile();
      if (await file.exists()) {
        final contents = await file.readAsString();
        final json = jsonDecode(contents) as Map<String, dynamic>;
        return PlaybackState.fromJson(json);
      }
    } catch (e) {
      //
    }
    return null;
  }

  // 清除播放状态
  Future<void> clearPlaybackState() async {
    try {
      final file = await _getPlaybackStateFile();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      //
    }
  }

  // 保存播放队列
  Future<void> savePlaybackQueue(List<String> queue) async {
    try {
      final file = await _getPlaybackQueueFile();
      await file.writeAsString(jsonEncode(queue));
    } catch (e) {
      //
    }
  }

  // 加载播放队列
  Future<List<String>?> loadPlaybackQueue() async {
    try {
      final file = await _getPlaybackQueueFile();
      if (await file.exists()) {
        final contents = await file.readAsString();
        return (jsonDecode(contents) as List<dynamic>).cast<String>();
      }
    } catch (e) {
      //
    }
    return null;
  }

  // 清除播放队列
  Future<void> clearPlaybackQueue() async {
    try {
      final file = await _getPlaybackQueueFile();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      //
    }
  }
}
