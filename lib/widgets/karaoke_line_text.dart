import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../page/playlist/playlist_models.dart';

class KaraokeLineText extends StatefulWidget {
  const KaraokeLineText({
    super.key,
    required this.tokens,
    required this.baseStyle,
    required this.highlightStyle,
    required this.currentTime,
    required this.isPlaying,
    this.textAlign = TextAlign.center,
    this.highlightFactor = 1.0,
    this.enableFloating = true,
  });

  final List<LyricToken> tokens;

  final TextStyle baseStyle;
  final TextStyle highlightStyle;

  final Duration currentTime;
  final bool isPlaying;
  final TextAlign textAlign;

  final double highlightFactor;

  // 是否启用逐字上浮动效
  // 关闭时渲染路径与旧实现应该一致
  final bool enableFloating;

  @override
  State<KaraokeLineText> createState() => _KaraokeLineTextState();
}

class _TokenGeometry {
  const _TokenGeometry({
    required this.tokenIndex,
    required this.startCharIndex,
    required this.endCharIndex,
    required this.charLength,
    required this.startMs,
    required this.endMs,
    required this.boxes,
  });

  final int tokenIndex;
  final int startCharIndex;
  final int endCharIndex;
  final int charLength;
  final double startMs;
  final double endMs;
  final List<Rect> boxes;

  double get durationMs => endMs - startMs;
}

class _FillState {
  const _FillState({
    required this.beforeRows,
    required this.afterRows,
    required this.currentRow,
    required this.edgeX,
  });

  final List<Rect> beforeRows;
  final List<Rect> afterRows;
  final Rect? currentRow;
  final double edgeX;
}

