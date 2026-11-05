import 'package:flutter/widgets.dart';

// 0.5 以下的 sigma 无法用 blurRadius 表达（倒推半径会是负数）
// 这里统一折成 0，相当于给模糊留了一小段不可见区间
const double _kMinRepresentableSigma = 0.5;
const double _kRadiusToSigmaFactor = 0.57735;

const Duration kLyricBlurTransitionDuration = Duration(milliseconds: 240);

const Curve kLyricBlurTransitionCurve = Curves.easeOutCubic;

const double _kSigmaGridPerUnit = 20.0;

double quantizeLyricBlurSigma(double sigma) =>
    (sigma * _kSigmaGridPerUnit).roundToDouble() / _kSigmaGridPerUnit;

TextStyle buildLyricTextStyle({
  required Color lineColor,
  required double fontSize,
  required FontWeight fontWeight,
  required double blurSigma,
}) {
  final double radius = lyricShadowRadiusForSigma(blurSigma);
  if (radius > 0.0) {
    return TextStyle(
      fontSize: fontSize,
      height: 1.2,
      color: const Color(0x00000000),
      shadows: <Shadow>[Shadow(color: lineColor, blurRadius: radius)],
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

double lyricShadowRadiusForSigma(double sigma) =>
    sigma <= _kMinRepresentableSigma
    ? 0.0
    : (sigma - _kMinRepresentableSigma) / _kRadiusToSigmaFactor;

class AnimatedLyricBlur extends StatelessWidget {
  const AnimatedLyricBlur({
    super.key,
    required this.targetSigma,
    required this.builder,
    this.duration = kLyricBlurTransitionDuration,
    this.curve = kLyricBlurTransitionCurve,
  });

  final double targetSigma;

  /// 用当前显示中的 sigma 构建内容
  final Widget Function(double sigma) builder;

  final Duration duration;
  final Curve curve;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: targetSigma, end: targetSigma),
      duration: duration,
      curve: curve,
      builder: (BuildContext context, double sigma, Widget? _) =>
          builder(quantizeLyricBlurSigma(sigma)),
    );
  }
}
