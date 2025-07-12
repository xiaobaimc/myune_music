import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../widgets/lyrics_widget.dart';
import 'playlist/playlist_content_notifier.dart';
import '../widgets/playbar.dart';
import '../widgets/app_window_title_bar.dart';
import './setting/settings_provider.dart';

class SongDetailPage extends StatelessWidget {
  const SongDetailPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const AppWindowTitleBar(),
          Expanded(
            child: Row(
              children: [
                const SizedBox(width: 80),
                // 左侧歌曲信息区域
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 使用 Consumer 获取 currentSong
                      Consumer<PlaylistContentNotifier>(
                        builder: (context, playlistNotifier, child) {
                          final currentSong = playlistNotifier.currentSong;

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 70),
                              Padding(
                                padding: const EdgeInsets.only(left: 10),
                                child: Text(
                                  // 截取前15个字符，如果超出则添加省略号
                                  (currentSong?.title ?? '未知歌曲').length > 15
                                      ? '${(currentSong?.title ?? '未知歌曲').substring(0, 15)}...'
                                      : (currentSong?.title ?? '未知歌曲'),
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Padding(
                                padding: const EdgeInsets.only(left: 10),
                                child: Text(
                                  // 截取前15个字符，如果超出则添加省略号
                                  (currentSong?.artist ?? '未知艺术家').length > 15
                                      ? '${(currentSong?.artist ?? '未知艺术家').substring(0, 15)}...'
                                      : (currentSong?.artist ?? '未知艺术家'),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 5),
                              Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.3,
                                      ),
                                      blurRadius: 12,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(20),
                                  child: SizedBox(
                                    width: 300,
                                    height: 300,
                                    // 根据 currentSong.albumArt 判断显示专辑封面还是默认图标
                                    child:
                                        (currentSong?.albumArt != null &&
                                            currentSong!.albumArt!.isNotEmpty)
                                        ? Image.memory(
                                            currentSong.albumArt!,
                                            fit: BoxFit.cover,
                                            errorBuilder:
                                                (context, error, stackTrace) {
                                                  return const Icon(
                                                    Icons.music_note,
                                                    size: 72,
                                                    color: Colors.black12,
                                                  );
                                                },
                                          )
                                        : Container(
                                            // 没有封面图片时，显示一个带有音乐图标的占位符
                                            color: Colors.black12,
                                            child: const Icon(
                                              Icons.music_note,
                                              size: 72,
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
                // 歌词区域
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 80,
                      vertical: 10,
                    ),
                    child: Center(
                      child: Builder(
                        builder: (context) {
                          final playlistNotifier = context
                              .watch<PlaylistContentNotifier>();
                          final currentLyrics = playlistNotifier.currentLyrics;
                          if (currentLyrics.isEmpty) {
                            return const Center(
                              child: Text(
                                '无歌词数据',
                                style: TextStyle(
                                  fontSize: 20,
                                  color: Colors.grey,
                                ),
                              ),
                            );
                          }
                          return StreamBuilder<int>(
                            stream: playlistNotifier.lyricLineIndexStream,
                            initialData: playlistNotifier.currentLyricLineIndex,
                            builder: (context, snapshot) {
                              return LyricsView(
                                maxLinesPerLyric: context
                                    .watch<SettingsProvider>()
                                    .maxLinesPerLyric,
                                onTapLine: (index) {
                                  final seekTime =
                                      currentLyrics[index].timestamp;
                                  playlistNotifier.audioPlayer.seek(seekTime);
                                },
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Playbar(disableTap: true),
        ],
      ),
    );
  }
}