class _KaraokeLineTextState extends State<KaraokeLineText>
    with SingleTickerProviderStateMixin {
  static const double _kFadeRatio = 0.16;

  // 主行上浮幅度：相对字号的比例，以及像素上下限
  static const double _kFloatDistanceRatio = 0.07;
  static const double _kFloatDistanceMin = 1.5;
  static const double _kFloatDistanceMax = 2.8;

  late final Ticker _ticker;
  final ValueNotifier<double> _timeMs = ValueNotifier<double>(0);

  Duration _lastAudioTime = Duration.zero;
  DateTime _lastAudioUpdate = DateTime.now();

  TextPainter? _measurer;
  String _layoutKey = '';
  List<_TokenGeometry> _geometries = const <_TokenGeometry>[];
  Size _paragraphSize = Size.zero;

  String get _fullText =>
      widget.tokens.map((LyricToken token) => token.text).join();

  double get _fadeWidth => (widget.baseStyle.fontSize ?? 16.0) * _kFadeRatio;

  @override
  void initState() {
    super.initState();
    _lastAudioTime = widget.currentTime;
    _lastAudioUpdate = DateTime.now();
    _timeMs.value = widget.currentTime.inMicroseconds / 1000.0;
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didUpdateWidget(covariant KaraokeLineText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentTime != widget.currentTime) {
      _lastAudioTime = widget.currentTime;
      _lastAudioUpdate = DateTime.now();
    }
    if (widget.isPlaying && !oldWidget.isPlaying) {
      // 从暂停恢复播放：以当前音频时间重新起算
      _lastAudioUpdate = DateTime.now();
    }
    if (oldWidget.baseStyle != widget.baseStyle ||
        oldWidget.textAlign != widget.textAlign ||
        !identical(oldWidget.tokens, widget.tokens)) {
      _layoutKey = ''; // 样式/文本变化，几何必须重算
    }
  }

  void _onTick(Duration _) {
    final Duration uiTime = widget.isPlaying
        ? _lastAudioTime + DateTime.now().difference(_lastAudioUpdate)
        : _lastAudioTime;
    _timeMs.value = uiTime.inMicroseconds / 1000.0;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _timeMs.dispose();
    _measurer?.dispose();
    super.dispose();
  }

  // 用与两层 Text 完全相同的样式/宽度/缩放/语言测量几何
  void _ensureGeometry({
    required double maxWidth,
    required TextStyle style,
    required TextScaler textScaler,
    required TextDirection textDirection,
    required Locale? locale,
    required TextHeightBehavior? textHeightBehavior,
    required TextWidthBasis textWidthBasis,
  }) {
    final String widthKey = maxWidth.isFinite
        ? maxWidth.toStringAsFixed(2)
        : 'inf';
    final String key =
        '${_fullText.hashCode}|$widthKey|${style.hashCode}'
        '|${textScaler.hashCode}|${textDirection.name}'
        '|${locale?.toLanguageTag() ?? ''}'
        '|${textHeightBehavior.hashCode}|${textWidthBasis.name}';
    if (key == _layoutKey && _measurer != null) {
      return;
    }
    _measurer?.dispose();
    final TextPainter painter = TextPainter(
      text: TextSpan(text: _fullText, style: style),
      textDirection: textDirection,
      textAlign: widget.textAlign,
      textScaler: textScaler,
      locale: locale,
      textHeightBehavior: textHeightBehavior,
      textWidthBasis: textWidthBasis,
    )..layout(minWidth: maxWidth.isFinite ? maxWidth : 0.0, maxWidth: maxWidth);
    _measurer = painter;
    _layoutKey = key;
    _paragraphSize = Size(painter.width, painter.height);

    final double width = maxWidth.isFinite ? maxWidth : _paragraphSize.width;
    final List<Rect> rows = _lineRects(painter, width);

    final List<LyricToken> tokens = widget.tokens;
    final List<_TokenGeometry> geometries = <_TokenGeometry>[];
    int charCursor = 0;
    for (int i = 0; i < tokens.length; i++) {
      final LyricToken token = tokens[i];
      final int len = token.text.length;
      final int startChar = charCursor;
      final int endChar = charCursor + len;
      charCursor = endChar;

      final double start = token.start.inMicroseconds / 1000.0;
      double end = token.end.inMicroseconds / 1000.0;
      if (end <= start) {
        final double? nextStart = i + 1 < tokens.length
            ? tokens[i + 1].start.inMicroseconds / 1000.0
            : null;
        end = (nextStart != null && nextStart > start) ? nextStart : start;
      }

      final List<Rect> rawBoxes = len > 0
          ? painter
                .getBoxesForSelection(
                  TextSelection(baseOffset: startChar, extentOffset: endChar),
                )
                .map((ui.TextBox b) => b.toRect())
                .toList()
          : const <Rect>[];

      // 将 rawBoxes 的上下边界校准为完整的行边界
      // 避免 getBoxesForSelection 只取字形 EM-Box 导致文字被裁切且相对容器偏上
      final List<Rect> fullRowBoxes = <Rect>[];
      for (final Rect box in rawBoxes) {
        final double midY = (box.top + box.bottom) / 2.0;
        final int rowIndex = _rowIndexAt(midY, rows);
        final Rect row = (rowIndex >= 0 && rowIndex < rows.length)
            ? rows[rowIndex]
            : Rect.fromLTWH(0, 0, width, _paragraphSize.height);
        fullRowBoxes.add(
          Rect.fromLTRB(box.left, row.top, box.right, row.bottom),
        );
      }

      geometries.add(
        _TokenGeometry(
          tokenIndex: i,
          startCharIndex: startChar,
          endCharIndex: endChar,
          charLength: len,
          startMs: start,
          endMs: end,
          boxes: fullRowBoxes,
        ),
      );
    }
    _geometries = geometries;
  }

  // 当前时间"已唱完多少个字符"
  double _sungCharsAt(double timeMs) {
    double chars = 0.0;
    for (final _TokenGeometry geometry in _geometries) {
      final double duration = geometry.durationMs;
      final double progress = duration <= 0
          ? (timeMs >= geometry.startMs ? 1.0 : 0.0)
          : ((timeMs - geometry.startMs) / duration).clamp(0.0, 1.0);
      chars += geometry.charLength * progress;
      if (progress < 1.0) {
        break;
      }
    }
    return chars;
  }

  // 行矩形：computeLineMetrics 的 height 是行高，逐行累加得到行顶
  List<Rect> _lineRects(TextPainter painter, double width) {
    final List<Rect> rows = <Rect>[];
    double top = 0.0;
    for (final ui.LineMetrics line in painter.computeLineMetrics()) {
      rows.add(Rect.fromLTWH(0, top, width, line.height));
      top += line.height;
    }
    return rows;
  }

  // y 落在第几行（行矩形是连续堆叠的，取最后一个 bottom 大于 y 的行）
  int _rowIndexAt(double y, List<Rect> rows) {
    for (int i = 0; i < rows.length; i++) {
      if (y < rows[i].bottom - 0.5) {
        return i;
      }
    }
    return rows.length - 1;
  }

  // 取某个字符在段落坐标系里的盒子
  ui.TextBox? _boxForChar(TextPainter painter, int index, int totalChars) {
    List<ui.TextBox> boxes = painter.getBoxesForSelection(
      TextSelection(baseOffset: index, extentOffset: index + 1),
    );
    if (boxes.isNotEmpty) {
      return boxes.first;
    }
    if (index + 2 <= totalChars) {
      boxes = painter.getBoxesForSelection(
        TextSelection(baseOffset: index, extentOffset: index + 2),
      );
      if (boxes.isNotEmpty) {
        return boxes.first;
      }
      boxes = painter.getBoxesForSelection(
        TextSelection(baseOffset: index + 1, extentOffset: index + 2),
      );
      if (boxes.isNotEmpty) {
        return boxes.first;
      }
    }
    return null;
  }

  // 按当前时间算出填充状态
  _FillState _fillStateAt(double timeMs) {
    final TextPainter? painter = _measurer;
    final double width = _paragraphSize.width;
    final double height = _paragraphSize.height;
    if (painter == null || width <= 0 || height <= 0) {
      return const _FillState(
        beforeRows: <Rect>[],
        afterRows: <Rect>[],
        currentRow: null,
        edgeX: 0,
      );
    }

    final Rect whole = Rect.fromLTWH(0, 0, width, height);
    final int totalChars = _fullText.length;
    final double sungChars = _sungCharsAt(timeMs);

    // 整行未唱 / 整行已唱
    if (sungChars <= 0.0) {
      return _FillState(
        beforeRows: const <Rect>[],
        afterRows: <Rect>[whole],
        currentRow: null,
        edgeX: 0,
      );
    }
    if (sungChars >= totalChars) {
      return _FillState(
        beforeRows: <Rect>[whole],
        afterRows: const <Rect>[],
        currentRow: null,
        edgeX: width,
      );
    }

    final List<Rect> rows = _lineRects(painter, width);
    if (rows.isEmpty) {
      return _FillState(
        beforeRows: <Rect>[whole],
        afterRows: const <Rect>[],
        currentRow: null,
        edgeX: width,
      );
    }

    final int lastCharIndex = totalChars - 1;
    final int caretIndex = sungChars.floor().clamp(0, lastCharIndex);
    final double fraction = (sungChars - caretIndex).clamp(0.0, 1.0);
    final ui.TextBox? edgeBox = _boxForChar(painter, caretIndex, totalChars);

    int currentLine = rows.length - 1;
    double edgeX = rows[currentLine].right;
    if (edgeBox != null) {
      final Rect boxRect = edgeBox.toRect();
      currentLine = _rowIndexAt((boxRect.top + boxRect.bottom) / 2.0, rows);
      edgeX = boxRect.left + boxRect.width * fraction;
    }
    final Rect row = rows[currentLine];
    edgeX = edgeX.clamp(row.left, row.right);

    return _FillState(
      beforeRows: rows.sublist(0, currentLine),
      afterRows: rows.sublist(currentLine + 1),
      currentRow: row,
      edgeX: edgeX,
    );
  }

  // 计算单个音节当前时刻的上浮位移
  double _calculateTokenFloatY({
    required _TokenGeometry geometry,
    required double timeMs,
    required double maxFloatDistance,
    required double highlightFactor,
  }) {
    if (maxFloatDistance <= 0.0 || highlightFactor <= 0.0) return 0.0;
    if (timeMs < geometry.startMs) return 0.0;

    final double durationMs = geometry.durationMs;
    final double riseDuration = math.max(1000.0, durationMs);

    final double elapsed = timeMs - geometry.startMs;
    final double progress = (elapsed / riseDuration).clamp(0.0, 1.0);

    // 柔
    const Curve floatCurve = Curves.easeOut;
    final double curveValue = floatCurve.transform(progress);

    // 基础向上浮动位移
    final double floatY = -maxFloatDistance * curveValue;

    return floatY * highlightFactor;
  }

  // 当前行的软边遮罩
  LinearGradient _edgeGradient({
    required Rect bounds,
    required double edgeX,
    required double fade,
    required bool highlightSide,
  }) {
    final double w = bounds.width <= 0.0 ? 1.0 : bounds.width;
    double a = ((edgeX - fade) / w).clamp(0.0, 1.0);
    final double b = ((edgeX + fade) / w).clamp(0.0, 1.0);
    if (b < a) {
      a = b;
    }
    return LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: highlightSide
          ? const <Color>[
              Colors.white,
              Colors.white,
              Colors.transparent,
              Colors.transparent,
            ]
          : const <Color>[
              Colors.transparent,
              Colors.transparent,
              Colors.white,
              Colors.white,
            ],
      stops: <double>[0.0, a, b, 1.0],
    );
  }

  @override
  Widget build(BuildContext context) {
    final String text = _fullText;
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : double.infinity;

        final DefaultTextStyle defaultTextStyle = DefaultTextStyle.of(context);
        TextStyle effectiveStyle = widget.baseStyle.inherit
            ? defaultTextStyle.style.merge(widget.baseStyle)
            : widget.baseStyle;
        if (MediaQuery.boldTextOf(context)) {
          effectiveStyle = effectiveStyle.merge(
            const TextStyle(fontWeight: FontWeight.bold),
          );
        }
        _ensureGeometry(
          maxWidth: maxWidth,
          style: effectiveStyle,
          textScaler: MediaQuery.textScalerOf(context),
          textDirection: Directionality.of(context),
          locale: Localizations.maybeLocaleOf(context),
          textHeightBehavior:
              defaultTextStyle.textHeightBehavior ??
              DefaultTextHeightBehavior.maybeOf(context),
          textWidthBasis: defaultTextStyle.textWidthBasis,
        );

        // 两层 Text：排版信息完全相同，只有颜色不同
        final Widget baseLayer = Text(
          text,
          style: widget.baseStyle,
          textAlign: widget.textAlign,
        );
        final Widget highlightLayer = Text(
          text,
          style: widget.highlightStyle,
          textAlign: widget.textAlign,
        );
        final double width = maxWidth.isFinite
            ? maxWidth
            : _paragraphSize.width;
        final double fade = _fadeWidth;

        // 主行逐字上浮幅度：约 0.095em
        final double fontSize = widget.baseStyle.fontSize ?? 24.0;
        final double maxFloatDistance = widget.enableFloating
            ? (fontSize * _kFloatDistanceRatio).clamp(
                _kFloatDistanceMin,
                _kFloatDistanceMax,
              )
            : 0.0;

        return SizedBox(
          width: width,
          height: _paragraphSize.height,
          child: ValueListenableBuilder<double>(
            valueListenable: _timeMs,
            builder: (BuildContext context, double timeMs, Widget? child) {
              final _FillState fill = _fillStateAt(timeMs);
              // 高亮因子同时缩放颜色与上浮位移：交接后从 1 平滑回到 0
              final double highlightFactor = widget.highlightFactor.clamp(
                0.0,
                1.0,
              );
              final double settledFloatY = -maxFloatDistance * highlightFactor;
              final List<Widget> layers = <Widget>[];

              if (!widget.enableFloating || _geometries.isEmpty) {
                // 未启用上浮动效时的兼容渲染路径
                if (fill.beforeRows.isNotEmpty) {
                  layers.add(
                    ClipPath(
                      clipper: _RectsClipper(fill.beforeRows),
                      child: highlightLayer,
                    ),
                  );
                }
                if (fill.afterRows.isNotEmpty) {
                  layers.add(
                    ClipPath(
                      clipper: _RectsClipper(fill.afterRows),
                      child: baseLayer,
                    ),
                  );
                }
                final Rect? currentRow = fill.currentRow;
                if (currentRow != null) {
                  final List<Rect> rowRects = <Rect>[currentRow];
                  layers.add(
                    ClipPath(
                      clipper: _RectsClipper(rowRects),
                      child: ShaderMask(
                        blendMode: BlendMode.dstIn,
                        shaderCallback: (Rect bounds) => _edgeGradient(
                          bounds: bounds,
                          edgeX: fill.edgeX,
                          fade: fade,
                          highlightSide: false,
                        ).createShader(bounds),
                        child: baseLayer,
                      ),
                    ),
                  );
                  layers.add(
                    ClipPath(
                      clipper: _RectsClipper(rowRects),
                      child: ShaderMask(
                        blendMode: BlendMode.dstIn,
                        shaderCallback: (Rect bounds) => _edgeGradient(
                          bounds: bounds,
                          edgeX: fill.edgeX,
                          fade: fade,
                          highlightSide: true,
                        ).createShader(bounds),
                        child: highlightLayer,
                      ),
                    ),
                  );
                }
              } else {
                // 上浮动效路径
                final List<Rect> unsungBoxes = <Rect>[];
                final List<Rect> settledBoxes = <Rect>[];
                final List<Widget> floatingWidgets = <Widget>[];

                for (final _TokenGeometry geom in _geometries) {
                  if (geom.boxes.isEmpty) continue;

                  final double startMs = geom.startMs;
                  final double endMs = geom.endMs;
                  final double durationMs = geom.durationMs;
                  final double riseDuration = math.max(850.0, durationMs);
                  final double riseEndMs = startMs + riseDuration;

                  if (timeMs < startMs) {
                    // 尚未唱到的音节：保持原位未高亮
                    unsungBoxes.addAll(geom.boxes);
                  } else if (timeMs >= riseEndMs && timeMs >= endMs) {
                    // 唱完且浮动到位沉淀的音节：统一归入沉淀高亮层
                    settledBoxes.addAll(geom.boxes);
                  } else {
                    // 正在演唱中，或正在向上浮动上升中的音节
                    final double tokenFloatY = _calculateTokenFloatY(
                      geometry: geom,
                      timeMs: timeMs,
                      maxFloatDistance: maxFloatDistance,
                      highlightFactor: highlightFactor,
                    );

                    final bool isWiping = timeMs < endMs;

                    if (isWiping) {
                      // 正在演唱中的音节：应用卡拉OK水平擦除过渡，同时整体上浮
                      floatingWidgets.add(
                        Transform.translate(
                          filterQuality: FilterQuality.low,
                          offset: Offset(0, tokenFloatY),
                          child: ClipPath(
                            clipper: _RectsClipper(geom.boxes),
                            child: Stack(
                              fit: StackFit.expand,
                              children: <Widget>[
                                ShaderMask(
                                  blendMode: BlendMode.dstIn,
                                  shaderCallback: (Rect bounds) =>
                                      _edgeGradient(
                                        bounds: bounds,
                                        edgeX: fill.edgeX,
                                        fade: fade,
                                        highlightSide: false,
                                      ).createShader(bounds),
                                  child: baseLayer,
                                ),
                                ShaderMask(
                                  blendMode: BlendMode.dstIn,
                                  shaderCallback: (Rect bounds) =>
                                      _edgeGradient(
                                        bounds: bounds,
                                        edgeX: fill.edgeX,
                                        fade: fade,
                                        highlightSide: true,
                                      ).createShader(bounds),
                                  child: highlightLayer,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    } else {
                      // 唱完了但还在平滑减速上升到位的音节：全高亮，随自身浮动位移上升
                      floatingWidgets.add(
                        Transform.translate(
                          filterQuality: FilterQuality.low,
                          offset: Offset(0, tokenFloatY),
                          child: ClipPath(
                            clipper: _RectsClipper(geom.boxes),
                            child: highlightLayer,
                          ),
                        ),
                      );
                    }
                  }
                }

                // 未唱到的音节层
                if (unsungBoxes.isNotEmpty) {
                  layers.add(
                    ClipPath(
                      clipper: _RectsClipper(unsungBoxes),
                      child: baseLayer,
                    ),
                  );
                }

                // 已唱完并沉淀的音节层
                if (settledBoxes.isNotEmpty) {
                  layers.add(
                    Transform.translate(
                      filterQuality: FilterQuality.low,
                      offset: Offset(0, settledFloatY),
                      child: ClipPath(
                        clipper: _RectsClipper(settledBoxes),
                        child: highlightLayer,
                      ),
                    ),
                  );
                }

                // 正在上浮及当前演唱的音节
                layers.addAll(floatingWidgets);
              }

              return Stack(
                fit: StackFit.expand,
                clipBehavior: Clip.none,
                children: layers,
              );
            },
          ),
        );
      },
    );
  }
}

// 把一组矩形并成一条裁剪路径
class _RectsClipper extends CustomClipper<Path> {
  _RectsClipper(this.rects);

  final List<Rect> rects;

  @override
  Path getClip(Size size) {
    final Path path = Path();
    for (final Rect rect in rects) {
      path.addRect(rect);
    }
    return path;
  }

  @override
  bool shouldReclip(_RectsClipper oldClipper) =>
      !listEquals(oldClipper.rects, rects);
}
