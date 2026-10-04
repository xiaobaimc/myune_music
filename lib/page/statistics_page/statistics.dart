import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;
import 'dart:typed_data';
import 'package:silky_scroll/silky_scroll.dart';
import '../../theme/scroll_config.dart';

import '../playlist/playlist_content_notifier.dart';
import '../setting/settings_provider.dart';
import '../playlist/playlist_models.dart';
import '../../services/search_service.dart';
import '../../utils/search_debouncer.dart';
import '../../widgets/custom_background_layer.dart';
import '../../widgets/song_cover.dart';
import 'statistics_manager.dart';
import 'statistics_models.dart';

class Statistics extends StatefulWidget {
  const Statistics({super.key});

  @override
  State<Statistics> createState() => _StatisticsState();
}

class _StatisticsState extends State<Statistics> {
  // 页面上展示的排行榜条数
  static const int _rankingPreviewCount = 5;

  static const int _rankingProbeCount = _rankingPreviewCount + 1;

  late StatisticsManager _statsManager;

  late final ScrollController scrollController;

  @override
  void initState() {
    super.initState();
    _statsManager = StatisticsManager();
    scrollController = ScrollController();
  }

  @override
  void dispose() {
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

              ListenableBuilder(
                listenable: playlistNotifier.coverStore,
                builder: (context, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 歌曲播放排行
                    _buildSectionHeader(
                      title: '歌曲播放排行',
                      hasMore:
                          _statsManager
                              .getTopPlayedSongs(_rankingProbeCount)
                              .length >
                          _rankingPreviewCount,
                      onShowMore: _showTopSongsDialog,
                    ),
                    const SizedBox(height: 8),
                    _buildTopSongsList(playlistNotifier.allSongs),

                    const SizedBox(height: 24),

                    // 艺术家播放排行
                    _buildSectionHeader(
                      title: '艺术家播放排行',
                      hasMore:
                          _statsManager
                              .getTopArtists(_rankingProbeCount, separators)
                              .length >
                          _rankingPreviewCount,
                      onShowMore: () => _showTopArtistsDialog(separators),
                    ),
                    const SizedBox(height: 8),
                    _buildTopArtistsList(separators),

                    const SizedBox(height: 24),

                    // 专辑播放排行
                    _buildSectionHeader(
                      title: '专辑播放排行',
                      hasMore:
                          _statsManager
                              .getTopAlbums(_rankingProbeCount)
                              .length >
                          _rankingPreviewCount,
                      onShowMore: _showTopAlbumsDialog,
                    ),
                    const SizedBox(height: 8),
                    _buildTopAlbumsList(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _cardColor(BuildContext context) {
    return CustomBackgroundSurfaces.panelColor(
      context.watch<SettingsProvider>(),
      Theme.of(context).colorScheme.surfaceContainerLow,
    );
  }

  double _cardElevation(BuildContext context) {
    return CustomBackgroundSurfaces.cardElevationOverBackground(
      context.watch<SettingsProvider>(),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Card(
      color: _cardColor(context),
      elevation: _cardElevation(context),
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

  // 排行榜的小标题栏
  Widget _buildSectionHeader({
    required String title,
    required bool hasMore,
    required VoidCallback onShowMore,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        if (hasMore)
          TextButton(onPressed: onShowMore, child: const Text('查看全部')),
      ],
    );
  }

  // ---- 歌曲播放排行 ----

  Widget _buildTopSongsList(List<Song> allSongs) {
    final topSongs = _statsManager.getTopPlayedSongs(_rankingPreviewCount);

    if (topSongs.isEmpty) {
      return _buildEmptyRankingCard();
    }

    final showAlbumName = context.watch<SettingsProvider>().showAlbumName;
    // 创建一个映射，使用文件名作为键来查找所有具有相同文件名的歌曲
    final songMap = _songsByFileName(allSongs);

    return _buildRankingCard(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      itemCount: topSongs.length,
      separator: const Divider(height: 2),
      itemBuilder: (context, index) {
        final stat = topSongs[index];
        return _buildTopSongTile(
          stat,
          _resolveSongForStat(
            matchedSongs: songMap[p.basename(stat.path)],
            fallback: _fallbackSongOf(stat),
          ),
          showAlbumName,
        );
      },
    );
  }

  Widget _buildTopSongTile(SongPlayStat stat, Song song, bool showAlbumName) {
    return ListTile(
      leading: _StatCover(
        filePath: song.filePath,
        fallbackIcon: Icons.music_note,
      ),
      title: Text(stat.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        showAlbumName ? '${stat.artist} - ${stat.album}' : stat.artist,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text('${stat.playCount} 次'),
    );
  }

  // ---- 艺术家播放排行 ----

  Widget _buildTopArtistsList(List<String> separators) {
    final topArtists = _statsManager.getTopArtists(
      _rankingPreviewCount,
      separators,
    );

    if (topArtists.isEmpty) {
      return _buildEmptyRankingCard();
    }

    // 为每个艺术家找到一个代表性的专辑封面
    final coverSongs = _resolveArtistCoverSongs(
      topArtists.map((entry) => entry.key),
      context.watch<PlaylistContentNotifier>().allSongs,
      separators,
    );

    return _buildRankingCard(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      itemCount: topArtists.length,
      separator: const Divider(),
      itemBuilder: (context, index) => _buildTopArtistTile(
        topArtists[index],
        coverSongs[topArtists[index].key],
      ),
    );
  }

  Widget _buildTopArtistTile(MapEntry<String, int> artist, Song? coverSong) {
    return ListTile(
      leading: coverSong == null
          ? const SizedBox(
              width: 40,
              height: 40,
              child: Icon(Icons.person, size: 20),
            )
          : _StatCover(
              filePath: coverSong.filePath,
              fallbackIcon: Icons.person,
              borderRadius: BorderRadius.circular(100),
            ),
      title: Text(artist.key, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Text('${artist.value} 次'),
    );
  }

  // ---- 专辑播放排行 ----

  Widget _buildTopAlbumsList() {
    final topAlbums = _statsManager.getTopAlbums(_rankingPreviewCount);

    if (topAlbums.isEmpty) {
      return _buildEmptyRankingCard();
    }

    // 为每个专辑找到一个代表性的专辑封面
    final coverSongs = _resolveAlbumCoverSongs(
      topAlbums.map((entry) => entry.key),
      context.watch<PlaylistContentNotifier>().allSongs,
    );

    return _buildRankingCard(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      itemCount: topAlbums.length,
      separator: const Divider(),
      itemBuilder: (context, index) => _buildTopAlbumTile(
        topAlbums[index],
        coverSongs[topAlbums[index].key],
      ),
    );
  }

  Widget _buildTopAlbumTile(MapEntry<String, int> album, Song? coverSong) {
    return ListTile(
      leading: coverSong == null
          ? const SizedBox(
              width: 40,
              height: 40,
              child: Icon(Icons.album, size: 20),
            )
          : _StatCover(filePath: coverSong.filePath, fallbackIcon: Icons.album),
      title: Text(album.key, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Text('${album.value} 次'),
    );
  }

  // ---- 排行榜弹窗（查看全部）----

  Future<void> _showTopSongsDialog() async {
    // 一次拿全量数据，弹窗内按 100 条分批展示
    final topSongs = _statsManager.getTopPlayedSongs(null);
    if (topSongs.isEmpty) return;

    final showAlbumName = context.read<SettingsProvider>().showAlbumName;
    final songMap = _songsByFileName(
      context.read<PlaylistContentNotifier>().allSongs,
    );

    if (!mounted) return;
    await _showRankingDialog<SongPlayStat>(
      title: '歌曲播放排行',
      unit: '首',
      searchHint: '搜索歌曲名、歌手名...',
      items: topSongs,
      searchTextOf: (stat) => (title: stat.title, artist: stat.artist),
      estimatedRowExtent: _tileExtent(context, twoLine: true),
      // 只有真正滚到的那几行才会去曲库里解析歌曲并加载封面
      itemBuilder: (context, stat, index) => _buildTopSongTile(
        stat,
        _resolveSongForStat(
          matchedSongs: songMap[p.basename(stat.path)],
          fallback: _fallbackSongOf(stat),
        ),
        showAlbumName,
      ),
    );
  }

  Future<void> _showTopArtistsDialog(List<String> separators) async {
    // limit 传 null：弹窗里可以一直查看更多到全部记录
    final topArtists = _statsManager.getTopArtists(null, separators);
    if (topArtists.isEmpty) return;

    final coverSongs = _resolveArtistCoverSongs(
      topArtists.map((entry) => entry.key),
      context.read<PlaylistContentNotifier>().allSongs,
      separators,
    );

    if (!mounted) return;
    await _showRankingDialog<MapEntry<String, int>>(
      title: '艺术家播放排行',
      unit: '位',
      searchHint: '搜索歌手名...',
      items: topArtists,
      searchTextOf: (artist) => (title: artist.key, artist: ''),
      estimatedRowExtent: _tileExtent(context, twoLine: false),
      itemBuilder: (context, artist, index) =>
          _buildTopArtistTile(artist, coverSongs[artist.key]),
    );
  }

  Future<void> _showTopAlbumsDialog() async {
    // limit 传 null：弹窗里可以一直查看更多到全部记录
    final topAlbums = _statsManager.getTopAlbums(null);
    if (topAlbums.isEmpty) return;

    final coverSongs = _resolveAlbumCoverSongs(
      topAlbums.map((entry) => entry.key),
      context.read<PlaylistContentNotifier>().allSongs,
    );

    if (!mounted) return;
    await _showRankingDialog<MapEntry<String, int>>(
      title: '专辑播放排行',
      unit: '张',
      searchHint: '搜索专辑名...',
      items: topAlbums,
      searchTextOf: (album) => (title: album.key, artist: ''),
      estimatedRowExtent: _tileExtent(context, twoLine: false),
      itemBuilder: (context, album, index) =>
          _buildTopAlbumTile(album, coverSongs[album.key]),
    );
  }

  Future<void> _showRankingDialog<T>({
    required String title,
    required String unit,
    required String searchHint,
    required List<T> items,
    required ({String title, String artist}) Function(T item) searchTextOf,
    required double estimatedRowExtent,
    required Widget Function(BuildContext context, T item, int index)
    itemBuilder,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => _RankingDialog<T>(
        title: title,
        unit: unit,
        searchHint: searchHint,
        items: items,
        searchTextOf: searchTextOf,
        estimatedRowExtent: estimatedRowExtent,
        itemBuilder: itemBuilder,
      ),
    );
  }

  // 只用来决定弹窗的初始高度，不参与行布局
  double _tileExtent(BuildContext context, {required bool twoLine}) {
    return (twoLine ? 72.0 : 56.0) +
        Theme.of(context).visualDensity.baseSizeAdjustment.dy;
  }

  // ---- 通用小工具 ----

  Widget _buildEmptyRankingCard() {
    return Card(
      color: _cardColor(context),
      elevation: _cardElevation(context),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text('暂无播放记录', style: Theme.of(context).textTheme.bodyMedium),
      ),
    );
  }

  Widget _buildRankingCard({
    required int itemCount,
    required NullableIndexedWidgetBuilder itemBuilder,
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(vertical: 2.0),
    Widget? separator,
  }) {
    final Widget? divider = separator;
    final Widget list = divider == null
        ? ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: itemCount,
            itemBuilder: itemBuilder,
          )
        : ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: itemCount,
            separatorBuilder: (_, __) => divider,
            itemBuilder: itemBuilder,
          );

    return Card(
      color: _cardColor(context),
      elevation: _cardElevation(context),
      child: Padding(padding: padding, child: list),
    );
  }

  // 使用文件名作为键，方便用统计记录去曲库里找回真正的 song
  Map<String, List<Song>> _songsByFileName(List<Song> allSongs) {
    final map = <String, List<Song>>{};
    for (final song in allSongs) {
      (map[p.basename(song.filePath)] ??= <Song>[]).add(song);
    }
    return map;
  }

  Song _fallbackSongOf(SongPlayStat stat) {
    return Song(
      title: stat.title,
      artist: stat.artist,
      album: stat.album,
      filePath: stat.path,
    );
  }

  // 为每个艺术家挑一首代表歌曲（优先挑封面已经缓存的）
  Map<String, Song> _resolveArtistCoverSongs(
    Iterable<String> artistNames,
    List<Song> allSongs,
    List<String> separators,
  ) {
    final wanted = artistNames.toSet();
    final result = <String, Song>{};
    final withCover = <String>{};
    // 循环前取一次 notifier，避免每个歌曲都做一次 provider 查找
    final notifier = context.read<PlaylistContentNotifier>();

    for (final song in allSongs) {
      final hasCover = notifier.coverOfCacheKey(song.normalizedPath) != null;
      for (final raw in _splitArtists(song.artist, separators)) {
        final artistName = raw.trim();
        if (artistName.isEmpty || !wanted.contains(artistName)) continue;
        if (withCover.contains(artistName)) continue;
        if (result.containsKey(artistName) && !hasCover) continue;
        result[artistName] = song;
        if (hasCover) {
          withCover.add(artistName);
        }
      }
    }
    return result;
  }

  // 为每个专辑挑一首代表歌曲（优先挑封面已经缓存的）
  Map<String, Song> _resolveAlbumCoverSongs(
    Iterable<String> albumNames,
    List<Song> allSongs,
  ) {
    final wanted = albumNames.toSet();
    final result = <String, Song>{};
    final withCover = <String>{};
    // 循环前取一次 notifier，避免每个歌曲都做一次 provider 查找
    final notifier = context.read<PlaylistContentNotifier>();

    for (final song in allSongs) {
      final albumName = song.album;
      if (!wanted.contains(albumName) || withCover.contains(albumName)) {
        continue;
      }
      final hasCover = notifier.coverOfCacheKey(song.normalizedPath) != null;
      if (result.containsKey(albumName) && !hasCover) continue;
      result[albumName] = song;
      if (hasCover) {
        withCover.add(albumName);
      }
    }
    return result;
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

  // 从封面仓库里查询某首歌的封面
  Uint8List? _coverOf(Song song) {
    return context.read<PlaylistContentNotifier>().coverOfCacheKey(
      song.normalizedPath,
    );
  }

  Song _resolveSongForStat({
    required List<Song>? matchedSongs,
    required Song fallback,
  }) {
    if (matchedSongs == null || matchedSongs.isEmpty) {
      return fallback;
    }
    return matchedSongs.firstWhere(
      (s) => _coverOf(s) != null,
      orElse: () => matchedSongs.first,
    );
  }
}

class _StatCover extends StatelessWidget {
  final String filePath;
  final IconData fallbackIcon;
  final BorderRadius borderRadius;
  final double size;

  const _StatCover({
    required this.filePath,
    required this.fallbackIcon,
    this.borderRadius = const BorderRadius.all(Radius.circular(4)),
  }) : size = 40;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: SongCoverBuilder(
        filePath: filePath,
        builder: (context, cover) {
          if (cover == null || cover.isEmpty) {
            return Icon(fallbackIcon, size: size / 2);
          }
          return ClipRRect(
            borderRadius: borderRadius,
            child: Image.memory(
              cacheWidth: (size * 2.5).round(),
              cover,
              width: size,
              height: size,
              fit: BoxFit.cover,
            ),
          );
        },
      ),
    );
  }
}

class _RankingSearchEntry<T> {
  final T item;
  final SongSearchIndex index;

  _RankingSearchEntry(this.item, this.index);
}

class _RankingDialog<T> extends StatefulWidget {
  final String title;

  // 计数单位，例如 首、位、张
  final String unit;

  final String searchHint;

  final List<T> items;

  // 歌曲：标题 + 艺术家；歌手/专辑：名字 + 空串
  final ({String title, String artist}) Function(T item) searchTextOf;

  // 仅用于决定弹窗的初始高度
  final double estimatedRowExtent;

  final Widget Function(BuildContext context, T item, int index) itemBuilder;

  const _RankingDialog({
    required this.title,
    required this.unit,
    required this.searchHint,
    required this.items,
    required this.searchTextOf,
    required this.estimatedRowExtent,
    required this.itemBuilder,
  });

  @override
  State<_RankingDialog<T>> createState() => _RankingDialogState<T>();
}

class _RankingDialogState<T> extends State<_RankingDialog<T>> {
  // 每次展示/追加的条数
  static const int _pageSize = 100;

  static const double _headerExtent = 132.0;

  static const EdgeInsets _listPadding = EdgeInsets.only(top: 4, bottom: 16);

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final SearchDebouncer _searchDebouncer = SearchDebouncer();
  final SearchService _searchService = SearchService();

  // 搜索索引
  List<SongSearchIndex>? _searchIndices;
  Map<Song, _RankingSearchEntry<T>>? _entriesBySong;

  String _query = '';

  List<T>? _filtered;

  int _visibleCount = 0;

  // 当前用于展示的条目
  List<T> get _visibleItems => _filtered ?? widget.items;

  bool get _hasMore => _visibleCount < _visibleItems.length;

  @override
  void initState() {
    super.initState();
    _visibleCount = _initialVisibleCount(widget.items.length);
  }

  @override
  void dispose() {
    _searchDebouncer.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  static int _initialVisibleCount(int total) =>
      total < _pageSize ? total : _pageSize;

  void _showMore() {
    final total = _visibleItems.length;
    setState(() {
      final next = _visibleCount + _pageSize;
      _visibleCount = next > total ? total : next;
    });
  }

  // ---- 搜索 ----

  void _onQueryChanged(String value) {
    // 只刷新清除按钮的显隐，真正的过滤交给防抖
    setState(() {});
    _searchDebouncer.run(_applySearch);
  }

  void _clearSearch() {
    if (_searchController.text.isEmpty && _query.isEmpty) return;
    _searchController.clear();
    _applySearch();
  }

  void _applySearch() {
    if (!mounted) return;
    final keyword = _searchController.text.trim();
    if (keyword == _query) return;

    final List<T>? filtered = keyword.isEmpty ? null : _runSearch(keyword);

    setState(() {
      _query = keyword;
      _filtered = filtered;
      _visibleCount = _initialVisibleCount((filtered ?? widget.items).length);
    });
  }

  List<T> _runSearch(String keyword) {
    _ensureSearchIndices();

    final bySong = _entriesBySong!;
    final results = _searchService.search(keyword, _searchIndices!);

    final matched = <T>[];
    for (final result in results) {
      final entry = bySong[result.song];
      if (entry != null) {
        matched.add(entry.item);
      }
    }
    return matched;
  }

  void _ensureSearchIndices() {
    if (_searchIndices != null) return;

    final items = widget.items;
    final bySong = <Song, _RankingSearchEntry<T>>{};
    final indices = <SongSearchIndex>[];

    for (var i = 0; i < items.length; i++) {
      final text = widget.searchTextOf(items[i]);
      // filePath 只是占位，不参与匹配
      final song = Song(title: text.title, artist: text.artist, filePath: '$i');
      final entry = _RankingSearchEntry<T>(items[i], SongSearchIndex(song));
      bySong[song] = entry;
      indices.add(entry.index);
    }

    _entriesBySong = bySong;
    _searchIndices = indices;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final screenHeight = MediaQuery.of(context).size.height;

    final items = _visibleItems;
    // 最后一行是查看更多按钮
    final int rowCount = _visibleCount + (_hasMore ? 1 : 0);

    // 内容少时窗口自适应，内容多时最多占屏幕的 70%，
    final double heightBudget = screenHeight - _headerExtent - 48;
    final double percentBudget = screenHeight * 0.7;
    final double maxListHeight = percentBudget < heightBudget
        ? percentBudget
        : heightBudget;
    final double minListHeight = maxListHeight < 140.0 ? maxListHeight : 140.0;
    final double contentHeight =
        rowCount * widget.estimatedRowExtent + _listPadding.vertical;
    final double listHeight = contentHeight < minListHeight
        ? minListHeight
        : (contentHeight > maxListHeight ? maxListHeight : contentHeight);

    return Dialog(
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 8, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: Theme.of(
                            context,
                          ).textTheme.titleMedium?.copyWith(fontSize: 18.0),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            _buildSubtitle(),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: colorScheme.onSurfaceVariant),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: TextField(
                controller: _searchController,
                onChanged: _onQueryChanged,
                textInputAction: TextInputAction.search,
                style: Theme.of(context).textTheme.bodyMedium,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: widget.searchHint,
                  hintStyle: Theme.of(context).textTheme.bodySmall,
                  prefixIcon: const Icon(Icons.search, size: 18),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          tooltip: '清除',
                          visualDensity: VisualDensity.compact,
                          onPressed: _clearSearch,
                        ),
                  suffixIconConstraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            Divider(height: 1, color: colorScheme.outlineVariant),
            SizedBox(
              height: listHeight,
              child: items.isEmpty
                  ? Center(
                      child: Text(
                        '没有匹配的记录',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    )
                  : SilkyScroll(
                      controller: _scrollController,
                      silkyScrollDuration: ScrollConfig.duration,
                      scrollSpeed: ScrollConfig.speed,
                      animationCurve: ScrollConfig.curve,
                      builder: (context, controller, physics, _) =>
                          ListView.builder(
                            controller: controller,
                            physics: physics,
                            padding: _listPadding,
                            itemCount: rowCount,
                            itemBuilder: (context, index) {
                              if (index >= _visibleCount) {
                                return _buildShowMoreRow();
                              }
                              return widget.itemBuilder(
                                context,
                                items[index],
                                index,
                              );
                            },
                          ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _buildSubtitle() {
    if (_query.isNotEmpty) {
      return '共找到 ${_visibleItems.length}${widget.unit}';
    }

    final total = widget.items.length;
    if (!_hasMore) {
      return '共 $total${widget.unit}';
    }
    return '已显示 $_visibleCount ${widget.unit} / 共 $total${widget.unit}';
  }

  Widget _buildShowMoreRow() {
    final remaining = _visibleItems.length - _visibleCount;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: TextButton.icon(
          onPressed: _showMore,
          icon: const Icon(Icons.expand_more, size: 18),
          label: Text('查看更多（还有 $remaining${widget.unit}）'),
          style: TextButton.styleFrom(
            // 加大点击区域，鼠标好点一些
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
        ),
      ),
    );
  }
}
