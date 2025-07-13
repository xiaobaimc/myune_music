import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../widgets/lyrics_widget.dart';
import 'playlist/playlist_content_notifier.dart';
import '../widgets/song_detali_page/palybar.dart';
import '../widgets/song_detali_page/app_window_title_bar.dart';
import './setting/settings_provider.dart';

// 公共模糊背景组件
class BackgroundBlurWidget extends StatelessWidget {
  final Widget child;
  const BackgroundBlurWidget({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Consumer<PlaylistContentNotifier>(
      builder: (context, playlistNotifier, child) {
        final currentSong = playlistNotifier.currentSong;
        final useBlurBackground = context
            .watch<SettingsProvider>()
            .useBlurBackground;

        // 当没有封面图或用户未启用模糊背景时，使用纯色背景
        if (currentSong?.albumArt == null || !useBlurBackground) {
          return Container(
            color: Theme.of(context).colorScheme.surface,
            child: child,
          );
        }

        // 使用封面图作为模糊背景
        return Stack(
          fit: StackFit.expand,
          children: [
            Image.memory(
              currentSong!.albumArt!,
              fit: BoxFit.cover, // 确保图片填充整个背景
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: Theme.of(context).colorScheme.surface, // 加载失败时使用纯色背景
                );
              },
            ),
            // BackdropFilter 应该在 Image 上方，并对其进行模糊
            Positioned.fill(
              // 使用 Positioned.fill 确保 BackdropFilter 填充整个 Stack
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                child: Container(
                  color: Theme.of(
                    context,
                  ).colorScheme.surface.withValues(alpha: 0.8),
                  child: child,
                ),
              ),
            ),
          ],
        );
      },
      child: child,
    );
  }
}

class SongDetailPage extends StatelessWidget {
  const SongDetailPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BackgroundBlurWidget(
        child: Column(
          children: [
            // 标题栏
            const AppWindowTitleBar(),
            Expanded(
              child: Row(
                children: [
                  const SizedBox(width: 80),
                  // 左侧歌曲信息和播放控制区域
                  Expanded(
                    flex: 2,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // 歌曲信息
                            Consumer<PlaylistContentNotifier>(
                              builder: (context, playlistNotifier, child) {
                                final currentSong =
                                    playlistNotifier.currentSong;

                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    const SizedBox(height: 70),
                                    // 歌曲标题
                                    Padding(
                                      padding: const EdgeInsets.only(left: 10),
                                      // 截取前15个字符，如果超出则添加省略号
                                      child: Text(
                                        (currentSong?.title ?? '未知歌曲').length >
                                                15
                                            ? '${(currentSong?.title ?? '未知歌曲').substring(0, 15)}...'
                                            : (currentSong?.title ?? '未知歌曲'),
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    // 艺术家
                                    Padding(
                                      padding: const EdgeInsets.only(left: 10),
                                      // 截取前15个字符，如果超出则添加省略号
                                      child: Text(
                                        (currentSong?.artist ?? '未知艺术家')
                                                    .length >
                                                15
                                            ? '${(currentSong?.artist ?? '未知艺术家').substring(0, 15)}...'
                                            : (currentSong?.artist ?? '未知艺术家'),
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    // 专辑封面
                                    Container(
                                      width: 300,
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
                                        child: AspectRatio(
                                          aspectRatio: 1,
                                          child:
                                              (currentSong?.albumArt != null &&
                                                  currentSong!
                                                      .albumArt!
                                                      .isNotEmpty)
                                              ? Image.memory(
                                                  currentSong.albumArt!,
                                                  fit: BoxFit.cover,
                                                  errorBuilder:
                                                      (
                                                        context,
                                                        error,
                                                        stackTrace,
                                                      ) {
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
                                                    color: Colors.black12,
                                                  ),
                                                ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    // 播放控制区域
                                    const Playbar(),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // 歌词区域
                  Expanded(
                    flex: 3,
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
                            final currentLyrics =
                                playlistNotifier.currentLyrics;
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
                              initialData:
                                  playlistNotifier.currentLyricLineIndex,
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
          ],
        ),
      ),
    );
  }
}
