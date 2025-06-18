import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';

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
  OverlayEntry? _overlayEntry;
  bool _isHovering = false;
  double _lastVolume = 1.0;
  double _currentVolume = 1.0; // 用于存储当前音量状态

  final LayerLink _layerLink = LayerLink();

  @override
  void initState() {
    super.initState();
    _loadInitialVolume();
  }

  // 加载播放器初始音量
  Future<void> _loadInitialVolume() async {
    final currentVolume = widget.player.volume; // 直接访问 player.volume getter

    // 确保widget仍然挂载
    if (mounted) {
      setState(() {
        _currentVolume = currentVolume;
        _lastVolume = currentVolume > 0
            ? currentVolume
            : 1.0; // 避免0导致_lastVolume为0
      });
    }
  }

  void _showOverlay() {
    if (_overlayEntry != null) return;

    _overlayEntry = OverlayEntry(
      builder: (context) {
        return Positioned(
          left: 50,
          top: 100,
          child: CompositedTransformFollower(
            link: _layerLink,
            offset: const Offset(0, -170),
            child: MouseRegion(
              onEnter: (_) => _setHovering(true),
              onExit: (_) => _setHovering(false),
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  width: 40,
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 40,
                        height: 120,
                        child: RotatedBox(
                          quarterTurns: -1,
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
                              // 直接使用 _currentVolume 状态
                              value: _currentVolume,
                              min: 0,
                              max: 1,
                              onChanged: (value) {
                                // 直接更新播放器音量并更新本地状态
                                widget.player.setVolume(value);
                                setState(() {
                                  _currentVolume = value;
                                  if (value > 0) _lastVolume = value;
                                });
                                _overlayEntry?.markNeedsBuild();
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${(_currentVolume * 100).round()}%',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _setHovering(bool hovering) {
    setState(() {
      _isHovering = hovering;
    });

    // 悬停消失时，检查是否隐藏弹出层
    if (!hovering) {
      // 延迟一下避免鼠标移入弹出层瞬间消失
      Future.delayed(const Duration(milliseconds: 100), () {
        if (!_isHovering) {
          _removeOverlay();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 浮层的定位目标
    return CompositedTransformTarget(
      link: _layerLink,
      child: Listener(
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) {
            final dy = event.scrollDelta.dy;

            const double step = 0.03;
            final double newVolume = (_currentVolume + (dy > 0 ? -step : step))
                .clamp(0.0, 1.0);

            widget.player.setVolume(newVolume);
            setState(() {
              // 更新本地音量状态
              _currentVolume = newVolume;
              if (newVolume > 0) _lastVolume = newVolume;
            });
            _overlayEntry?.markNeedsBuild();
          }
        },
        child: MouseRegion(
          onEnter: (_) {
            _setHovering(true);
            _showOverlay();
          },
          onExit: (_) => _setHovering(false),
          child: IconButton(
            icon: Icon(
              _currentVolume < 0.001
                  ? Icons.volume_off
                  : (_currentVolume <= 0.5
                        ? Icons.volume_down
                        : Icons.volume_up),
              color: widget.iconColor.withAlpha(179),
              size: 24,
            ),
            onPressed: () {
              if (_currentVolume > 0.01) {
                // 如果当前音量不是静音
                _lastVolume = _currentVolume; // 保存当前音量
                widget.player.setVolume(0.0);
                setState(() {
                  // 更新本地状态为静音
                  _currentVolume = 0.0;
                });
              } else {
                // 如果当前是静音
                widget.player.setVolume(_lastVolume);
                setState(() {
                  // 恢复上次音量
                  _currentVolume = _lastVolume;
                });
              }
              _overlayEntry?.markNeedsBuild();
            },
          ),
        ),
      ),
    );
  }
}
