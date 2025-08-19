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
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: ListView.builder(
                        itemCount: queue.length,
                        itemBuilder: (context, index) {
                          final song = queue[index];

                          // 再次复用 SongTileWidget
                          return SongTileWidget(
                            key: ValueKey(song.filePath),
                            song: song,
                            index: index,
                            enableContextMenu: false, // 禁用右键菜单
                            // 传入当前播放的歌单作为上下文
                            contextPlaylist: playingPlaylist!,
                            onTap: () {
                              // 这里的index正好就是歌曲在队列中的索引
                              notifier.playSongFromQueue(index);
                            },
                          );
                        },
                      ),
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
