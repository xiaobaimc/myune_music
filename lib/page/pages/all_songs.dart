import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../playlist/playlist_models.dart';
import '../playlist/playlist_content_widget.dart';
import '../playlist/playlist_content_notifier.dart';
import '../../widgets/single_line_lyrics.dart';

class AllSongsPage extends StatelessWidget {
  const AllSongsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final allSongs = context.select<PlaylistContentNotifier, List<Song>>(
      (notifier) => notifier.allSongs,
    );
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
              padding: const EdgeInsets.all(16.0),
              child: allSongs.isEmpty
                  ? const Center(child: Text('没有发现任何歌曲'))
                  : ReorderableListView.builder(
                      buildDefaultDragHandles: false,
                      proxyDecorator: (child, index, animation) => Material(
                        elevation: 4,
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        child: child,
                      ),
                      itemCount: allSongs.length,
                      itemBuilder: (context, index) {
                        final song = allSongs[index];
                        final notifier = context
                            .read<PlaylistContentNotifier>();
                        return SongTileWidget(
                          key: ValueKey(song.filePath),
                          song: song,
                          index: index,
                          contextPlaylist: notifier.allSongsVirtualPlaylist,
                          onTap: () => notifier.playSongFromAllSongs(index),
                        );
                      },
                      // onReorder 回调
                      onReorder: (oldIndex, newIndex) {
                        context.read<PlaylistContentNotifier>().reorderAllSongs(
                          oldIndex,
                          newIndex,
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
