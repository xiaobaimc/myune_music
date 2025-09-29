import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../playlist/playlist_content_widget.dart';
import '../playlist/playlist_content_notifier.dart';
import '../../widgets/sort_dialog.dart';
import '../playlist/playlist_models.dart';
import '../../widgets/app_window_title_bar.dart';
import '../../widgets/playbar.dart';
import '../../widgets/playing_queue_drawer.dart';

class SongListDetailPage extends StatelessWidget {
  const SongListDetailPage({super.key});

  void _showSortDialog(BuildContext context) async {
    final notifier = context.read<PlaylistContentNotifier>();
    if (notifier.activeSongList.isEmpty) {
      notifier.postError('没有歌曲可以排序');
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
    final title = notifier.activeDetailTitle;

    return Scaffold(
      endDrawer: const PlayingQueueDrawer(),
      body: Column(
        children: [
          const AppWindowTitleBar(),
          Container(
            height: kToolbarHeight,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                // 返回按钮
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: '返回',
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 8),
                // 标题和歌曲数量
                Expanded(
                  child: Row(
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(width: 16),
                      Text(
                        '共 ${notifier.activeSongList.length} 首',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                // 排序按钮
                IconButton(
                  icon: const Icon(Icons.sort),
                  tooltip: '排序',
                  onPressed: () => _showSortDialog(context),
                ),
                // 搜索按钮
                IconButton(
                  icon: const Icon(Icons.search),
                  tooltip: '搜索',
                  onPressed: notifier.startSearch,
                ),
              ],
            ),
          ),
          const Expanded(child: SongListDetailWidget()),
          const Playbar(),
        ],
      ),
    );
  }
}

class SongListDetailWidget extends StatelessWidget {
  const SongListDetailWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<PlaylistContentNotifier>();
    final isSearching = notifier.isSearching;
    final title = notifier.activeDetailTitle;

    return Column(
      children: [
        if (isSearching)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              autofocus: true,
              decoration: InputDecoration(
                hintText: '在 "$title" 中搜索...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: notifier.stopSearch,
                ),
              ),
              onChanged: notifier.search,
            ),
          ),
        Expanded(
          child: Selector<PlaylistContentNotifier, List<Song>>(
            selector: (_, notifier) => notifier.isSearching
                ? notifier.filteredSongs
                : notifier.activeSongList,
            builder: (context, songs, _) {
              if (songs.isEmpty) {
                return Center(child: Text(isSearching ? '未找到匹配的歌曲' : '没有歌曲'));
              }

              return Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                child: ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  itemCount: songs.length,
                  onReorder: (oldIndex, newIndex) {
                    // 在搜索时，禁用拖拽排序功能
                    if (isSearching) return;

                    notifier.reorderActiveSongList(oldIndex, newIndex);
                  },
                  itemBuilder: (context, index) {
                    final song = songs[index];
                    return SongTileWidget(
                      key: ValueKey(song.filePath),
                      song: song,
                      index: index,
                      enableContextMenu: false, // 禁用右键菜单
                      contextPlaylist:
                          notifier.playingPlaylist ??
                          Playlist(id: 'dummy', name: 'dummy'),
                      onTap: () {
                        final listToPlay = isSearching
                            ? notifier.filteredSongs
                            : notifier.activeSongList;
                        final originalIndexInList = listToPlay.indexOf(song);

                        if (originalIndexInList != -1) {
                          notifier.playFromDynamicList(
                            listToPlay,
                            originalIndexInList,
                          );
                        }
                      },
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
