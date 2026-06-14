import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import '../page/playlist/playlist_content_notifier.dart';
import 'hover_overlay_control.dart';

class VolumeControl extends StatefulWidget {
  final Player player;
  final Color iconColor;

  const VolumeControl({
    required this.player,
    required this.iconColor,
    super.key,
  });

  @override
  VolumeControlState createState() => VolumeControlState();
}

class VolumeControlState extends State<VolumeControl> {
  @override
  void initState() {
    super.initState();
  }

  // 处理滚轮事件，增加/减少音量
  void _handleScroll(
    PointerSignalEvent event,
    PlaylistContentNotifier playlistNotifier,
  ) {
    if (event is PointerScrollEvent) {
      const double step = 3.0;
      final newVolume =
          (playlistNotifier.volume - event.scrollDelta.dy.sign * step).clamp(
            0.0,
            100.0,
          );
      playlistNotifier.setVolume(newVolume);
    }
  }

  // 获取当前应显示的音量图标
  IconData _getVolumeIcon(double volume) {
    if (volume < 1.0) return Icons.volume_off;
    if (volume <= 50.0) {
      return Icons.volume_down;
    }
    return Icons.volume_up;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PlaylistContentNotifier>(
      builder: (context, playlistNotifier, child) {
        return HoverOverlayControl(
          icon: _getVolumeIcon(playlistNotifier.volume),
          iconColor: widget.iconColor,
          onIconPressed: playlistNotifier.toggleMute,
          onPointerSignal: (event) => _handleScroll(event, playlistNotifier),
          overlayOffset: const Offset(0, -170),
          overlayConstraints: const BoxConstraints(maxWidth: 40),
          overlayContentBuilder: (context) {
            return _buildOverlayContent(playlistNotifier);
          },
        );
      },
    );
  }

  Widget _buildOverlayContent(PlaylistContentNotifier playlistNotifier) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 40,
            height: 120,
            child: RotatedBox(
              quarterTurns: -1, // 横向滑块旋转成垂直显示
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 6,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 8,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 12,
                  ),
                ),
                child: Consumer<PlaylistContentNotifier>(
                  builder: (context, notifier, child) {
                    return Slider(
                      value: notifier.volume,
                      min: 0,
                      max: 100,
                      onChanged: (value) {
                        notifier.setVolume(value);
                      },
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Consumer<PlaylistContentNotifier>(
            builder: (context, notifier, child) {
              return Text(
                '${(notifier.volume).round()}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
