import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../page/playlist/playlist_content_notifier.dart';
import '../page/playlist/playlist_content_widget.dart';

class PlayingQueueDrawer extends StatelessWidget {
  const PlayingQueueDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<PlaylistContentNotifier>(
      builder: (context, notifier, child) {
        // 获取播放队列
        final queue = notifier.playingQueueSongs;
        final playingPlaylist = notifier.playingPlaylist;

        return Drawer(
          width: 400,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 抽屉的标题栏
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Text(
                        '正在播放 (${queue.length})',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                        tooltip: '关闭',
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),

                // 歌曲列表
                if (queue.isEmpty)
                  const Expanded(child: Center(child: Text('当前没有播放任何歌曲')))
                else
                  Expanded(
                    child: ListView.builder(
                      itemCount: queue.length,
                      itemBuilder: (context, index) {
                        final song = queue[index];

                        // 再次复用 SongTileWidget
                        return SongTileWidget(
                          key: ValueKey(song.filePath),
                          song: song,
                          index: index,
                          // 传入当前播放的歌单作为上下文
                          contextPlaylist: playingPlaylist!,
                          onTap: () {
                            // 检查当前是否在全部歌曲中播放
                            if (playingPlaylist.id ==
                                notifier.allSongsVirtualPlaylist.id) {
                              // 在 allSongs 列表中找到它的索引
                              final originalIndex = notifier.allSongs
                                  .indexWhere(
                                    (s) => s.filePath == song.filePath,
                                  );
                              if (originalIndex != -1) {
                                notifier.playSongFromAllSongs(originalIndex);
                              }
                            } else {
                              // 在普通歌单中找到它的索引
                              final originalIndex = playingPlaylist
                                  .songFilePaths
                                  .indexOf(song.filePath);
                              if (originalIndex != -1) {
                                notifier.playSongAtIndex(originalIndex);
                              }
                            }
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
