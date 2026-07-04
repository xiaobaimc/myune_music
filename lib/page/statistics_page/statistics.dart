import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;
import 'package:silky_scroll/silky_scroll.dart';
import '../../theme/scroll_config.dart';

import '../playlist/playlist_content_notifier.dart';
import '../setting/settings_provider.dart';
import '../playlist/playlist_models.dart';
import 'statistics_manager.dart';

class Statistics extends StatefulWidget {
  const Statistics({super.key});

  @override
  State<Statistics> createState() => _StatisticsState();
}

class _StatisticsState extends State<Statistics> {
  late StatisticsManager _statsManager;
  bool _showAllSongs = false;
  bool _showAllArtists = false;
  bool _showAllAlbums = false;
  final Set<String> _trackedCoverPaths = <String>{};

  late final ScrollController scrollController;
  PlaylistContentNotifier? _playlistNotifier;

  @override
  void initState() {
    super.initState();
    _statsManager = StatisticsManager();
    scrollController = ScrollController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _playlistNotifier ??= context.read<PlaylistContentNotifier>();
  }

  @override
  void dispose() {
    final pathsToRelease = List<String>.from(_trackedCoverPaths);
    _trackedCoverPaths.clear();

    if (_playlistNotifier != null && pathsToRelease.isNotEmpty) {
      Future.microtask(() {
        for (final path in pathsToRelease) {
          _playlistNotifier!.releaseSongCover(path);
        }
      });
    }

    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playlistNotifier = context.watch<PlaylistContentNotifier>();
    final settingsProvider = context.watch<SettingsProvider>();
    final separators = settingsProvider.artistSeparators;
    final allSongs = playlistNotifier.allSongs;

    // 计算统计数据
    final totalDuration = allSongs.fold(
      Duration.zero,
      (prev, song) => prev + (song.duration ?? Duration.zero),
    );

    final uniqueArtists = <String>{};
    final uniqueAlbums = <String>{};

    for (final song in allSongs) {
      // 添加艺术家（使用设置中的分隔符）
      final artists = _splitArtists(song.artist, separators);
      uniqueArtists.addAll(
        artists.map((a) => a.trim()).where((a) => a.isNotEmpty),
      );

      // 添加专辑
      if (song.album.trim().isNotEmpty) {
        uniqueAlbums.add(song.album);
      }
    }

    final requiredCoverPaths = _collectRequiredCoverPaths(
      allSongs: allSongs,
      separators: separators,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncTrackedCovers(requiredCoverPaths);
    });

