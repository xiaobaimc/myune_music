import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../../page/playlist/playlist_content_notifier.dart';
import '../volume_control_state.dart';
import '../balance_rate_control.dart';

// 格式化时间函数
String _formatDuration(Duration duration) {
  if (duration == Duration.zero) return '00:00';
  String twoDigits(int n) => n.toString().padLeft(2, '0');
  final minutes = twoDigits(duration.inMinutes.remainder(60));
  final seconds = twoDigits(duration.inSeconds.remainder(60));
  return "$minutes:$seconds";
}

class Playbar extends StatefulWidget {
  const Playbar({super.key});

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
      final AudioPlayer player = playlistNotifier.audioPlayer;

      // 如果用户正在拖动滑块，则暂停自动更新，避免UI跳动
      if (!_isDraggingSlider) {
        // 获取当前播放位置和总时长
        final currentPosition =
            await player.getCurrentPosition() ?? Duration.zero;
        final totalDuration = await player.getDuration() ?? Duration.zero;

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

    // 顶级 Consumer，确保 Playbar 整体能响应 PlaylistContentNotifier 的变化
    return Consumer<PlaylistContentNotifier>(
      builder: (context, playlistNotifier, child) {
        final AudioPlayer player = playlistNotifier.audioPlayer;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 播放时间显示
            StreamBuilder<Duration?>(
              stream: player.onPositionChanged, // 监听当前位置
              initialData:
                  playlistNotifier.currentPosition, // 使用 Notifier 中的同步数据
              builder: (context, positionSnapshot) {
                final currentPosition = positionSnapshot.data ?? Duration.zero;
                return StreamBuilder<Duration?>(
                  stream: player.onDurationChanged, // 监听总时长
                  initialData:
                      playlistNotifier.totalDuration, // 使用 Notifier 中的同步数据
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
            const SizedBox(height: 8),
            // 进度条
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
                  final totalDuration =
                      await player.getDuration() ?? Duration.zero;
                  final seekPosition = Duration(
                    milliseconds: (totalDuration.inMilliseconds * endValue)
                        .round(),
                  );
                  player.seek(seekPosition); // 拖动结束后才实际 seek
                  playlistNotifier.smtcManager?.updateTimeline(
                    position: seekPosition,
                    duration: totalDuration,
                  );
                  setState(() {
                    _currentSliderValue = totalDuration.inMilliseconds == 0
                        ? 0.0
                        : seekPosition.inMilliseconds /
                              totalDuration.inMilliseconds;
                  });
                },
              ),
            ),
            const SizedBox(height: 4),
            // 播放控制按钮
            Row(
              mainAxisAlignment:
                  MainAxisAlignment.spaceBetween, // 使左右两边的内容分别对齐到两端
              children: [
                // 左侧
                Row(
                  mainAxisSize: MainAxisSize.min, // 确保这个Row只占用必要的空间
                  children: [
                    // 上一首按钮
                    IconButton(
                      icon: Icon(
                        Icons.skip_previous,
                        color: onBarColor,
                        size: 28,
                      ),
                      onPressed: playlistNotifier.playingPlaylist != null
                          ? () => playlistNotifier.playPrevious()
                          : null,
                    ),
                    // 播放/暂停按钮
                    StreamBuilder<PlayerState>(
                      stream: player.onPlayerStateChanged,
                      initialData: playlistNotifier.playerState,
                      builder: (context, snapshot) {
                        final playerState = snapshot.data;
                        return IconButton(
                          icon: Icon(
                            playerState == PlayerState.playing
                                ? Icons.pause
                                : Icons.play_arrow,
                            color: accentColor,
                            size: 36,
                          ),
                          onPressed: playerState == PlayerState.playing
                              ? playlistNotifier.pause
                              : playlistNotifier.play,
                        );
                      },
                    ),
                    // 下一首按钮
                    IconButton(
                      icon: Icon(Icons.skip_next, color: onBarColor, size: 28),
                      onPressed:
                          playlistNotifier.currentPlaylistSongs.isNotEmpty &&
                              !playlistNotifier.isLoadingSongs
                          ? () => playlistNotifier.playNext()
                          : null,
                    ),
                  ],
                ),
                // 右侧
                Row(
                  mainAxisSize: MainAxisSize.min, // 确保这个Row只占用必要的空间
                  children: [
                    // 随机播放按钮 (现在放在右侧功能键组)
                    Consumer<PlaylistContentNotifier>(
                      builder: (context, notifier, _) {
                        IconData icon;
                        String tooltip;
                        Color iconColor = onBarColor.withValues(alpha: 0.7);
                        if (notifier.playMode == PlayMode.shuffle) {
                          icon = Icons.shuffle;
                          tooltip = '随机播放';
                          iconColor = accentColor;
                        } else if (notifier.playMode == PlayMode.repeatOne) {
                          icon = Icons.repeat_one;
                          tooltip = '单曲循环';
                          iconColor = accentColor;
                        } else {
                          icon = Icons.repeat;
                          tooltip = '列表循环';
                        }
                        return IconButton(
                          tooltip: tooltip,
                          icon: Icon(icon, color: iconColor, size: 24),
                          onPressed: () => notifier.togglePlayMode(),
                        );
                      },
                    ),
                    // 音量控制
                    VolumeControl(player: player, iconColor: onBarColor),
                    // 声道平衡、倍速控制
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
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}