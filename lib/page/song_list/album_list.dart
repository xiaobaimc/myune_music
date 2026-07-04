import 'package:flutter/material.dart';
import '../../layout/navigation_notifier.dart';
import 'package:provider/provider.dart';
import 'dart:typed_data';
import 'package:silky_scroll/silky_scroll.dart';
import '../../theme/scroll_config.dart';
import '../playlist/playlist_content_notifier.dart';
import '../../widgets/single_line_lyrics.dart';
import 'album_detail_view.dart';
import 'package:pinyin/pinyin.dart';

class AlbumList extends StatefulWidget {
  const AlbumList({super.key});

  @override
  State<AlbumList> createState() => _AlbumListState();
}

class _AlbumListState extends State<AlbumList> {
  late final ScrollController _scrollController = ScrollController();
  double _savedScrollOffset = 0.0;
  bool _prevShowAlbumDetail = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  bool _isSearching = false;
  String _searchKeyword = '';
  bool _hideSingleSongAlbums = false;

  void _closeAlbumDetail() {
    final notifier = context.read<PlaylistContentNotifier>();
    final navNotifier = context.read<NavigationNotifier>();
    
    if (notifier.isSearching) {
      notifier.stopSearch();
    }
    notifier.clearActiveDetailView();
    
    if (navNotifier.canPop) {
      navNotifier.popRoute();
    }
  }

  void sortAlbums(List<String> albumNames) {
    final Map<String, String> cache = {};

    String getPy(String s) {
      if (cache.containsKey(s)) return cache[s]!;
      final py = PinyinHelper.getPinyin(s, separator: '').toLowerCase().trim();
      final result = py.isEmpty ? s.toLowerCase() : py;
      cache[s] = result;
      return result;
    }

    albumNames.sort((a, b) {
      final pa = getPy(a);
      final pb = getPy(b);
      return pa.compareTo(pb);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final notifier = context.read<PlaylistContentNotifier>();
    final showAlbumDetail =
        notifier.currentDetailViewContext == DetailViewContext.album;

    if (!showAlbumDetail && _prevShowAlbumDetail && _savedScrollOffset > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_savedScrollOffset);
          _savedScrollOffset = 0.0;
        }
      });
    }
    _prevShowAlbumDetail = showAlbumDetail;
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<PlaylistContentNotifier>();
    final showAlbumDetail =
        notifier.currentDetailViewContext == DetailViewContext.album;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final offsetAnimation = Tween<Offset>(
          begin: const Offset(0.03, 0),
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: offsetAnimation, child: child),
        );
      },
      child: showAlbumDetail
          ? AlbumDetailView(
              key: const ValueKey('album_detail'),
              onBack: _closeAlbumDetail,
            )
          : Column(
              key: const ValueKey('album_grid'),
              children: [
                AppBar(
                  title: const SingleLineLyricView(
                    maxLinesPerLyric: 2,
                    textAlign: TextAlign.left,
                    alignment: Alignment.topLeft,
                  ),
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  surfaceTintColor: Colors.transparent,
                ),
                const Divider(height: 1, thickness: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 6.0,
                  ),
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
                                  _hideSingleSongAlbums =
                                      !_hideSingleSongAlbums;
                                }),
                              ),
                              IconButton(
                                icon: const Icon(Icons.search),
                                tooltip: '搜索专辑',
                                onPressed: () =>
                                    setState(() => _isSearching = true),
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

                          // 拼音排序
                          sortAlbums(albumNames);

                          if (albumNames.isEmpty) {
                            return Center(
                              child: Text(
                                _isSearching ? '未找到匹配的专辑' : '没有找到任何专辑',
                              ),
                            );
                          }

                          return SilkyScroll(
                            controller: _scrollController,
                            silkyScrollDuration: ScrollConfig.duration,
                            scrollSpeed: ScrollConfig.speed,
                            animationCurve: ScrollConfig.curve,
                            builder: (context, controller, physics, _) => GridView.builder(
                              controller: controller,
                              physics: physics,
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
                                final representativeSong = songs.firstWhere(
                                  (s) => s.albumArt != null,
                                  orElse: () => songs.first,
                                );
                                final albumArt = representativeSong.albumArt;

                                return InkWell(
                                  onTap: () {
                                    if (_scrollController.hasClients) {
                                      _savedScrollOffset =
                                          _scrollController.offset;
                                    }
                                    notifier.setActiveAlbumView(albumName);
                                  },
                                  borderRadius: BorderRadius.circular(12.0),
                                  child: Card(
                                    clipBehavior: Clip.antiAlias,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: _AlbumCoverTile(
                                            filePath:
                                                representativeSong.filePath,
                                            albumArt: albumArt,
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
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodySmall,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                      ],
                                    ),
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
            ),
    );
  }
}

class _AlbumCoverTile extends StatefulWidget {
  final String filePath;
  final Uint8List? albumArt;

  const _AlbumCoverTile({required this.filePath, required this.albumArt});

  @override
  State<_AlbumCoverTile> createState() => _AlbumCoverTileState();
}

class _AlbumCoverTileState extends State<_AlbumCoverTile> {
  String? _requestedCoverPath;
  late PlaylistContentNotifier _notifier;

  @override
  void initState() {
    super.initState();
    _notifier = context.read<PlaylistContentNotifier>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _requestCover(widget.filePath);
    });
  }

  @override
  void didUpdateWidget(covariant _AlbumCoverTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath) {
      final oldPath = oldWidget.filePath;
      final newPath = widget.filePath;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _releaseCover(oldPath);
        _requestCover(newPath);
      });
    }
  }

  @override
  void dispose() {
    if (_requestedCoverPath != null) {
      _releaseCover(_requestedCoverPath!);
    }
    super.dispose();
  }

  void _requestCover(String filePath) {
    _requestedCoverPath = filePath;
    _notifier.requestSongCover(filePath);
  }

  void _releaseCover(String filePath) {
    if (_requestedCoverPath == null) return;
    _notifier.releaseSongCover(filePath);
    _requestedCoverPath = null;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.secondaryContainer,
      // isNotEmpty: 过滤空字节数组；errorBuilder: 兜底解码失败
      child: widget.albumArt != null && widget.albumArt!.isNotEmpty
          ? Image.memory(
              cacheWidth: 200,
              widget.albumArt!,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (context, error, stackTrace) {
                return const Icon(Icons.album, size: 50);
              },
            )
          : const Icon(Icons.album, size: 50),
    );
  }
}
