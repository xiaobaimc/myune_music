import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../playlist/playlist_content_notifier.dart';
import 'song_list_detail_page.dart';

class AlbumList extends StatefulWidget {
  const AlbumList({super.key});

  @override
  State<AlbumList> createState() => _AlbumListState();
}

class _AlbumListState extends State<AlbumList> {
  bool _isSearching = false;
  String _searchKeyword = '';
  bool _hideSingleSongAlbums = false;

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<PlaylistContentNotifier>();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: _isSearching
                // --- 搜索状态 ---
                ? TextField(
                    key: const ValueKey('album_search_field'),
                    autofocus: true,
                    onChanged: (value) =>
                        setState(() => _searchKeyword = value),
                    decoration: InputDecoration(
                      hintText: '搜索专辑名称...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() {
                          _isSearching = false;
                          _searchKeyword = '';
                        }),
                      ),
                    ),
                  )
                // --- 常规状态 ---
                : Row(
                    key: const ValueKey('album_title_bar'),
                    children: [
                      const Text('专辑', style: TextStyle(fontSize: 22)),
                      const SizedBox(width: 16),
                      Text(
                        '共 ${notifier.songsByAlbum.keys.length} 张',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Icon(
                          _hideSingleSongAlbums
                              ? Icons.filter_alt_off_outlined
                              : Icons.filter_alt_outlined,
                          color: _hideSingleSongAlbums
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                        tooltip: _hideSingleSongAlbums
                            ? '显示所有专辑'
                            : '隐藏只有单首歌曲的专辑',
                        onPressed: () => setState(() {
                          _hideSingleSongAlbums = !_hideSingleSongAlbums;
                        }),
                      ),
                      IconButton(
                        icon: const Icon(Icons.search),
                        tooltip: '搜索专辑',
                        onPressed: () => setState(() => _isSearching = true),
                      ),
                    ],
                  ),
          ),
        ),

        // 列表部分
        Expanded(
          child: Material(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Builder(
                builder: (context) {
                  final albums = notifier.songsByAlbum;
                  var albumNames = albums.keys.toList();

                  // 应用搜索过滤逻辑
                  if (_searchKeyword.isNotEmpty) {
                    albumNames = albumNames.where((name) {
                      return name.toLowerCase().contains(
                        _searchKeyword.toLowerCase(),
                      );
                    }).toList();
                  }

                  // 应用单曲专辑过滤逻辑
                  if (_hideSingleSongAlbums) {
                    albumNames = albumNames.where((name) {
                      return albums[name]!.length > 1;
                    }).toList();
                  }

                  // 简化为固定的字母排序
                  albumNames.sort(
                    (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
                  );

                  if (albumNames.isEmpty) {
                    return Center(
                      child: Text(_isSearching ? '未找到匹配的专辑' : '没有找到任何专辑'),
                    );
                  }

                  return GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 200,
                          childAspectRatio: 0.8,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                        ),
                    itemCount: albumNames.length,
                    itemBuilder: (context, index) {
                      final albumName = albumNames[index];
                      final songs = albums[albumName]!;
                      final albumArt = songs.first.albumArt;

                      return InkWell(
                        onTap: () {
                          notifier.setActiveAlbumView(albumName);
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const SongListDetailPage(),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(12.0),
                        child: Card(
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Container(
                                  width: double.infinity,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.secondaryContainer,
                                  child: albumArt != null
                                      ? Image.memory(
                                          albumArt,
                                          fit: BoxFit.cover,
                                          gaplessPlayback: true,
                                        )
                                      : const Icon(Icons.album, size: 50),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Text(
                                  albumName,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8.0,
                                ),
                                child: Text(
                                  '共 ${songs.length} 首歌曲',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}
