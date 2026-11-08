import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../widgets/song_cover.dart';
import '../../widgets/sort_dialog.dart';
import '../playlist/playlist_content_notifier.dart';
import 'song_list_detail_page.dart';
import '../../services/notification_service.dart';

class GenreDetailView extends StatelessWidget {
  final VoidCallback onBack;

  const GenreDetailView({super.key, required this.onBack});

  Future<void> _showSortDialog(BuildContext context) async {
    final notifier = context.read<PlaylistContentNotifier>();
    if (notifier.activeSongList.isEmpty) {
      context.read<NotificationService>().error('没有歌曲可以排序');
      return;
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const SortDialog(),
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
    final songs = notifier.activeSongList;
    final coverSong = songs.isEmpty
        ? null
        : notifier.getGenreCoverSong(notifier.activeDetailTitle, songs) ??
              songs.first;

    Widget buildHeader(Uint8List? cover) {
      return _GenreHeader(
        title: notifier.activeDetailTitle,
        songCount: songs.length,
        cover: cover,
        isSearching: notifier.isSearching,
        onBack: onBack,
        onSort: () => _showSortDialog(context),
        onSearch: notifier.startSearch,
        onSearchChanged: notifier.search,
        onCloseSearch: notifier.stopSearch,
      );
    }

    return Column(
      children: [
        // 封面单独订阅封面仓库：封面加载完成只重建头部，不影响下面的歌曲列表
        if (coverSong != null)
          SongCoverBuilder(
            filePath: coverSong.filePath,
            builder: (context, cover) => buildHeader(cover),
          )
        else
          buildHeader(null),
        const Expanded(child: SongListDetailWidget(showSearchField: false)),
      ],
    );
  }
}

class _GenreHeader extends StatelessWidget {
  final String title;
  final int songCount;
  final Uint8List? cover;
  final bool isSearching;
  final VoidCallback onBack;
  final VoidCallback onSort;
  final VoidCallback onSearch;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onCloseSearch;

  const _GenreHeader({
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final backgroundColor = Color.lerp(
      colorScheme.primaryContainer,
      colorScheme.secondaryContainer,
      0.5,
    )!;
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
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            backgroundColor,
            Color.lerp(backgroundColor, colorScheme.tertiaryContainer, 0.55)!,
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (cover != null) ...[
            Image.memory(
              cover!,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              cacheWidth: 600,
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox.shrink(),
            ),
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: ColoredBox(color: backgroundColor.withValues(alpha: 0.45)),
            ),
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
          ] else
            // 没有封面时的流派分类水印
            Positioned(
              right: -18,
              bottom: -34,
              child: Icon(
                Icons.category,
                size: 168,
                color: foreground.withValues(alpha: 0.08),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                _HeaderIconButton(
                  icon: Icons.arrow_back,
                  tooltip: '返回流派',
                  foreground: foreground,
                  onPressed: onBack,
                ),
                const SizedBox(width: 10),
                _GenreCoverArt(cover: cover, foreground: foreground),
                const SizedBox(width: 8),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: isSearching
                        ? _HeaderSearchField(
                            key: const ValueKey('genre_header_search'),
                            foreground: foreground,
                            onChanged: onSearchChanged,
                            onClose: onCloseSearch,
                          )
                        : _HeaderGenreInfo(
                            key: const ValueKey('genre_header_info'),
                            title: title,
                            songCount: songCount,
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
                  onPressed: onSort,
                ),
                const SizedBox(width: 6),
                _HeaderIconButton(
                  icon: Icons.search,
                  tooltip: '搜索',
                  foreground: foreground,
                  onPressed: onSearch,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderGenreInfo extends StatelessWidget {
  final String title;
  final int songCount;
  final Color foreground;
  final Color subtleForeground;

  const _HeaderGenreInfo({
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
        hintText: '搜索当前流派...',
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

class _GenreCoverArt extends StatelessWidget {
  final Uint8List? cover;
  final Color foreground;

  const _GenreCoverArt({required this.cover, required this.foreground});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      height: 88,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: foreground.withValues(alpha: 0.14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: cover != null
          ? Image.memory(cover!, fit: BoxFit.cover, gaplessPlayback: true)
          : Icon(Icons.category, size: 42, color: foreground),
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
