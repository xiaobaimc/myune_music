import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../page/playlist/playlist_content_notifier.dart';
import 'volume_control_state.dart';
import '../page/song_detail_page.dart';
import 'balance_rate_control.dart';
import 'play_pause_button.dart';
import 'play_mode_button.dart';

// 格式化时间函数
String _formatDuration(Duration duration) {
  if (duration == Duration.zero) return '00:00';
  String twoDigits(int n) => n.toString().padLeft(2, '0');
  final minutes = twoDigits(duration.inMinutes.remainder(60));
  final seconds = twoDigits(duration.inSeconds.remainder(60));
  return "$minutes:$seconds";
}

class Playbar extends StatefulWidget {
  final bool disableTap;

  const Playbar({
    super.key,
    this.disableTap = false, // 默认不禁用点击
  });

  @override
  State<Playbar> createState() => _PlaybarState();
}

class _PlaybarState extends State<Playbar> {
  double _currentSliderValue = 0.0;
  bool _isDraggingSlider = false; // 判断用户是否正在拖动滑块

  Timer? _progressTimer; // 声明定时器，用于定期更新播放进度

  @override
  void initState() {
    super.initState();
    _startProgressTimer(); // 组件初始化时启动定时器
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  @override
  void dispose() {
    _progressTimer?.cancel(); // 在组件销毁时取消定时器
    super.dispose();
  }

  void _startProgressTimer() {
    _progressTimer?.cancel(); // 确保只有一个定时器在运行
    _progressTimer = Timer.periodic(const Duration(milliseconds: 200), (
      timer,
    ) async {
      // 检查组件是否仍然挂载在widget树上，避免在dispose后调用setState
      if (!mounted) return;

      final playlistNotifier = Provider.of<PlaylistContentNotifier>(
        context,
        listen: false,
      );
      final Player player = playlistNotifier.mediaPlayer;

      // 如果用户正在拖动滑块，则暂停自动更新，避免UI跳动
      if (!_isDraggingSlider) {
        // 获取当前播放位置和总时长
        final currentPosition = player.state.position;
        final totalDuration = player.state.duration;

        setState(() {
          // 根据当前位置和总时长计算滑块的值
          _currentSliderValue = totalDuration.inMilliseconds == 0
              ? 0.0
              : currentPosition.inMilliseconds / totalDuration.inMilliseconds;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    final Color onBarColor = colorScheme.onSurface;
    final Color accentColor = colorScheme.primary;

    // 获取屏幕宽度
    final screenWidth = MediaQuery.of(context).size.width;
    final isNarrowScreen = screenWidth < 700;

    // 顶级 Consumer，确保 Playbar 整体能响应 PlaylistContentNotifier 的变化
    return Consumer<PlaylistContentNotifier>(
      builder: (context, playlistNotifier, child) {
        final Player player = playlistNotifier.mediaPlayer;

        return Container(
          height: 70,
          color: colorScheme.surface,
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              // 左侧区
              Expanded(
                flex: 3,
                child: Consumer<PlaylistContentNotifier>(
                  builder: (context, playlistNotifier, child) {
                    final currentSong = playlistNotifier.currentSong;

                    return Row(
                      children: <Widget>[
                        // 专辑封面点击跳转歌曲详情页
                        FilledButton(
                          onPressed: (currentSong != null && !widget.disableTap)
                              ? () {
                                  // 如果有歌曲在播放且点击未被禁用，则执行跳转
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const SongDetailPage(),
                                    ),
                                  );
                                }
                              : null,
                          style: ButtonStyle(
                            fixedSize: WidgetStateProperty.all(
                              const Size(50, 50),
                            ),
                            backgroundColor: WidgetStateProperty.all(
                              colorScheme.surfaceContainerHighest,
                            ),
                            minimumSize: WidgetStateProperty.all(
                              const Size(50, 50),
                            ),
                            padding: WidgetStateProperty.all(
                              EdgeInsets.zero,
                            ), // 去除内边距
                            shape: WidgetStateProperty.all(
                              RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            elevation: WidgetStateProperty.all(0),
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child:
                                  (currentSong?.albumArt != null &&
                                      currentSong!.albumArt!.isNotEmpty)
                                  ? Image.memory(
                                      currentSong.albumArt!,
                                      fit: BoxFit.cover,
                                      width: 50,
                                      height: 50,
                                      errorBuilder:
                                          (context, error, stackTrace) {
                                            return Icon(
                                              Icons.music_note,
                                              color: onBarColor.withValues(
                                                alpha: 0.7,
                                              ),
                                              size: 30,
                                            );
                                          },
                                    )
                                  : Icon(
                                      Icons.music_note,
                                      color: onBarColor.withValues(alpha: 0.7),
                                      size: 30,
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // 歌曲标题和艺术家
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              Text(
                                currentSong?.title ?? '未知歌曲',
                                style: TextStyle(
                                  color: onBarColor,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                              Text(
                                currentSong?.artist ?? '未知歌手',
                                style: TextStyle(
                                  color: onBarColor.withValues(alpha: 0.7),
                                  fontSize: 13,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),

              // 中间区
              Expanded(
                flex: 4,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    // 播放进度条
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2.0,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6.0,
                        ),
                        overlayShape: SliderComponentShape.noOverlay,
                        activeTrackColor: accentColor,
                        inactiveTrackColor: onBarColor.withValues(alpha: 0.7),
                        thumbColor: accentColor,
                      ),
                      child: Slider(
                        value: _currentSliderValue,
                        min: 0.0,
                        max: 1.0,
                        onChanged: (double newValue) {
                          // 用户拖动时，只更新内部状态
                          setState(() {
                            _isDraggingSlider = true;
                            _currentSliderValue = newValue;
                          });
                        },
                        onChangeStart: (double startValue) {
                          _isDraggingSlider = true; // 开始拖动
                        },
                        onChangeEnd: (double endValue) async {
                          _isDraggingSlider = false; // 结束拖动

                          // 获取当前总时长，用于计算seek位置
                          final totalDuration = player.state.duration;

                          final seekPosition = Duration(
                            milliseconds:
                                (totalDuration.inMilliseconds * endValue)
                                    .round(),
                          );
                          player.seek(seekPosition); // 拖动结束后才实际 seek
                          playlistNotifier.smtcManager?.updateTimeline(
                            position: seekPosition,
                            duration: totalDuration,
                          );
                          // 拖动结束后，立即更新滑块到最终位置，即使定时器还未触发
                          setState(() {
                            _currentSliderValue =
                                totalDuration.inMilliseconds == 0
                                ? 0.0
                                : seekPosition.inMilliseconds /
                                      totalDuration.inMilliseconds;
                          });
                        },
                      ),
                    ),
                    // 播放控制按钮 (上一首、播放/暂停、下一首)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        // 上一首按钮
                        IconButton(
                          icon: Icon(
                            Icons.skip_previous,
                            color: onBarColor,
                            size: 28,
                          ),
                          // 只有当歌单有歌曲且不是第一首时才启用按钮
                          onPressed: playlistNotifier.playingPlaylist != null
                              ? () => playlistNotifier.playPrevious()
                              : null,
                        ),
                        // 播放/暂停按钮 (根据播放器状态动态更新)
                        StreamBuilder<bool>(
                          stream: player.stream.playing,
                          initialData: playlistNotifier.isPlaying,
                          builder: (context, snapshot) {
                            final isPlaying = snapshot.data ?? false;
                            return PlayPauseButton(
                              isPlaying: isPlaying,
                              color: accentColor,
                              onPressed: isPlaying
                                  ? playlistNotifier.pause
                                  : playlistNotifier.play,
                            );
                          },
                        ),
                        // 下一首按钮
                        IconButton(
                          icon: Icon(
                            Icons.skip_next,
                            color: onBarColor,
                            size: 28,
                          ),
                          onPressed:
                              playlistNotifier
                                      .currentPlaylistSongs
                                      .isNotEmpty &&
                                  !playlistNotifier
                                      .isLoadingSongs // 正在加载歌曲时禁用
                              ? () async {
                                  await playlistNotifier.playNext();
                                }
                              : null, // 如果禁用，则传入 null
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // 右侧区
              Expanded(
                flex: 3,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    // 播放时间显示 (当前时间 / 总时长)
                    StreamBuilder<Duration?>(
                      stream: player.stream.position, // 监听当前位置
                      initialData: playlistNotifier
                          .currentPosition, // 使用 Notifier 中的同步数据
                      builder: (context, positionSnapshot) {
                        final currentPosition =
                            positionSnapshot.data ?? Duration.zero;
                        return StreamBuilder<Duration?>(
                          stream: player.stream.duration, // 监听总时长
                          initialData: playlistNotifier
                              .totalDuration, // 使用 Notifier 中的同步数据
                          builder: (context, totalDurationSnapshot) {
                            final totalDuration =
                                totalDurationSnapshot.data ?? Duration.zero;
                            return Text(
                              '${_formatDuration(currentPosition)} / ${_formatDuration(totalDuration)}',
                              style: TextStyle(
                                color: onBarColor.withValues(alpha: 0.7),
                                fontSize: 12,
                              ),
                            );
                          },
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    // 随机播放/列表循环按钮 (根据 playMode 动态更新)
                    if (!isNarrowScreen) ...[
                      // 播放模式
                      Consumer<PlaylistContentNotifier>(
                        builder: (context, notifier, _) {
                          return PlayModeButton(
                            playMode: notifier.playMode,
                            color: onBarColor.withValues(alpha: 0.7),
                            activeColor: accentColor,
                            onPressed: () {
                              notifier.togglePlayMode();
                            },
                          );
                        },
                      ),
                      // 音量控制
                      VolumeControl(player: player, iconColor: onBarColor),
                      // // 平衡速率控制
                      BalanceRateControl(player: player, iconColor: onBarColor),
                      // 播放列表
                      IconButton(
                        icon: const Icon(Icons.lyrics_outlined),
                        iconSize: 23,
                        tooltip: '播放列表',
                        padding: const EdgeInsets.only(top: 1.5),
                        onPressed: () {
                          // 打开右侧抽屉
                          Scaffold.of(context).openEndDrawer();
                        },
                      ),
                    ],

                    // // 桌面歌词按钮
                    // IconButton(
                    //   icon: Icon(
                    //     Icons.queue_music,
                    //     color: onBarColor.withValues(alpha: 0.7),
                    //     size: 24,
                    //   ),
                    //   onPressed: () {
                    //     // TODO: 桌面歌词功能
                    //     // 使用desktop_multi_window或等待官方更新
                    //   },
                    // ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
