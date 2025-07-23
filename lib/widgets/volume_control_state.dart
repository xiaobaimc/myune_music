import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'hover_overlay_control.dart';

class VolumeControl extends StatefulWidget {
  final AudioPlayer player;
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
  double _lastVolume = 1.0;
  double _currentVolume = 1.0;

  @override
  void initState() {
    super.initState();
    _loadInitialVolume();
  }

  // 初始化音量，尝试从本地缓存读取
  Future<void> _loadInitialVolume() async {
    final prefs = await SharedPreferences.getInstance();
    final storedVolume =
        prefs.getDouble('player_volume') ?? widget.player.volume;
    await _updateVolume(storedVolume, save: false);
  }

  // 将当前音量保存到本地
  Future<void> _saveVolume(double volume) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('player_volume', volume);
  }

  // 更新播放器音量，可选是否保存
  Future<void> _updateVolume(double newVolume, {bool save = true}) async {
    await widget.player.setVolume(newVolume);
    if (mounted) {
      setState(() {
        _currentVolume = newVolume;
        if (newVolume > 0) _lastVolume = newVolume; // 非静音时更新上次音量
      });
    }
    if (save) {
      await _saveVolume(newVolume);
    }
  }

  // 点击图标时切换静音与恢复上次音量
  void _toggleMute() {
    final isMuted = _currentVolume < 0.001;
    final newVolume = isMuted ? _lastVolume : 0.0;
    _updateVolume(newVolume);
  }

  // 处理滚轮事件，增加/减少音量
  void _handleScroll(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      const double step = 0.03;
      final newVolume = (_currentVolume - event.scrollDelta.dy.sign * step)
          .clamp(0.0, 1.0);
      _updateVolume(newVolume);
    }
  }

  // 获取当前应显示的音量图标
  IconData get _volumeIcon {
    if (_currentVolume < 0.001) return Icons.volume_off;
    if (_currentVolume <= 0.5) return Icons.volume_down;
    return Icons.volume_up;
  }

  @override
  Widget build(BuildContext context) {
    return HoverOverlayControl(
      icon: _volumeIcon,
      iconColor: widget.iconColor,
      onIconPressed: _toggleMute,
      onPointerSignal: _handleScroll,
      overlayOffset: const Offset(0, -170),
      overlayConstraints: const BoxConstraints(maxWidth: 40),
      overlayContentBuilder: (context) {
        return _buildOverlayContent();
      },
    );
  }

  Widget _buildOverlayContent() {
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
                child: Slider(
                  value: _currentVolume,
                  min: 0,
                  max: 1,
                  onChanged: (value) {
                    _updateVolume(value);
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${(_currentVolume * 100).round()}%',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
