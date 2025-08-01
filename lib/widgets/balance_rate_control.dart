import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audioplayers/audioplayers.dart';
import '../page/playlist/playlist_content_notifier.dart';
import 'hover_overlay_control.dart';

class BalanceRateControl extends StatefulWidget {
  final AudioPlayer player;
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
  double _currentBalance = 0.0;
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

  // 加载初始声道均衡和播放倍速
  void _loadInitialValues() {
    setState(() {
      _currentBalance = _playlistNotifier.currentBalance;
      _currentRate = _playlistNotifier.currentPlaybackRate;
    });
  }

  // 提炼出处理声道变化的函数
  void _onBalanceChanged(double value, StateSetter setState) {
    setState(() {
      _currentBalance = value;
    });
    _playlistNotifier.setBalance(value);
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
            value: _currentBalance,
            min: -1.0,
            max: 1.0,
            divisions: 20,
            label:
                '左 ${((1 - _currentBalance) * 50).round()}%  右 ${((1 + _currentBalance) * 50).round()}%',
            onChanged: (value) => _onBalanceChanged(value, setState),
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
            if (icon == Icons.graphic_eq) // 特殊处理声道均衡的标签位置
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
