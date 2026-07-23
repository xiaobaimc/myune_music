import 'dart:typed_data';
import 'dart:ui';

import 'package:colorgram/colorgram.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../widgets/sort_dialog.dart';
import '../playlist/playlist_content_notifier.dart';
import 'song_list_detail_page.dart';

class AlbumDetailView extends StatelessWidget {
  final VoidCallback onBack;

  const AlbumDetailView({super.key, required this.onBack});

  Future<void> _showSortDialog(BuildContext context) async {
    final notifier = context.read<PlaylistContentNotifier>();
    if (notifier.activeSongList.isEmpty) {
      notifier.postError('没有歌曲可以排序');
      return;
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => SortDialog(
        isAlbumView: true,
        initialCriterion: notifier.activeSongListSortCriterion,
        initialDescending: notifier.activeSongListSortDescending,
      ),
    );

    if (result != null && context.mounted) {
      await notifier.sortActiveSongList(
        criterion: result['criterion'] as SortCriterion,
        descending: result['descending'] as bool,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<PlaylistContentNotifier>();
    final cover = _findAlbumCover(notifier);

    return Column(
      children: [
        _AlbumHeader(
          title: notifier.activeDetailTitle,
          songCount: notifier.activeSongList.length,
          cover: cover,
          isSearching: notifier.isSearching,
          onBack: onBack,
          onSort: () => _showSortDialog(context),
          onSearch: notifier.startSearch,
          onSearchChanged: notifier.search,
          onCloseSearch: notifier.stopSearch,
        ),
        const Expanded(child: SongListDetailWidget(showSearchField: false)),
      ],
    );
  }

  Uint8List? _findAlbumCover(PlaylistContentNotifier notifier) {
    for (final song in notifier.activeSongList) {
      final albumArt = song.albumArt;
      if (albumArt != null) {
        return albumArt;
      }
    }
    return null;
  }
}

class _AlbumHeader extends StatefulWidget {
  final String title;
  final int songCount;
  final Uint8List? cover;
  final bool isSearching;
  final VoidCallback onBack;
  final VoidCallback onSort;
  final VoidCallback onSearch;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onCloseSearch;

  const _AlbumHeader({
    required this.title,
    required this.songCount,
    required this.cover,
    required this.isSearching,
    required this.onBack,
    required this.onSort,
    required this.onSearch,
    required this.onSearchChanged,
    required this.onCloseSearch,
  });

  @override
  State<_AlbumHeader> createState() => _AlbumHeaderState();
}

class _AlbumHeaderState extends State<_AlbumHeader> {
  Uint8List? _lastCover;
  Color? _dominantColor;

  @override
  void initState() {
    super.initState();
    _extractDominantColor();
  }

  @override
  void didUpdateWidget(covariant _AlbumHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cover != widget.cover) {
      _extractDominantColor();
    }
  }

  Future<void> _extractDominantColor() async {
    final cover = widget.cover;
    _lastCover = cover;

    if (cover == null) {
      if (mounted) {
        setState(() => _dominantColor = null);
      }
      return;
    }

    try {
      final colors = await extractColor(
        ResizeImage(MemoryImage(cover), width: 56, height: 56),
        1,
      );
      if (!mounted || _lastCover != cover || colors.isEmpty) return;

      final color = colors.first;
      setState(() {
        _dominantColor = Color.fromARGB(255, color.r, color.g, color.b);
      });
    } catch (_) {
      if (mounted && _lastCover == cover) {
        setState(() => _dominantColor = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final baseColor = _dominantColor ?? colorScheme.surfaceContainerHighest;
    final backgroundColor = _tintForBackground(baseColor, colorScheme);
    final foreground = backgroundColor.computeLuminance() > 0.45
        ? Colors.black
        : Colors.white;
    final subtleForeground = foreground.withValues(alpha: 0.72);

    return Container(
      height: 136,
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: backgroundColor,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _AlbumHeaderBackdrop(cover: widget.cover, baseColor: backgroundColor),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Colors.black.withValues(alpha: 0.24),
                  backgroundColor.withValues(alpha: 0.78),
                  backgroundColor.withValues(alpha: 0.96),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                _HeaderIconButton(
                  icon: Icons.arrow_back,
                  tooltip: '返回专辑',
                  foreground: foreground,
                  onPressed: widget.onBack,
                ),
                const SizedBox(width: 10),
                _AlbumCoverArt(cover: widget.cover),
                const SizedBox(width: 8),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: widget.isSearching
                        ? _HeaderSearchField(
                            key: const ValueKey('album_header_search'),
                            foreground: foreground,
                            onChanged: widget.onSearchChanged,
                            onClose: widget.onCloseSearch,
                          )
                        : _HeaderAlbumInfo(
                            key: const ValueKey('album_header_info'),
                            title: widget.title,
                            songCount: widget.songCount,
                            foreground: foreground,
                            subtleForeground: subtleForeground,
                          ),
                  ),
                ),
                const SizedBox(width: 10),
                _HeaderIconButton(
                  icon: Icons.sort,
                  tooltip: '排序',
                  foreground: foreground,
                  onPressed: widget.onSort,
                ),
                const SizedBox(width: 6),
                _HeaderIconButton(
                  icon: Icons.search,
                  tooltip: '搜索',
                  foreground: foreground,
                  onPressed: widget.onSearch,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _tintForBackground(Color color, ColorScheme colorScheme) {
    final hsl = HSLColor.fromColor(color);
    final isDark = colorScheme.brightness == Brightness.dark;
    return hsl
        .withSaturation(hsl.saturation.clamp(0.24, 0.52))
        .withLightness(isDark ? 0.20 : 0.72)
        .toColor();
  }
}

class _HeaderAlbumInfo extends StatelessWidget {
  final String title;
  final int songCount;
  final Color foreground;
  final Color subtleForeground;

  const _HeaderAlbumInfo({
    super.key,
    required this.title,
    required this.songCount,
    required this.foreground,
    required this.subtleForeground,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Align(
      alignment: Alignment.centerLeft,

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 4),
          Text(
            title,
            textAlign: TextAlign.left,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '共 $songCount 首歌曲',
            textAlign: TextAlign.left,
            style: theme.textTheme.bodySmall?.copyWith(color: subtleForeground),
          ),
        ],
      ),
    );
  }
}

class _HeaderSearchField extends StatelessWidget {
  final Color foreground;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;

  const _HeaderSearchField({
    super.key,
    required this.foreground,
    required this.onChanged,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      autofocus: true,
      style: TextStyle(color: foreground),
      cursorColor: foreground,
      decoration: InputDecoration(
        isDense: true,
        hintText: '搜索当前专辑...',
        hintStyle: TextStyle(color: foreground.withValues(alpha: 0.58)),
        prefixIcon: Icon(Icons.search, color: foreground),
        suffixIcon: IconButton(
          icon: Icon(Icons.close, color: foreground),
          onPressed: onClose,
        ),
        filled: true,
        fillColor: foreground.withValues(alpha: 0.12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: foreground.withValues(alpha: 0.20)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: foreground.withValues(alpha: 0.16)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: foreground.withValues(alpha: 0.42)),
        ),
      ),
      onChanged: onChanged,
    );
  }
}

class _AlbumHeaderBackdrop extends StatelessWidget {
  final Uint8List? cover;
  final Color baseColor;

  const _AlbumHeaderBackdrop({required this.cover, required this.baseColor});

  @override
  Widget build(BuildContext context) {
    if (cover == null) {
      return ColoredBox(color: baseColor);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.memory(
          cover!,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          cacheWidth: 600,
          errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
        ), // 缓存封面
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: ColoredBox(color: baseColor.withValues(alpha: 0.40)),
        ),
      ],
    );
  }
}

class _AlbumCoverArt extends StatelessWidget {
  final Uint8List? cover;

  const _AlbumCoverArt({required this.cover});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: 88,
      height: 88,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: colorScheme.secondaryContainer,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.20),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: cover != null
          ? Image.memory(cover!, fit: BoxFit.cover, gaplessPlayback: true)
          : Icon(
              Icons.album,
              size: 42,
              color: colorScheme.onSecondaryContainer,
            ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color foreground;
  final VoidCallback onPressed;

  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.foreground,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: foreground.withValues(alpha: 0.12),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: IconButton(
          icon: Icon(icon),
          color: foreground,
          onPressed: onPressed,
        ),
      ),
    );
  }
}
