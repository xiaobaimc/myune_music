import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:provider/provider.dart';
import '../page/playlist/playlist_content_notifier.dart';
import 'volume_control_state.dart';
import '../page/song_detail_page.dart';

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

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    final Color onBarColor = colorScheme.onSurface;
    final Color accentColor = colorScheme.primary;

    // 顶级 Consumer，确保 Playbar 整体能响应 PlaylistContentNotifier 的变化
    return Consumer<PlaylistContentNotifier>(
      builder: (context, playlistNotifier, child) {
        final AudioPlayer player = playlistNotifier.audioPlayer;

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
                        GestureDetector(
                          onTap: (currentSong != null && !widget.disableTap)
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
                          child: Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child:
                                (currentSong?.albumArt != null &&
                                    currentSong!.albumArt!.isNotEmpty)
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.memory(
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
                                    ),
                                  )
                                : Icon(
                                    Icons.music_note,
                                    color: onBarColor.withValues(alpha: 0.7),
                                    size: 30,
                                  ),
                          ),
                        ),
                        const SizedBox(width: 12),
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
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                              Text(
                                currentSong?.artist ?? '未知歌手',
                                style: TextStyle(
                                  color: onBarColor.withValues(alpha: 0.7),
                                  fontSize: 12,
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
                    // 嵌套 StreamBuilder 监听总时长和当前位置
                    StreamBuilder<Duration?>(
                      stream: player.onDurationChanged, // 监听歌曲总时长
                      initialData:
                          playlistNotifier.totalDuration, // 使用 Notifier 中的同步数据
                      builder: (context, totalDurationSnapshot) {
                        final totalDuration =
                            totalDurationSnapshot.data ?? Duration.zero;

                        return StreamBuilder<Duration>(
                          stream: player.onPositionChanged, // 监听当前播放位置
                          initialData: playlistNotifier
                              .currentPosition, // 使用 Notifier 中的同步数据
                          builder: (context, positionSnapshot) {
                            final currentPosition =
                                positionSnapshot.data ?? Duration.zero;

                            // 如果用户正在拖动，则不更新滑块值
                            if (!_isDraggingSlider) {
                              _currentSliderValue =
                                  totalDuration.inMilliseconds == 0
                                  ? 0.0
                                  : currentPosition.inMilliseconds /
                                        totalDuration.inMilliseconds;
                            }

                            return SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 2.0,
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 6.0,
                                ),
                                overlayShape: SliderComponentShape.noOverlay,
                                activeTrackColor: accentColor,
                                inactiveTrackColor: onBarColor.withValues(
                                  alpha: 0.7,
                                ),
                                thumbColor: accentColor,
                              ),
                              child: Slider(
                                value: _currentSliderValue,
                                min: 0.0,
                                max: 1.0,
                                onChanged: (double newValue) {
                                  // 只更新内部状态
                                  setState(() {
                                    _currentSliderValue = newValue;
                                  });
                                },
                                onChangeStart: (double startValue) {
                                  _isDraggingSlider = true; // 开始拖动
                                },
                                onChangeEnd: (double endValue) {
                                  _isDraggingSlider = false; // 结束拖动
                                  final seekPosition = Duration(
                                    milliseconds:
                                        (totalDuration.inMilliseconds *
                                                endValue)
                                            .round(),
                                  );
                                  player.seek(seekPosition); // 拖动结束后才实际 seek
                                },
                              ),
                            );
                          },
                        );
                      },
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
                          onPressed:
                              playlistNotifier
                                      .currentPlaylistSongs
                                      .isNotEmpty &&
                                  playlistNotifier.currentSongIndex > 0
                              ? () => playlistNotifier.playPrevious()
                              : null,
                        ),
                        // 播放/暂停按钮 (根据播放器状态动态更新)
                        StreamBuilder<PlayerState>(
                          stream: player.onPlayerStateChanged,
                          initialData: playlistNotifier
                              .playerState, // 使用 Notifier 中的同步状态
                          builder: (context, snapshot) {
                            final playerState = snapshot.data;
                            if (playerState == PlayerState.playing) {
                              return IconButton(
                                icon: Icon(
                                  Icons.pause,
                                  color: accentColor,
                                  size: 36,
                                ),
                                onPressed: playlistNotifier.pause,
                              );
                            } else {
                              // 当 playerState 不是 playing 时，统一显示播放按钮
                              return IconButton(
                                icon: Icon(
                                  Icons.play_arrow,
                                  color: accentColor,
                                  size: 36,
                                ),
                                onPressed: playlistNotifier.play,
                              );
                            }
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
                      stream: player.onPositionChanged, // 监听当前位置
                      initialData: playlistNotifier
                          .currentPosition, // 使用 Notifier 中的同步数据
                      builder: (context, positionSnapshot) {
                        final currentPosition =
                            positionSnapshot.data ?? Duration.zero;
                        return StreamBuilder<Duration?>(
                          stream: player.onDurationChanged, // 监听总时长
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
                    Consumer<PlaylistContentNotifier>(
                      builder: (context, notifier, _) {
                        // 根据播放模式选择图标和工具提示
                        IconData icon;
                        String tooltip;
                        Color iconColor = onBarColor.withValues(
                          alpha: 0.7,
                        ); // 默认颜色

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
                          icon: Icon(icon, color: iconColor),
                          onPressed: () {
                            notifier.togglePlayMode(); // 调用 notifier 中的方法改变模式
                          },
                        );
                      },
                    ),
                    // 音量控制
                    VolumeControl(player: player, iconColor: onBarColor),
                    // 桌面歌词按钮
                    IconButton(
                      icon: Icon(
                        Icons.queue_music,
                        color: onBarColor.withValues(alpha: 0.7),
                        size: 24,
                      ),
                      onPressed: () {
                        // TODO: 桌面歌词功能
                      },
                    ),
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