    return SilkyScroll(
      controller: scrollController,
      silkyScrollDuration: ScrollConfig.duration,
      scrollSpeed: ScrollConfig.speed,
      animationCurve: ScrollConfig.curve,
      builder: (context, controller, physics, _) => SingleChildScrollView(
        controller: controller,
        physics: physics,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('统计信息', style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (BuildContext context) {
                          return AlertDialog(
                            title: const Text('确认重置'),
                            content: const Text('此操作将清空所有播放记录，且无法撤销'),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(false),
                                child: const Text('取消'),
                              ),
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(true),
                                child: const Text('确定'),
                              ),
                            ],
                          );
                        },
                      );

                      if (confirm == true) {
                        await _statsManager.clearAllStats();
                        setState(() {
                          // 刷新UI
                        });
                      }
                    },
                    tooltip: '重置统计数据',
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // 基本统计信息
              LayoutBuilder(
                builder: (context, constraints) {
                  return Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      SizedBox(
                        width: (constraints.maxWidth - 32 - 16) / 2,
                        child: _buildStatCard(
                          icon: Icons.music_note,
                          label: '总歌曲数',
                          value: allSongs.length.toString(),
                        ),
                      ),
                      SizedBox(
                        width: (constraints.maxWidth - 32 - 16) / 2,
                        child: _buildStatCard(
                          icon: Icons.album,
                          label: '总专辑数',
                          value: uniqueAlbums.length.toString(),
                        ),
                      ),
                      SizedBox(
                        width: (constraints.maxWidth - 32 - 16) / 2,
                        child: _buildStatCard(
                          icon: Icons.person,
                          label: '总歌手数',
                          value: uniqueArtists.length.toString(),
                        ),
                      ),
                      SizedBox(
                        width: (constraints.maxWidth - 32 - 16) / 2,
                        child: _buildStatCard(
                          icon: Icons.access_time,
                          label: '总时长',
                          value:
                              '${(totalDuration.inHours).toString().padLeft(2, '0')}:${(totalDuration.inMinutes % 60).toString().padLeft(2, '0')}:${(totalDuration.inSeconds % 60).toString().padLeft(2, '0')}',
                        ),
                      ),
                    ],
                  );
                },
              ),

              const SizedBox(height: 24),

              // 歌曲播放排行榜
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('歌曲播放排行', style: Theme.of(context).textTheme.titleLarge),
                  if (_statsManager.getTopPlayedSongs(5).length >= 5)
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _showAllSongs = !_showAllSongs;
                        });
                      },
                      child: Text(_showAllSongs ? '收起' : '查看更多'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              _buildTopSongsList(playlistNotifier.allSongs),

              const SizedBox(height: 24),

              // 艺术家播放排行榜
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '艺术家播放排行',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (_statsManager.getTopArtists(5, separators).length >= 5)
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _showAllArtists = !_showAllArtists;
                        });
                      },
                      child: Text(_showAllArtists ? '收起' : '查看更多'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              _buildTopArtistsList(separators),

              const SizedBox(height: 24),

              // 专辑播放排行榜
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('专辑播放排行', style: Theme.of(context).textTheme.titleLarge),
                  if (_statsManager.getTopAlbums(5).length >= 5)
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _showAllAlbums = !_showAllAlbums;
                        });
                      },
                      child: Text(_showAllAlbums ? '收起' : '查看更多'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              _buildTopAlbumsList(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 24, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopSongsList(List<Song> allSongs) {
    final topSongs = _statsManager.getTopPlayedSongs(_showAllSongs ? 100 : 5);

    if (topSongs.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text('暂无播放记录', style: Theme.of(context).textTheme.bodyMedium),
        ),
      );
    }

    // 创建一个映射，使用文件名作为键来查找所有具有相同文件名的歌曲
    final songMap = <String, List<Song>>{};
    for (final song in allSongs) {
      final fileName = p.basename(song.filePath);
      if (!songMap.containsKey(fileName)) {
        songMap[fileName] = [];
      }
      songMap[fileName]!.add(song);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.0),
        child: ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: topSongs.length,
          separatorBuilder: (_, __) => const Divider(height: 2),
          itemBuilder: (context, index) {
            final song = topSongs[index];

            // 使用文件名进行匹配
            final statFileName = p.basename(song.path);
            final matchedSongs = songMap[statFileName];

            final songWithArt = _resolveSongForStat(
              matchedSongs: matchedSongs,
              fallback: Song(
                title: song.title,
                artist: song.artist,
                album: song.album,
                filePath: song.path,
              ),
            );

            return ListTile(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: songWithArt.albumArt != null
                    ? Image.memory(
                        cacheWidth: 100,
                        songWithArt.albumArt!,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                      )
                    : const SizedBox(
                        width: 40,
                        height: 40,
                        child: Icon(Icons.music_note, size: 20),
                      ),
              ),
              title: Text(song.title),
              subtitle: Text(
                context.watch<SettingsProvider>().showAlbumName
                    ? '${song.artist} - ${song.album}'
                    : song.artist,
              ),
              trailing: Text('${song.playCount} 次'),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTopArtistsList(List<String> separators) {
    final topArtists = _statsManager.getTopArtists(
      _showAllArtists ? 100 : 5,
      separators,
    );

    if (topArtists.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text('暂无播放记录', style: Theme.of(context).textTheme.bodyMedium),
        ),
      );
    }

    // 获取所有歌曲，用于查找艺术家的专辑封面
    final playlistNotifier = context.watch<PlaylistContentNotifier>();
    final allSongs = playlistNotifier.allSongs;

    // 为每个艺术家找到一个代表性的专辑封面
    final artistCoverMap = <String, Song>{};
    for (final artistEntry in topArtists) {
      final artistName = artistEntry.key;
      if (!artistCoverMap.containsKey(artistName)) {
        Song? fallbackSong;
        for (final song in allSongs) {
          final containsArtist = _splitArtists(
            song.artist,
            separators,
          ).map((a) => a.trim()).contains(artistName);
          if (!containsArtist) {
            continue;
          }
          fallbackSong ??= song;
          if (song.albumArt != null) {
            artistCoverMap[artistName] = song;
            break;
          }
        }
        if (!artistCoverMap.containsKey(artistName) && fallbackSong != null) {
          artistCoverMap[artistName] = fallbackSong;
        }
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: topArtists.length,
          separatorBuilder: (_, __) => const Divider(),
          itemBuilder: (context, index) {
            final artist = topArtists[index];
            final coverSong = artistCoverMap[artist.key];
            final cover = coverSong?.albumArt;
            return ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                ),
                child: cover != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(100),
                        child: Image.memory(
                          cacheWidth: 100,
                          cover,
                          width: 40,
                          height: 40,
                          fit: BoxFit.cover,
                        ),
                      )
                    : const Icon(Icons.person, size: 20),
              ),
              title: Text(artist.key),
              trailing: Text('${artist.value} 次'),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTopAlbumsList() {
    final topAlbums = _statsManager.getTopAlbums(_showAllAlbums ? 100 : 5);

    if (topAlbums.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text('暂无播放记录', style: Theme.of(context).textTheme.bodyMedium),
        ),
      );
    }

    // 获取所有歌曲，用于查找专辑的封面
    final playlistNotifier = context.watch<PlaylistContentNotifier>();
    final allSongs = playlistNotifier.allSongs;

    // 为每个专辑找到一个代表性的专辑封面
    final albumCoverMap = <String, Song>{};
    for (final albumEntry in topAlbums) {
      final albumName = albumEntry.key;
      if (!albumCoverMap.containsKey(albumName)) {
        Song? fallbackSong;
        for (final song in allSongs) {
          if (song.album != albumName) {
            continue;
          }
          fallbackSong ??= song;
          if (song.albumArt != null) {
            albumCoverMap[albumName] = song;
            break;
          }
        }
        if (!albumCoverMap.containsKey(albumName) && fallbackSong != null) {
          albumCoverMap[albumName] = fallbackSong;
        }
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: topAlbums.length,
          separatorBuilder: (_, __) => const Divider(),
          itemBuilder: (context, index) {
            final album = topAlbums[index];
            final coverSong = albumCoverMap[album.key];
            final cover = coverSong?.albumArt;
            return ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                ),
                child: cover != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.memory(
                          cacheWidth: 100,
                          cover,
                          width: 40,
                          height: 40,
                          fit: BoxFit.cover,
                        ),
                      )
                    : const Icon(Icons.album, size: 20),
              ),
              title: Text(album.key),
              trailing: Text('${album.value} 次'),
            );
          },
        ),
      ),
    );
  }

  List<String> _splitArtists(String artistString, List<String> separators) {
    var result = [artistString];
    for (final separator in separators) {
      final newResult = <String>[];
      for (final str in result) {
        newResult.addAll(str.split(separator));
      }
      result = newResult;
    }

    return result;
  }

  Song _resolveSongForStat({
    required List<Song>? matchedSongs,
    required Song fallback,
  }) {
    if (matchedSongs == null || matchedSongs.isEmpty) {
      return fallback;
    }
    return matchedSongs.firstWhere(
      (s) => s.albumArt != null,
      orElse: () => matchedSongs.first,
    );
  }

  Set<String> _collectRequiredCoverPaths({
    required List<Song> allSongs,
    required List<String> separators,
  }) {
    final required = <String>{};

    final topSongs = _statsManager.getTopPlayedSongs(_showAllSongs ? 100 : 5);
    final songMap = <String, List<Song>>{};
    for (final song in allSongs) {
      final fileName = p.basename(song.filePath);
      (songMap[fileName] ??= <Song>[]).add(song);
    }
    for (final statSong in topSongs) {
      final matched = songMap[p.basename(statSong.path)];
      final resolved = _resolveSongForStat(
        matchedSongs: matched,
        fallback: Song(
          title: statSong.title,
          artist: statSong.artist,
          album: statSong.album,
          filePath: statSong.path,
        ),
      );
      required.add(resolved.filePath);
    }

    final topArtists = _statsManager.getTopArtists(
      _showAllArtists ? 100 : 5,
      separators,
    );
    for (final entry in topArtists) {
      final artistName = entry.key;
      Song? fallbackSong;
      for (final song in allSongs) {
        final containsArtist = _splitArtists(
          song.artist,
          separators,
        ).map((a) => a.trim()).contains(artistName);
        if (!containsArtist) continue;
        fallbackSong ??= song;
        if (song.albumArt != null) {
          required.add(song.filePath);
          break;
        }
      }
      if (fallbackSong != null) {
        required.add(fallbackSong.filePath);
      }
    }

    final topAlbums = _statsManager.getTopAlbums(_showAllAlbums ? 100 : 5);
    for (final entry in topAlbums) {
      final albumName = entry.key;
      Song? fallbackSong;
      for (final song in allSongs) {
        if (song.album != albumName) continue;
        fallbackSong ??= song;
        if (song.albumArt != null) {
          required.add(song.filePath);
          break;
        }
      }
      if (fallbackSong != null) {
        required.add(fallbackSong.filePath);
      }
    }

    return required;
  }

  void _syncTrackedCovers(Set<String> requiredPaths) {
    final notifier = context.read<PlaylistContentNotifier>();
    final toAdd = requiredPaths.difference(_trackedCoverPaths);
    final toRemove = _trackedCoverPaths.difference(requiredPaths);

    for (final path in toAdd) {
      notifier.requestSongCover(path);
    }
    for (final path in toRemove) {
      notifier.releaseSongCover(path);
    }

    _trackedCoverPaths
      ..clear()
      ..addAll(requiredPaths);
  }
}
