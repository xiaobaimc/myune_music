import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audioplayers/audioplayers.dart';
import '../page/playlist/playlist_content_notifier.dart';

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
  OverlayEntry? _overlayEntry;
  bool _isHovering = false;
  double _currentBalance = 0.0; // 声道均衡：-1.0 到 1.0
  double _currentRate = 1.0; // 播放倍速：0.5 到 2.0

  final LayerLink _layerLink = LayerLink();

  @override
  void initState() {
    super.initState();
    _loadInitialValues();
  }

  // 加载初始声道均衡和播放倍速
  void _loadInitialValues() {
    final playlistNotifier = Provider.of<PlaylistContentNotifier>(
      context,
      listen: false,
    );

    if (mounted) {
      setState(() {
        _currentBalance = playlistNotifier.currentBalance;
        _currentRate = playlistNotifier.currentPlaybackRate;
      });
    }
  }

  void _showOverlay() {
    if (_overlayEntry != null) return;

    _overlayEntry = OverlayEntry(
      builder: (context) {
        return CompositedTransformFollower(
          link: _layerLink,
          offset: const Offset(-200, -110),
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: MouseRegion(
                onEnter: (_) => _setHovering(true),
                onExit: (_) => _setHovering(false),
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 12,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min, // 确保 Column 垂直方向最小化
                      children: [
                        // 声道均衡滑块
                        Row(
                          mainAxisSize: MainAxisSize.max,
                          children: [
                            Icon(
                              Icons.graphic_eq,
                              color: widget.iconColor.withAlpha(179),
                              size: 24,
                            ),
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
                                  value: _currentBalance,
                                  min: -1.0,
                                  max: 1.0,
                                  divisions: 20,
                                  onChanged: (value) {
                                    final playlistNotifier =
                                        Provider.of<PlaylistContentNotifier>(
                                          context,
                                          listen: false,
                                        );
                                    setState(() {
                                      _currentBalance = value;
                                    });
                                    playlistNotifier.setBalance(value);
                                    _overlayEntry?.markNeedsBuild();
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '左 ${((1 - _currentBalance) * 50).round()}%  右 ${((1 + _currentBalance) * 50).round()}%',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 6),
                        // 播放倍速滑块
                        Row(
                          mainAxisSize: MainAxisSize.max,
                          children: [
                            Icon(
                              Icons.speed,
                              color: widget.iconColor.withAlpha(179),
                              size: 24,
                            ),
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
                                  value: _currentRate,
                                  min: 0.5,
                                  max: 2.0,
                                  divisions: 15,
                                  onChanged: (value) {
                                    final playlistNotifier =
                                        Provider.of<PlaylistContentNotifier>(
                                          context,
                                          listen: false,
                                        );
                                    setState(() {
                                      _currentRate = value;
                                    });
                                    playlistNotifier.setPlaybackRate(value);
                                    _overlayEntry?.markNeedsBuild();
                                  },
                                ),
                              ),
                            ),
                            Text(
                              '${_currentRate.toStringAsFixed(1)}x',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
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

    if (!hovering) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (!_isHovering) {
          _removeOverlay();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: MouseRegion(
        onEnter: (_) {
          _setHovering(true);
          _showOverlay();
        },
        onExit: (_) => _setHovering(false),
        child: IconButton(
          icon: Icon(
            Icons.tune,
            color: widget.iconColor.withAlpha(179),
            size: 24,
          ),
          onPressed: () {
            if (_overlayEntry == null) {
              _showOverlay();
            } else {
              _removeOverlay();
            }
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }
}
