import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../playlist/playlist_content_widget.dart';
import '../playlist/playlist_content_notifier.dart';
import '../../widgets/single_line_lyrics.dart';
import '../playlist/sort_options.dart';
import '../../widgets/sort_dialog.dart';

class AllSongsPage extends StatelessWidget {
  const AllSongsPage({super.key});

  void _showSortDialog(BuildContext context) async {
    final notifier = context.read<PlaylistContentNotifier>();
    if (notifier.allSongs.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('没有歌曲可以排序')));
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
    final allSongs = notifier.allSongs;
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const SingleLineLyricView(
          maxLinesPerLyric: 2,
          textAlign: TextAlign.left,
          alignment: Alignment.topLeft,
        ),
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: Column(
        children: [
          const Divider(height: 1, thickness: 1),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '全部歌曲',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.sort),
                        tooltip: '排序歌曲',
                        onPressed: () => _showSortDialog(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: allSongs.isEmpty
                        ? const Center(child: Text('没有发现任何歌曲'))
                        : ReorderableListView.builder(
                            buildDefaultDragHandles: false,
                            proxyDecorator: (child, index, animation) =>
                                Material(
                                  elevation: 4,
                                  color: colorScheme.surface,
                                  borderRadius: BorderRadius.circular(8),
                                  child: child,
                                ),
                            itemCount: allSongs.length,
                            itemBuilder: (context, index) {
                              final song = allSongs[index];
                              return SongTileWidget(
                                key: ValueKey(song.filePath),
                                song: song,
                                index: index,
                                contextPlaylist:
                                    notifier.allSongsVirtualPlaylist,
                                onTap: () =>
                                    notifier.playSongFromAllSongs(index),
                              );
                            },
                            onReorder: (oldIndex, newIndex) {
                              notifier.reorderAllSongs(oldIndex, newIndex);
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
