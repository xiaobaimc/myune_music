import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../playlist/playlist_content_widget.dart';
import '../playlist/playlist_content_notifier.dart';
import '../../widgets/sort_dialog.dart';
import '../playlist/playlist_models.dart';

class AllSongsPage extends StatelessWidget {
  const AllSongsPage({super.key});

  void _showSortDialog(BuildContext context) async {
    final notifier = context.read<PlaylistContentNotifier>();
    if (notifier.allSongs.isEmpty) {
      notifier.postError('没有歌曲可以排序');
      return;
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const SortDialog(),
    );

    if (result != null && context.mounted) {
      await notifier.sortAllSongs(
        criterion: result['criterion'] as SortCriterion,
        descending: result['descending'] as bool,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<PlaylistContentNotifier>();
    final isSearching = notifier.isSearching;
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 6.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: isSearching
                      // --- 搜索状态下显示的UI ---
                      ? TextField(
                          key: const ValueKey('search_field_all'),
                          autofocus: true,
                          decoration: InputDecoration(
                            hintText: '搜索全部歌曲...',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: notifier.stopSearch, // 点击关闭按钮，退出搜索
                            ),
                          ),
                          onChanged: (keyword) => notifier.search(keyword),
                        )
                      // --- 常规状态下显示的UI ---
                      : Row(
                          key: const ValueKey('title_bar_all'),
                          children: [
                            Text(
                              '全部歌曲',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(width: 16),
                            // 显示歌曲总数
                            if (notifier.allSongs.isNotEmpty)
                              Text(
                                '共 ${notifier.allSongs.length} 首',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.sort),
                              tooltip: '排序歌曲',
                              onPressed: () => _showSortDialog(context),
                            ),
                            const SizedBox(width: 8),
                            // 搜索按钮
                            IconButton(
                              icon: const Icon(Icons.search),
                              tooltip: '搜索歌曲',
                              onPressed: notifier.startSearch, // 点击触发搜索
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: Material(
                    child: Selector<PlaylistContentNotifier, List<Song>>(
                      selector: (_, notifier) {
                        // 根据是否在搜索，决定使用哪个列表
                        return notifier.isSearching
                            ? notifier.filteredSongs
                            : notifier.allSongs;
                      },
                      builder: (context, songs, _) {
                        // 检查是否仍在加载全部歌曲
                        if (!notifier.allSongsLoaded) {
                          return const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [CircularProgressIndicator()],
                            ),
                          );
                        }

                        if (songs.isEmpty) {
                          return Center(
                            child: Text(isSearching ? '未找到匹配的歌曲' : '没有发现任何歌曲'),
                          );
                        }

                        return ReorderableListView.builder(
                          buildDefaultDragHandles: false,
                          proxyDecorator: (child, index, animation) => Material(
                            elevation: 4,
                            color: colorScheme.surface,
                            borderRadius: BorderRadius.circular(8),
                            child: child,
                          ),
                          itemCount: songs.length,
                          itemBuilder: (context, index) {
                            final song = songs[index];
                            // 播放时需要找到它在原始 allSongs 列表中的索引
                            final originalIndex = notifier.allSongs.indexOf(
                              song,
                            );
                            return SongTileWidget(
                              key: ValueKey(song.filePath),
                              song: song,
                              index: index,
                              contextPlaylist: notifier.allSongsVirtualPlaylist,
                              enableContextMenu: false,
                              onTap: () {
                                if (originalIndex != -1) {
                                  notifier.playSongFromAllSongs(originalIndex);
                                }
                              },
                            );
                          },
                          onReorder: (oldIndex, newIndex) {
                            // 在搜索时，不执行排序操作
                            if (isSearching) return;
                            notifier.reorderAllSongs(oldIndex, newIndex);
                          },
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
