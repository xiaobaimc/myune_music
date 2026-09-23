import 'package:flutter/material.dart';
import '../../layout/navigation_notifier.dart';
import '../../services/pinyin_cache.dart';
import '../playlist/playlist_models.dart';
import 'package:provider/provider.dart';
import 'package:silky_scroll/silky_scroll.dart';
import '../../theme/scroll_config.dart';
import 'dart:typed_data';
import '../playlist/playlist_content_notifier.dart';
import '../../widgets/single_line_lyrics.dart';
import 'artist_detail_view.dart';
import '../setting/settings_provider.dart';
import '../../widgets/custom_background_layer.dart';

class ArtistList extends StatefulWidget {
  const ArtistList({super.key});

  @override
  State<ArtistList> createState() => _ArtistListState();
}

class _ArtistListState extends State<ArtistList> {
  late final ScrollController _scrollController = ScrollController();
  double _savedScrollOffset = 0.0;
  bool _prevShowArtistDetail = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  bool _isSearching = false;
  String _searchKeyword = '';

  List<String>? _cachedSortedArtists;
  Map<String, List<dynamic>>? _lastArtistData;

  void _closeArtistDetail() {
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

  List<String> _getSortedArtists(Map<String, List<Song>> artists) {
    if (!identical(artists, _lastArtistData)) {
      _lastArtistData = artists;
      final names = artists.keys.toList();
      final cache = PinyinCache.instance;
      names.sort(
        (a, b) => cache.getFullPinyin(a).compareTo(cache.getFullPinyin(b)),
      );
      _cachedSortedArtists = names;
    }
    return _cachedSortedArtists!;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final notifier = context.read<PlaylistContentNotifier>();
    final showArtistDetail =
        notifier.currentDetailViewContext == DetailViewContext.artist;

    if (!showArtistDetail && _prevShowArtistDetail && _savedScrollOffset > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_savedScrollOffset);
          _savedScrollOffset = 0.0;
        }
      });
    }
    _prevShowArtistDetail = showArtistDetail;
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<PlaylistContentNotifier>();
    final settings = context.watch<SettingsProvider>();
    final showArtistDetail =
        notifier.currentDetailViewContext == DetailViewContext.artist;

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
      child: showArtistDetail
          ? ArtistDetailView(
              key: const ValueKey('artist_detail'),
              onBack: _closeArtistDetail,
            )
          : Column(
              key: const ValueKey('artist_list'),
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
                                  notifier.hideSingleSongArtists
                                      ? Icons.filter_alt_off_outlined
                                      : Icons.filter_alt_outlined,
                                  color: notifier.hideSingleSongArtists
                                      ? Theme.of(context).colorScheme.primary
                                      : null,
                                ),
                                tooltip: notifier.hideSingleSongArtists
                                    ? '显示所有歌手'
                                    : '隐藏只有单首歌曲的歌手',
                                onPressed: () =>
                                    notifier.toggleHideSingleSongArtists(),
                              ),
                              IconButton(
                                icon: const Icon(Icons.search),
                                tooltip: '搜索歌手',
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
                    color: CustomBackgroundSurfaces.materialColor(settings),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      child: Builder(
                        builder: (context) {
                          final artists = notifier.songsByArtist;
                          // 使用缓存的排序结果
                          var artistNames = _getSortedArtists(artists).toList();

                          // 应用搜索过滤逻辑（支持拼音搜索）
                          if (_searchKeyword.isNotEmpty) {
                            final lowerKeyword = _searchKeyword.toLowerCase();
                            final isLatin = RegExp(
                              r'^[a-z0-9]+$',
                            ).hasMatch(lowerKeyword);
                            artistNames = artistNames.where((name) {
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

                          // 应用单曲歌手过滤逻辑
                          if (notifier.hideSingleSongArtists) {
                            artistNames = artistNames.where((name) {
                              return artists[name]!.length > 1;
                            }).toList();
                          }

                          if (artistNames.isEmpty) {
                            return Center(
                              child: Text(_isSearching ? '未找到匹配的歌手' : '未找到歌手'),
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
                                  itemCount: artistNames.length,
                                  itemBuilder: (context, index) {
                                    final artistName = artistNames[index];
                                    final songs = artists[artistName]!;
                                    final representativeSong =
                                        notifier.getArtistCoverSong(
                                          artistName,
                                          songs,
                                        ) ??
                                        songs.first;
                                    final representativeArt =
                                        representativeSong.albumArt;

                                    return ListTile(
                                      leading: _ArtistCoverAvatar(
                                        filePath: representativeSong.filePath,
                                        representativeArt: representativeArt,
                                      ),
                                      title: Text(artistName),
                                      subtitle: Text('共 ${songs.length} 首歌曲'),
                                      onTap: () {
                                        if (_scrollController.hasClients) {
                                          _savedScrollOffset =
                                              _scrollController.offset;
                                        }
                                        notifier.setActiveArtistView(
                                          artistName,
                                        );
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

class _ArtistCoverAvatar extends StatefulWidget {
  final String filePath;
  final Uint8List? representativeArt;

  const _ArtistCoverAvatar({
    required this.filePath,
    required this.representativeArt,
  });

  @override
  State<_ArtistCoverAvatar> createState() => _ArtistCoverAvatarState();
}

class _ArtistCoverAvatarState extends State<_ArtistCoverAvatar> {
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
  void didUpdateWidget(covariant _ArtistCoverAvatar oldWidget) {
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
    return CircleAvatar(
      backgroundImage: widget.representativeArt != null
          ? ResizeImage(
              MemoryImage(widget.representativeArt!),
              width: 100,
              height: 100,
            )
          : null,
      child: widget.representativeArt == null ? const Icon(Icons.person) : null,
    );
  }
}
