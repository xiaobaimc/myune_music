import 'package:flutter/material.dart';

import '../theme/scroll_config.dart';

// 把懒加载列表中的特定条目滚动到可视区域的中间
Future<void> scrollToIndexInList({
  required ScrollController controller,
  required int index,
  required int itemCount,
  Duration duration = const Duration(milliseconds: 300),
  Curve curve = ScrollConfig.curve,
}) async {
  if (index < 0 || itemCount <= 0) return;
  if (controller.positions.isEmpty) return;

  final ScrollPosition position = controller.positions.first;
  if (!position.hasContentDimensions) return;

  final double maxScrollExtent = position.maxScrollExtent;
  final double viewportDimension = position.viewportDimension;

  // 内容不足以滚动时目标条目本来就可见，无需处理
  if (maxScrollExtent <= 0 || viewportDimension <= 0) return;

  final double itemExtent = (maxScrollExtent + viewportDimension) / itemCount;
  final double targetOffset =
      (index + 0.5) * itemExtent - viewportDimension / 2;
  final double offset = targetOffset.clamp(0.0, maxScrollExtent);

  if ((offset - position.pixels).abs() < 1.0) return;

  await controller.animateTo(offset, duration: duration, curve: curve);
}
