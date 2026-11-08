import 'package:flutter/material.dart';
import '../../layout/navigation_notifier.dart';
import '../../services/pinyin_cache.dart';
import '../playlist/playlist_models.dart';
import 'package:provider/provider.dart';
import 'package:silky_scroll/silky_scroll.dart';
import '../../theme/scroll_config.dart';
import '../playlist/playlist_content_notifier.dart';
import '../playlist/playlist_content_widget.dart';
import '../../widgets/single_line_lyrics.dart';
import '../../widgets/song_cover.dart';
import 'genre_detail_view.dart';
import '../setting/settings_provider.dart';
import '../../widgets/custom_background_layer.dart';

class GenreList extends StatefulWidget {
  const GenreList({super.key});

  @override
  State<GenreList> createState() => _GenreListState();
}

class _GenreListState extends State<GenreList> {
  late final ScrollController _scrollController = ScrollController();
  double _savedScrollOffset = 0.0;
  bool _prevShowGenreDetail = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  bool _isSearching = false;
  String _searchKeyword = '';

  List<String>? _cachedSortedGenres;
  Map<String, List<Song>>? _lastGenreData;
  List<Song>? _lastScanRequestSongs;

  void _closeGenreDetail() {
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

  List<String> _getSortedGenres(Map<String, List<Song>> genres) {
    if (!identical(genres, _lastGenreData)) {
      _lastGenreData = genres;
      final names = genres.keys.toList();
      final cache = PinyinCache.instance;
      names.sort(
        (a, b) => cache.getFullPinyin(a).compareTo(cache.getFullPinyin(b)),
      );
      _cachedSortedGenres = names;
    }
    return _cachedSortedGenres!;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final notifier = context.read<PlaylistContentNotifier>();
    final showGenreDetail =
        notifier.currentDetailViewContext == DetailViewContext.genre;

    if (!showGenreDetail && _prevShowGenreDetail && _savedScrollOffset > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_savedScrollOffset);
          _savedScrollOffset = 0.0;
        }
      });
    }
    _prevShowGenreDetail = showGenreDetail;
  }

  void _requestGenreScan(PlaylistContentNotifier notifier) {
    if (!notifier.allSongsLoaded || notifier.isScanningGenres) {
      return;
    }
    // 歌曲库列表对象变化时才重新请求补读，避免每次重建都全量检查缓存
    final songs = notifier.allSongs;
    if (identical(songs, _lastScanRequestSongs)) {
      return;
    }
    _lastScanRequestSongs = songs;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<PlaylistContentNotifier>().ensureGenreTagsLoaded();
    });
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<PlaylistContentNotifier>();
    final settings = context.watch<SettingsProvider>();
    final showGenreDetail =
        notifier.currentDetailViewContext == DetailViewContext.genre;

    _requestGenreScan(notifier);

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
      child: showGenreDetail
          ? GenreDetailView(
              key: const ValueKey('genre_detail'),
              onBack: _closeGenreDetail,
            )
          : Column(
              key: const ValueKey('genre_list'),
              children: [
                AppBar(
                  title: const SingleLineLyricView(
                    maxLinesPerLyric: 2,
                    textAlign: TextAlign.left,
                    alignment: Alignment.topLeft,
                  ),
                  backgroundColor:
                      CustomBackgroundSurfaces.transparentWhenEnabled(
                        settings,
                        Theme.of(context).colorScheme.surface,
                      ),
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
                            key: const ValueKey('genre_search_field'),
                            autofocus: true,
                            onChanged: (value) =>
                                setState(() => _searchKeyword = value),
                            decoration: InputDecoration(
                              hintText: '搜索流派名称...',
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
                            key: const ValueKey('genre_title_bar'),
                            children: [
                              const Text('流派', style: TextStyle(fontSize: 22)),
                              const SizedBox(width: 16),
                              Text(
                                '共 ${notifier.songsByGenre.keys.length} 种',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              const Spacer(),
                              IconButton(
                                icon: const Icon(Icons.search),
                                tooltip: '搜索流派',
                                onPressed: () =>
                                    setState(() => _isSearching = true),
                              ),
                            ],
                          ),
                  ),
                ),
                if (notifier.isScanningGenres)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            notifier.genreScanTotal > 0
                                ? '正在读取流派标签 ${notifier.genreScanDone}/${notifier.genreScanTotal}'
                                : '正在读取流派标签...',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        SizedBox(
                          width: 160,
                          child: LinearProgressIndicator(
                            value: notifier.genreScanTotal > 0
                                ? notifier.genreScanDone /
                                      notifier.genreScanTotal
                                : null,
                            minHeight: 4,
                          ),
                        ),
                      ],
                    ),
                  ),
                // 列表部分
                Expanded(
                  child: Material(
                    color: CustomBackgroundSurfaces.materialColor(settings),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      child: Builder(
                        builder: (context) {
                          if (!notifier.allSongsLoaded) {
                            return const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(),
                                  SizedBox(height: 12),
                                  Text('正在加载歌曲库...'),
                                ],
                              ),
                            );
                          }

                          final genres = notifier.songsByGenre;
                          // 使用缓存的排序结果
                          var genreNames = _getSortedGenres(genres).toList();

                          // 应用搜索过滤逻辑（支持拼音搜索）
                          if (_searchKeyword.isNotEmpty) {
                            final lowerKeyword = _searchKeyword.toLowerCase();
                            final isLatin = RegExp(
                              r'^[a-z0-9]+$',
                            ).hasMatch(lowerKeyword);
                            genreNames = genreNames.where((name) {
                              // 直接字符串匹配
                              if (name.toLowerCase().contains(lowerKeyword)) {
                                return true;
                              }
                              // 拼音匹配（仅拉丁字符输入时）
                              if (isLatin) {
                                final pinyin = PinyinCache.instance
                                    .getFullPinyin(name);
                                if (pinyin.contains(lowerKeyword)) return true;
                                final initials = PinyinCache.instance
                                    .getInitials(name);
                                if (initials.contains(lowerKeyword)) {
                                  return true;
                                }
                              }
                              return false;
                            }).toList();
                          }

                          if (genreNames.isEmpty) {
                            return Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.category_outlined,
                                    size: 52,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    _isSearching
                                        ? '未找到匹配的流派'
                                        : notifier.isScanningGenres
                                        ? '正在读取流派标签...'
                                        : '未找到流派标签',
                                  ),
                                  if (!_isSearching &&
                                      !notifier.isScanningGenres) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      '歌曲没有流派标签时不会显示在这里',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ],
                                ],
                              ),
                            );
                          }

                          return SilkyScroll(
                            controller: _scrollController,
                            silkyScrollDuration: ScrollConfig.duration,
                            scrollSpeed: ScrollConfig.speed,
                            animationCurve: ScrollConfig.curve,
                            builder: (context, controller, physics, _) =>
                                ListView.builder(
                                  controller: controller,
                                  physics: physics,
                                  itemExtent: songTileExtentOf(context),
                                  itemCount: genreNames.length,
                                  itemBuilder: (context, index) {
                                    final genreName = genreNames[index];
                                    final songs = genres[genreName]!;
                                    final representativeSong =
                                        notifier.getGenreCoverSong(
                                          genreName,
                                          songs,
                                        ) ??
                                        songs.first;

                                    return ListTile(
                                      leading: _GenreCoverAvatar(
                                        filePath: representativeSong.filePath,
                                        genreName: genreName,
                                      ),
                                      title: Text(genreName),
                                      subtitle: Text('共 ${songs.length} 首歌曲'),
                                      onTap: () {
                                        if (_scrollController.hasClients) {
                                          _savedScrollOffset =
                                              _scrollController.offset;
                                        }
                                        notifier.setActiveGenreView(genreName);
                                      },
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                          12.0,
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

class _GenreCoverAvatar extends StatelessWidget {
  final String filePath;
  final String genreName;

  const _GenreCoverAvatar({required this.filePath, required this.genreName});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // 根据流派名生成稳定的色相，让没有封面的流派在列表里也能区分
    final hue = (genreName.hashCode % 360).abs().toDouble();
    final hsl = HSLColor.fromAHSL(
      1.0,
      hue,
      0.38,
      colorScheme.brightness == Brightness.dark ? 0.34 : 0.78,
    );
    final background = hsl.toColor();
    final foreground = hsl.lightness > 0.55
        ? Colors.black.withValues(alpha: 0.72)
        : Colors.white;

    return SongCoverBuilder(
      filePath: filePath,
      builder: (context, cover) {
        final hasCover = cover != null && cover.isNotEmpty;
        return CircleAvatar(
          backgroundColor: background,
          backgroundImage: hasCover
              ? ResizeImage(MemoryImage(cover), width: 100, height: 100)
              : null,
          child: hasCover ? null : Icon(Icons.category, color: foreground),
        );
      },
    );
  }
}
