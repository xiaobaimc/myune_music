import 'package:flutter/widgets.dart';

// 把一个逻辑长度吸附到物理像素栅格上
double snapToDevicePixel(BuildContext context, double logicalLength) {
  final double devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
  if (devicePixelRatio <= 0) {
    return logicalLength;
  }
  return (logicalLength * devicePixelRatio).roundToDouble() / devicePixelRatio;
}
