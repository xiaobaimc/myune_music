import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../playlist/playlist_content_notifier.dart';
import 'song_list_detail_page.dart';

class ArtistList extends StatefulWidget {
  const ArtistList({super.key});

  @override
  State<ArtistList> createState() => _ArtistListState();
}

class _ArtistListState extends State<ArtistList> {
  bool _isSearching = false;
  String _searchKeyword = '';

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<PlaylistContentNotifier>();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
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
                      const Text(
                        '歌手',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        '共 ${notifier.songsByArtist.keys.length} 位',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const Spacer(),
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
              // 简化为固定的字母排序
              artistNames.sort(
                (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
              );

              if (artistNames.isEmpty) {
                return Center(child: Text(_isSearching ? '未找到匹配的歌手' : '未找到歌手'));
              }

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
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
                    subtitle: Text('${songs.length} 首歌曲'),
                    onTap: () {
                      notifier.setActiveArtistView(artistName);
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const SongListDetailPage(),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
