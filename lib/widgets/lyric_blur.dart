import 'dart:async';

import 'package:flutter/widgets.dart';

const Duration kLyricBlurTransitionDuration = Duration(milliseconds: 240);

const Curve kLyricBlurTransitionCurve = Curves.easeOutCubic;

// 弹性滚动弹簧收敛更慢，用更长时长与缓入缓出曲线贴合波浪节奏
const Duration kElasticLyricBlurTransitionDuration = Duration(
  milliseconds: 400,
);

const Curve kElasticLyricBlurTransitionCurve = Curves.easeInOutCubic;

const double _kSigmaGridPerUnit = 20.0;
const int _kMaxBlurPaintCacheSize = 256;

final Map<(int, int), Paint> _blurPaintCache = <(int, int), Paint>{};

double quantizeLyricBlurSigma(double sigma) => sigma <= 0.0
    ? 0.0
    : (sigma * _kSigmaGridPerUnit).roundToDouble() / _kSigmaGridPerUnit;

Paint _cachedBlurPaint(Color color, double quantizedSigma) {
  final int sigmaBucket = (quantizedSigma * _kSigmaGridPerUnit).round();
  final (int, int) key = (color.toARGB32(), sigmaBucket);
  final Paint? existing = _blurPaintCache.remove(key);
  if (existing != null) {
    _blurPaintCache[key] = existing;
    return existing;
  }

  final Paint paint = Paint()
    ..color = color
    ..maskFilter = MaskFilter.blur(BlurStyle.normal, quantizedSigma);
  if (_blurPaintCache.length >= _kMaxBlurPaintCacheSize) {
    _blurPaintCache.remove(_blurPaintCache.keys.first);
  }
  _blurPaintCache[key] = paint;
  return paint;
}

TextStyle buildLyricTextStyle({
  required Color lineColor,
  required double fontSize,
  required FontWeight fontWeight,
  required double blurSigma,
}) {
  final double quantizedSigma = quantizeLyricBlurSigma(blurSigma);
  if (quantizedSigma > 0.0) {
    return TextStyle(
      fontSize: fontSize,
      height: 1.2,
      foreground: _cachedBlurPaint(lineColor, quantizedSigma),
      fontWeight: fontWeight,
    );
  }
  return TextStyle(
    fontSize: fontSize,
    height: 1.2,
    color: lineColor,
    fontWeight: fontWeight,
  );
}

class AnimatedLyricBlur extends StatefulWidget {
  const AnimatedLyricBlur({
    super.key,
    required this.targetSigma,
    required this.builder,
    this.duration = kLyricBlurTransitionDuration,
    this.curve = kLyricBlurTransitionCurve,
    this.delay = Duration.zero,
  });

  final double targetSigma;

  /// 用当前显示中的 sigma 构建内容
  final Widget Function(double sigma) builder;

  final Duration duration;
  final Curve curve;
  final Duration delay;

  @override
  State<AnimatedLyricBlur> createState() => _AnimatedLyricBlurState();
}

class _AnimatedLyricBlurState extends State<AnimatedLyricBlur> {
  late double _effectiveTargetSigma = widget.targetSigma;
  Timer? _delayTimer;

  @override
  void didUpdateWidget(covariant AnimatedLyricBlur oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.targetSigma == oldWidget.targetSigma) return;

    _delayTimer?.cancel();
    _delayTimer = null;

    if (widget.delay <= Duration.zero) {
      _effectiveTargetSigma = widget.targetSigma;
    } else {
      final double nextTarget = widget.targetSigma;
      _delayTimer = Timer(widget.delay, () {
        _delayTimer = null;
        if (!mounted) return;
        setState(() {
          _effectiveTargetSigma = nextTarget;
        });
      });
    }
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(
        begin: _effectiveTargetSigma,
        end: _effectiveTargetSigma,
      ),
      duration: widget.duration,
      curve: widget.curve,
      builder: (BuildContext context, double sigma, Widget? _) =>
          widget.builder(quantizeLyricBlurSigma(sigma)),
    );
  }
}
