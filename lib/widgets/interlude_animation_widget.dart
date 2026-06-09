import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class InterludeAnimationWidget extends StatefulWidget {
  final bool isCurrent;
  final Color baseColor;
  final Color highlightColor;
  final Duration startTime;
  final Duration interludeDuration;
  final Duration currentTime;
  final bool isPlaying;

  const InterludeAnimationWidget({
    super.key,
    required this.isCurrent,
    required this.baseColor,
    required this.highlightColor,
    required this.startTime,
    required this.interludeDuration,
    required this.currentTime,
    required this.isPlaying,
  });

  @override
  State<InterludeAnimationWidget> createState() =>
      _InterludeAnimationWidgetState();
}

class _InterludeAnimationWidgetState extends State<InterludeAnimationWidget>
    with TickerProviderStateMixin {
  late AnimationController _breatheController;
  Ticker? _progressTicker;

  double _progress = 0.0;

  Duration _lastAudioTime = Duration.zero;
  DateTime? _lastAudioUpdateTime;
  Duration _uiTime = Duration.zero;

  @override
  void initState() {
    super.initState();
    _breatheController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _lastAudioTime = widget.currentTime;
    _lastAudioUpdateTime = DateTime.now();

    if (widget.isCurrent) {
      _breatheController.repeat(reverse: true);
      _startTicker();
    }
  }

  @override
  void didUpdateWidget(InterludeAnimationWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.currentTime != widget.currentTime) {
      _lastAudioTime = widget.currentTime;
      _lastAudioUpdateTime = DateTime.now();
    }

    if (oldWidget.isPlaying != widget.isPlaying) {
      if (widget.isPlaying) {
        _lastAudioUpdateTime = DateTime.now();
      }
    }

    if (widget.isCurrent && !oldWidget.isCurrent) {
      _breatheController.repeat(reverse: true);
      _startTicker();
    } else if (!widget.isCurrent && oldWidget.isCurrent) {
      _breatheController.stop();
      _breatheController.value = 0;
      _stopTicker();
      setState(() {
        _progress = 0.0;
      });
    }
  }

  void _startTicker() {
    _progressTicker?.stop();
    _progressTicker = createTicker((elapsed) {
      if (widget.isPlaying) {
        if (_lastAudioUpdateTime != null) {
          final now = DateTime.now();
          final timeSinceLastUpdate = now.difference(_lastAudioUpdateTime!);
          _uiTime = _lastAudioTime + timeSinceLastUpdate;
        }
      } else {
        _uiTime = _lastAudioTime;
      }

      double progress = 0.0;
      if (_uiTime >= widget.startTime) {
        final elapsedMs = (_uiTime - widget.startTime).inMilliseconds
            .toDouble();
        final totalMs = widget.interludeDuration.inMilliseconds.toDouble();
        if (totalMs > 0) {
          progress = (elapsedMs / totalMs).clamp(0.0, 1.0);
        }
      }
      //
      if (_progress != progress) {
        setState(() {
          _progress = progress;
        });
      }
    });
    _progressTicker!.start();
  }

  void _stopTicker() {
    _progressTicker?.stop();
    _progressTicker?.dispose();
    _progressTicker = null;
  }

  @override
  void dispose() {
    _breatheController.dispose();
    _stopTicker();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (index) {
        return AnimatedBuilder(
          animation: _breatheController,
          builder: (context, child) {
            // 三个点，计算每个点对应的进度区间
            final double dotStart = index / 3.0;
            final double dotEnd = (index + 1) / 3.0;

            double dotProgress = 0.0;
            if (_progress >= dotEnd) {
              dotProgress = 1.0;
            } else if (_progress > dotStart) {
              dotProgress = (_progress - dotStart) / (dotEnd - dotStart);
            }

            // 颜色混合
            final double easedProgress = Curves.easeInOut.transform(
              dotProgress,
            );
            final Color dotColor = Color.lerp(
              widget.baseColor,
              widget.highlightColor,
              easedProgress,
            )!;

            double scale = 0.8;

            final double breathe = _breatheController.value;

            // dotProgress=0 → amplitude=0.25（微弱）
            // dotProgress=0.5 → amplitude=0.45（最强，填充中）
            // dotProgress=1.0 → amplitude=0.15（安静）
            final double amplitude = dotProgress < 1.0
                ? lerpDouble(0.25, 0.45, dotProgress)!
                : 0.15;

            // 基础大小也随进度增长
            final double baseScale = lerpDouble(0.8, 1.0, dotProgress)!;

            scale = baseScale + amplitude * breathe;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6.0),
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          },
        );
      }),
    );
  }
}
