import 'package:flutter/material.dart';
import 'package:pinyin/pinyin.dart';
import 'package:provider/provider.dart';
import 'package:flutter_web_scroll/flutter_web_scroll.dart';
import '../playlist/playlist_content_notifier.dart';
import 'song_list_detail_page.dart';

class ArtistList extends StatefulWidget {
  const ArtistList({super.key});

  @override
  State<ArtistList> createState() => _ArtistListState();
}

class _ArtistListState extends State<ArtistList> {
  late final ScrollController _scrollController = ScrollController();
  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  bool _isSearching = false;
  String _searchKeyword = '';
  bool _hideSingleSongArtists = false;

  void sortArtists(List<String> artistNames) {
    final Map<String, String> cache = {};

    String getPy(String s) {
      if (cache.containsKey(s)) return cache[s]!;
      final py = PinyinHelper.getPinyin(s, separator: '').toLowerCase().trim();
      final result = py.isEmpty ? s.toLowerCase() : py;
      cache[s] = result;
      return result;
    }

    artistNames.sort((a, b) {
      final pa = getPy(a);
      final pb = getPy(b);
      return pa.compareTo(pb);
    });
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<PlaylistContentNotifier>();

    // 在构建界面时请求所有艺术家歌曲的封面
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final allArtists = notifier.songsByArtist;
      for (final songs in allArtists.values) {
        for (final song in songs) {
          notifier.requestSongCover(song.filePath);
        }
      }
    });

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: _isSearching
                // --- 搜索状态 ---
                ? TextField(
                    key: const ValueKey('artist_search_field'),
                    autofocus: true,
                    onChanged: (value) =>
                        setState(() => _searchKeyword = value),
                    decoration: InputDecoration(
                      hintText: '搜索歌手名称...',
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
                    key: const ValueKey('artist_title_bar'),
                    children: [
                      const Text('歌手', style: TextStyle(fontSize: 22)),
                      const SizedBox(width: 16),
                      Text(
                        '共 ${notifier.songsByArtist.keys.length} 位',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Icon(
                          _hideSingleSongArtists
                              ? Icons.filter_alt_off_outlined
                              : Icons.filter_alt_outlined,
                          color: _hideSingleSongArtists
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                        tooltip: _hideSingleSongArtists
                            ? '显示所有歌手'
                            : '隐藏只有单首歌曲的歌手',
                        onPressed: () => setState(() {
                          _hideSingleSongArtists = !_hideSingleSongArtists;
                        }),
                      ),
                      IconButton(
                        icon: const Icon(Icons.search),
                        tooltip: '搜索歌手',
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
                  final artists = notifier.songsByArtist;
                  var artistNames = artists.keys.toList();

                  // 应用搜索过滤逻辑
                  if (_searchKeyword.isNotEmpty) {
                    artistNames = artistNames.where((name) {
                      return name.toLowerCase().contains(
                        _searchKeyword.toLowerCase(),
                      );
                    }).toList();
                  }

                  // 应用单曲歌手过滤逻辑
                  if (_hideSingleSongArtists) {
                    artistNames = artistNames.where((name) {
                      return artists[name]!.length > 1;
                    }).toList();
                  }

                  // 拼音排序
                  sortArtists(artistNames);

                  if (artistNames.isEmpty) {
                    return Center(
                      child: Text(_isSearching ? '未找到匹配的歌手' : '未找到歌手'),
                    );
                  }

                  return SmoothScrollWeb(
                    controller: _scrollController,
                    config: SmoothScrollConfig.lenis(),
                    child: ListView.builder(
                      controller: _scrollController,
                      itemCount: artistNames.length,
                      itemBuilder: (context, index) {
                        final artistName = artistNames[index];
                        final songs = artists[artistName]!;
                        final representativeArt = songs
                            .firstWhere(
                              (s) => s.albumArt != null,
                              orElse: () => songs.first,
                            )
                            .albumArt;

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage: representativeArt != null
                                ? MemoryImage(representativeArt)
                                : null,
                            child: representativeArt == null
                                ? const Icon(Icons.person)
                                : null,
                          ),
                          title: Text(artistName),
                          subtitle: Text('共 ${songs.length} 首歌曲'),
                          onTap: () {
                            notifier.setActiveArtistView(artistName);
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const SongListDetailPage(),
                              ),
                            );
                          },
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12.0),
                          ),
                        );
                      },
                    ),
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
