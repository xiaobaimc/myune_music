import 'dart:ui' as ui;
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../widgets/lyrics_widget.dart';
import 'playlist/playlist_content_notifier.dart';
import '../widgets/song_detail_page/playbar.dart';
import '../widgets/song_detail_page/app_window_title_bar.dart';
import './setting/settings_provider.dart';
import '../widgets/playing_queue_drawer.dart';
import '../widgets/lyrics_settings_drawer.dart';

// 公共模糊背景组件
class BackgroundBlurWidget extends StatelessWidget {
  final Widget child;
  const BackgroundBlurWidget({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Consumer<PlaylistContentNotifier>(
      builder: (context, playlistNotifier, child) {
        final currentSong = playlistNotifier.currentSong;
        final settings = context.watch<SettingsProvider>();
        final useBlurBackground = settings.useBlurBackground;

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
    // 获取窗口宽高比
    final aspectRatio = MediaQuery.of(context).size.aspectRatio;
    final isPortrait = aspectRatio <= 1.0; // 竖屏判断

    return Scaffold(
      endDrawer: const PlayingQueueDrawer(),
      body: BackgroundBlurWidget(
        child: Column(
          children: [
            // 标题栏（保留）
            Builder(
              builder: (BuildContext context) {
                return AppWindowTitleBar(
                  onSettingsPressed: () {
                    Scaffold.of(context).openDrawer();
                  },
                );
              },
            ),
            // 主内容区域
            Expanded(
              child: isPortrait
                  ? // 竖屏：显示歌词和底部播放控制
                    Column(
                      children: [
                        // 歌词区域
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
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
                                    stream:
                                        playlistNotifier.lyricLineIndexStream,
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
                                          playlistNotifier.mediaPlayer.seek(
                                            seekTime,
                                          );
                                        },
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                        // 底部播放控制栏
                        const PortraitPlaybar(),
                      ],
                    )
                  : // 横屏：保留原有布局
                    Row(
                      children: [
                        const SizedBox(width: 80),
                        // 左侧歌曲信息和播放控制区域
                        Expanded(
                          flex: 2,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 10, bottom: 55),
                            child: Center(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  // 歌曲信息
                                  Consumer<PlaylistContentNotifier>(
                                    builder: (context, playlistNotifier, child) {
                                      final currentSong =
                                          playlistNotifier.currentSong;
                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          const SizedBox(height: 45),
                                          // 歌曲标题
                                          Text(
                                            currentSong?.title ?? '未知歌曲',
                                            style: const TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            textAlign: TextAlign.center,
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                            softWrap: false,
                                          ),
                                          // 艺术家
                                          Text(
                                            currentSong?.artist ?? '未知歌曲',
                                            style: const TextStyle(
                                              fontSize: 14,
                                              color: Colors.grey,
                                            ),
                                            textAlign: TextAlign.center,
                                            maxLines: 1,
                                            overflow: TextOverflow.clip,
                                            softWrap: false,
                                          ),
                                          const SizedBox(height: 6),
                                          // 专辑封面
                                          LayoutBuilder(
                                            builder: (context, constraints) {
                                              final w = constraints.maxWidth;
                                              // 按父容器宽度的60%计算封面大小，再限制在310~480像素之间，最后不超过父容器宽度
                                              final double size = min(
                                                w,
                                                ((w * 0.6)).clamp(310.0, 480.0),
                                              );

                                              final borderRadius =
                                                  BorderRadius.circular(12);
                                              const Widget fallback = Icon(
                                                Icons.music_note,
                                                size: 72,
                                                color: Colors.black12,
                                              );

                                              return SizedBox.square(
                                                dimension: size,
                                                child: DecoratedBox(
                                                  decoration: BoxDecoration(
                                                    borderRadius: borderRadius,
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: Colors.black
                                                            .withValues(
                                                              alpha: 0.3,
                                                            ),
                                                        blurRadius: 12,
                                                        offset: const Offset(
                                                          0,
                                                          2,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  child: ClipRRect(
                                                    borderRadius: borderRadius,
                                                    child: AspectRatio(
                                                      aspectRatio: 1,
                                                      child:
                                                          (currentSong?.albumArt !=
                                                                  null &&
                                                              currentSong!
                                                                  .albumArt!
                                                                  .isNotEmpty)
                                                          ? Image.memory(
                                                              currentSong
                                                                  .albumArt!,
                                                              fit: BoxFit.cover,
                                                              errorBuilder:
                                                                  (
                                                                    _,
                                                                    __,
                                                                    ___,
                                                                  ) => fallback,
                                                            )
                                                          : const ColoredBox(
                                                              color: Colors
                                                                  .black12,
                                                              child: Center(
                                                                child: fallback,
                                                              ),
                                                            ),
                                                    ),
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                          const SizedBox(height: 8),
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
                            padding: const EdgeInsets.only(
                              left: 80,
                              right: 80,
                              top: 20,
                              bottom: 40,
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
                                    stream:
                                        playlistNotifier.lyricLineIndexStream,
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
                                          playlistNotifier.mediaPlayer.seek(
                                            seekTime,
                                          );
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
      drawer: const LyricsSettingsDrawer(),
    );
  }
}
