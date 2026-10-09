import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

class LyricLineBoxMetrics {
  const LyricLineBoxMetrics({
    required this.plainHeight,
    required this.plainBaseline,
    required this.widgetHeight,
    required this.visualBaseline,
  });

  final double plainHeight;
  final double plainBaseline;
  final double widgetHeight;
  final double visualBaseline;

  double get shift => plainBaseline - visualBaseline;

  bool get needsCompensation =>
      (widgetHeight - plainHeight).abs() > 0.01 || shift.abs() > 0.01;
}

LyricLineBoxMetrics measureLyricLineBox({
  required String plainText,
  required TextStyle style,
  required double maxWidth,
}) {
  final double width = maxWidth.isFinite ? maxWidth : double.infinity;

  final TextPainter plainPainter = TextPainter(
    text: TextSpan(text: plainText, style: style),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: width);
  final double plainHeight = plainPainter.height;
  final double plainBaseline = plainPainter.computeDistanceToActualBaseline(
    TextBaseline.alphabetic,
  );
  // 子控件是单行文本，高度就是行高
  // 折行文本的行高一致，所以用 总高 / 行数 即可
  final int lineCount = plainPainter.computeLineMetrics().length;
  final double childHeight = plainHeight / (lineCount < 1 ? 1 : lineCount);
  plainPainter.dispose();

  final TextPainter placeholderPainter =
      TextPainter(
        text: TextSpan(
          style: style,
          children: const <InlineSpan>[
            WidgetSpan(
              child: SizedBox.shrink(),
              alignment: PlaceholderAlignment.bottom,
            ),
          ],
        ),
        textDirection: TextDirection.ltr,
      )..setPlaceholderDimensions(<PlaceholderDimensions>[
        PlaceholderDimensions(
          size: Size(0, childHeight),
          alignment: ui.PlaceholderAlignment.bottom,
        ),
      ]);
  placeholderPainter.layout(maxWidth: width);
  final double widgetHeight = placeholderPainter.height;
  final List<ui.TextBox> boxes =
      placeholderPainter.inlinePlaceholderBoxes ?? const <ui.TextBox>[];
  // 占位盒里装的是和纯文本同款式的单行文本，所以它的基线就是纯文本首行基线
  final double visualBaseline = boxes.isEmpty
      ? plainBaseline
      : boxes.first.top + plainBaseline;
  placeholderPainter.dispose();

  return LyricLineBoxMetrics(
    plainHeight: plainHeight,
    plainBaseline: plainBaseline,
    widgetHeight: widgetHeight,
    visualBaseline: visualBaseline,
  );
}

const int _kLineBoxCacheLimit = 32;
final Map<String, LyricLineBoxMetrics> _lineBoxCache =
    <String, LyricLineBoxMetrics>{};

// measureLyricLineBox 的带缓存版本
LyricLineBoxMetrics cachedLyricLineBox({
  required String plainText,
  required TextStyle style,
  required double maxWidth,
}) {
  final String key =
      '${style.fontFamily}|${style.fontSize}|${style.fontWeight}|${style.fontStyle}'
      '|${style.height}|${style.leadingDistribution}|${style.fontFamilyFallback}'
      '|${maxWidth.toStringAsFixed(2)}|$plainText';
  final LyricLineBoxMetrics? cached = _lineBoxCache[key];
  if (cached != null) {
    return cached;
  }
  final LyricLineBoxMetrics value = measureLyricLineBox(
    plainText: plainText,
    style: style,
    maxWidth: maxWidth,
  );
  if (_lineBoxCache.length >= _kLineBoxCacheLimit) {
    _lineBoxCache.remove(_lineBoxCache.keys.first);
  }
  _lineBoxCache[key] = value;
  return value;
}

class LyricLineBox extends SingleChildRenderObjectWidget {
  const LyricLineBox({
    super.key,
    required this.height,
    required this.offsetY,
    required super.child,
  });

  final double height;

  final double offsetY;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderLyricLineBox(height: height, offsetY: offsetY);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    if (renderObject is! _RenderLyricLineBox) return;
    renderObject
      ..height = height
      ..offsetY = offsetY;
  }
}

class _RenderLyricLineBox extends RenderShiftedBox {
  _RenderLyricLineBox({required double height, required double offsetY})
    : _height = height,
      _offsetY = offsetY,
      super(null);

  double get height => _height;
  double _height;
  set height(double value) {
    if (_height == value) return;
    _height = value;
    markNeedsLayout();
  }

  double get offsetY => _offsetY;
  double _offsetY;
  set offsetY(double value) {
    if (_offsetY == value) return;
    _offsetY = value;
    markNeedsLayout();
  }

  BoxConstraints _childConstraints(BoxConstraints constraints) {
    return BoxConstraints(
      minWidth: constraints.minWidth,
      maxWidth: constraints.maxWidth,
      // 高度放开 让逐字段落按自己的自然高度排版
      minHeight: 0,
      maxHeight: double.infinity,
    );
  }

  @override
  void performLayout() {
    final BoxConstraints constraints = this.constraints;
    final RenderBox? child = this.child;
    if (child == null) {
      size = constraints.constrain(Size(constraints.minWidth, _height));
      return;
    }
    child.layout(_childConstraints(constraints), parentUsesSize: true);
    size = constraints.constrain(Size(child.size.width, _height));
    (child.parentData! as BoxParentData).offset = Offset(0, _offsetY);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final RenderBox? child = this.child;
    if (child == null) {
      return constraints.constrain(Size(constraints.minWidth, _height));
    }
    final Size childSize = child.getDryLayout(_childConstraints(constraints));
    return constraints.constrain(Size(childSize.width, _height));
  }
}
