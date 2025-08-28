import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:media_kit/media_kit.dart';
import '../page/playlist/playlist_content_notifier.dart';
import 'hover_overlay_control.dart';

class BalanceRateControl extends StatefulWidget {
  final Player player;
  final Color iconColor;

  const BalanceRateControl({
    required this.player,
    required this.iconColor,
    super.key,
  });

  @override
  BalanceRateControlState createState() => BalanceRateControlState();
}

class BalanceRateControlState extends State<BalanceRateControl> {
  double _currentPitch = 1.0;
  double _currentRate = 1.0;

  late final PlaylistContentNotifier _playlistNotifier;

  @override
  void initState() {
    super.initState();
    // 使用 late final 在 initState 中初始化 Notifier
    _playlistNotifier = Provider.of<PlaylistContentNotifier>(
      context,
      listen: false,
    );
    _loadInitialValues();
  }

  // 加载初始音调和播放倍速
  void _loadInitialValues() {
    setState(() {
      _currentPitch = _playlistNotifier.currentPitch;
      _currentRate = _playlistNotifier.currentPlaybackRate;
    });
  }

  // 提炼出处理音调变化的函数
  void _onPitchChanged(double value, StateSetter setState) {
    setState(() {
      _currentPitch = value;
    });
    _playlistNotifier.setPitch(value);
  }

  // 提炼出处理倍速变化的函数
  void _onRateChanged(double value, StateSetter setState) {
    setState(() {
      _currentRate = value;
    });
    _playlistNotifier.setPlaybackRate(value);
  }

  @override
  Widget build(BuildContext context) {
    return HoverOverlayControl(
      icon: Icons.tune,
      iconColor: widget.iconColor,
      overlayOffset: const Offset(-200, -99),
      overlayContentBuilder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return _buildOverlayContent(setState);
          },
        );
      },
    );
  }

  // 浮层内容的构建逻辑
  Widget _buildOverlayContent(StateSetter setState) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSliderRow(
            icon: Icons.graphic_eq,
            value: _currentPitch,
            min: 0.5,
            max: 1.5,
            divisions: 20,
            label: '音调: ${_currentPitch.toStringAsFixed(1)}',
            onChanged: (value) => _onPitchChanged(value, setState),
          ),
          const SizedBox(height: 6),
          _buildSliderRow(
            icon: Icons.speed,
            value: _currentRate,
            min: 0.5,
            max: 2.0,
            divisions: 15,
            label: '${_currentRate.toStringAsFixed(1)}x',
            onChanged: (value) => _onRateChanged(value, setState),
          ),
        ],
      ),
    );
  }

  Widget _buildSliderRow({
    required IconData icon,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String label,
    required ValueChanged<double> onChanged,
  }) {
    // 确保滑块拖动时UI能实时更新
    return StatefulBuilder(
      builder: (context, setState) {
        return Column(
          children: [
            Row(
              children: [
                Icon(icon, color: widget.iconColor.withAlpha(179), size: 24),
                Expanded(
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
                      value: value,
                      min: min,
                      max: max,
                      divisions: divisions,
                      onChanged: (newValue) {
                        onChanged(newValue);
                        setState(() {});
                      },
                    ),
                  ),
                ),
                if (icon == Icons.speed) // 特殊处理倍速的标签位置
                  SizedBox(
                    width: 35,
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.end,
                    ),
                  ),
              ],
            ),
            if (icon == Icons.graphic_eq) // 特殊处理音调的标签位置
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        );
      },
    );
  }
}
