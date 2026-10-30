import 'package:flutter/painting.dart';

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
    sigma <= 0.5 ? 0.0 : (sigma - 0.5) / 0.57735;
