import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../page/playlist/playlist_models.dart';

@immutable
class LyricGlowStyle {
  const LyricGlowStyle({
    required this.color,
    this.peakAlpha = 0.45,
    this.radiusEm = 0.15,
    this.haloEm = 0.0,
  });

  final Color color;

  final double peakAlpha;

  final double radiusEm;

  final double haloEm;

  bool get isVisible => peakAlpha > 0.0 && radiusEm > 0.0;

  @override
  bool operator ==(Object other) =>
      other is LyricGlowStyle &&
      other.color == color &&
      other.peakAlpha == peakAlpha &&
      other.radiusEm == radiusEm &&
      other.haloEm == haloEm;

  @override
  int get hashCode => Object.hash(color, peakAlpha, radiusEm, haloEm);
}

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
    this.glow,
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

  // 长音节辉光；null 表示不发光
  final LyricGlowStyle? glow;

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
    required this.charBoxes,
    required this.dampedEmphasis,
  });

  final int tokenIndex;
  final int startCharIndex;
  final int endCharIndex;
  final int charLength;
  final double startMs;
  final double endMs;
  final List<Rect> boxes;

  // 长音节按字拆出的几何；空表示该 token 不参与强调动画
  final List<_CharGeometry> charBoxes;

  // CJK 用更克制的缩放幅度
  final bool dampedEmphasis;

  double get durationMs => endMs - startMs;
}

// 单个字符在段落坐标系中的位置（可能跨行，因此是列表）
class _CharGeometry {
  _CharGeometry({
    required this.charIndex,
    required this.text,
    required this.boxes,
  });

  final int charIndex;
  final String text;
  final List<Rect> boxes;

  // 只画阴影的段落，布局期构建一次；每帧只改图层 alpha
  TextPainter? glowPainter;
  Offset glowOrigin = Offset.zero;
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
  static const double _kFloatDistanceRatio = 0.075;
  static const double _kFloatDistanceMin = 1.8;
  static const double _kFloatDistanceMax = 3.5;

  // 长音节强调
  static const double _kEmphasisMinTokenMs = 1000.0;

  // 非 CJK 词的最大字数
  static const int _kEmphasisMaxWordChars = 7;

  // 错峰：整个词分摊 du / 2.5 的起步偏移
  static const double _kEmphasisStaggerSpan = 1.8;

  // 峰值时的形变量（相对字号 / 相对时长）
  static const double _kEmphasisScaleAmount = 0.1;

  // CJK 只保留最后一个字，且缩放减半，整体更克制
  static const double _kCjkScaleAmount = 0.05;
  static const double _kEmphasisPushEm = 0.045;
  static const double _kEmphasisLiftEm = 0.025;

  static const Curve _kEmphasisRise = Cubic(0.2, 0.4, 0.58, 1.0);
  static const Curve _kEmphasisFall = Cubic(0.3, 0.0, 0.58, 1.0);

  static const double _kGlowRadiusToSigma = 0.866;

  // 低于该强度的字不进入光晕层，避免每帧空转
  static const double _kGlowMinAlpha = 0.01;

  static const double _kGlowFadeScale = 1.8;

  late final Ticker _ticker;
  final ValueNotifier<double> _timeMs = ValueNotifier<double>(0);

  Duration _lastAudioTime = Duration.zero;
  DateTime _lastAudioUpdate = DateTime.now();

  TextPainter? _measurer;
  String _layoutKey = '';
  List<_TokenGeometry> _geometries = const <_TokenGeometry>[];
  Size _paragraphSize = Size.zero;

  // 逐字光晕段落，随几何一起重建/释放
  final List<TextPainter> _glowPainters = <TextPainter>[];

  String get _fullText =>
      widget.tokens.map((LyricToken token) => token.text).join();

  double get _fadeWidth => (widget.baseStyle.fontSize ?? 16.0) * _kFadeRatio;

  double get _emphasisFontSize => widget.baseStyle.fontSize ?? 24.0;

  LyricGlowStyle? get _glow {
    final LyricGlowStyle? style = widget.glow;
    if (style == null || !style.isVisible) return null;
    return style;
  }

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
    _disposeGlowPainters();
    super.dispose();
  }

  void _disposeGlowPainters() {
    for (final TextPainter painter in _glowPainters) {
      painter.dispose();
    }
    _glowPainters.clear();
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
    required double fontSize,
  }) {
    final String widthKey = maxWidth.isFinite
        ? maxWidth.toStringAsFixed(2)
        : 'inf';
    final String key =
        '${_fullText.hashCode}|$widthKey|${style.hashCode}'
        '|${textScaler.hashCode}|${textDirection.name}'
        '|${locale?.toLanguageTag() ?? ''}'
        '|${textHeightBehavior.hashCode}|${textWidthBasis.name}'
        '|${_glow?.hashCode ?? 0}|$fontSize';
    if (key == _layoutKey && _measurer != null) {
      return;
    }
    _measurer?.dispose();
    _disposeGlowPainters();
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

    // 纯 CJK 歌词只在整行最后一个 CJK 字上做强调，其余直接跳过
    int lastCjkToken = -1;
    for (int i = tokens.length - 1; i >= 0; i--) {
      if (_isPureCjk(tokens[i].text)) {
        lastCjkToken = i;
        break;
      }
    }

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

      final List<Rect> fullRowBoxes = len > 0
          ? _rowAdjustedBoxes(painter, startChar, endChar, rows, width)
          : const <Rect>[];

      // 纯 CJK 只在最后一个字强调；其它语言要求是"短词"（≤7 字）的长音节
      final bool isCjk = _isPureCjk(token.text);
      final bool emphasize =
          (end - start) >= _kEmphasisMinTokenMs &&
          len > 0 &&
          (!isCjk || i == lastCjkToken) &&
          (isCjk || token.text.trim().length <= _kEmphasisMaxWordChars);

      // 长音节：逐字拆几何，供强调动画单独缩放/位移
      final List<_CharGeometry> charBoxes = emphasize
          ? _buildCharBoxes(
              painter,
              startChar,
              endChar,
              token.text,
              rows,
              width,
            )
          : const <_CharGeometry>[];

      if (charBoxes.isNotEmpty && _glow != null) {
        _attachGlowPainters(
          charBoxes: charBoxes,
          style: style,
          textScaler: textScaler,
          textDirection: textDirection,
          locale: locale,
          textHeightBehavior: textHeightBehavior,
          textWidthBasis: textWidthBasis,
          fontSize: fontSize,
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
          charBoxes: charBoxes,
          dampedEmphasis: isCjk,
        ),
      );
    }
    _geometries = geometries;
  }

  // 纯 CJK 歌词通常一个字一个 token
  // 单字做强调不好看，所以只保留整行最后一个字且幅度更低
  static bool _isPureCjk(String text) {
    final String trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    for (final int rune in trimmed.runes) {
      if (!_isCjkRune(rune)) return false;
    }
    return true;
  }

  static bool _isCjkRune(int rune) {
    return (rune >= 0x3040 && rune <= 0x30FF) || // 平假名 / 片假名
        (rune >= 0x31F0 && rune <= 0x31FF) || // 片假名扩展
        (rune >= 0x3400 && rune <= 0x4DBF) || // 汉字扩展 A
        (rune >= 0x4E00 && rune <= 0x9FFF) || // 汉字基本区
        (rune >= 0xF900 && rune <= 0xFAFF) || // 兼容汉字
        (rune >= 0xFF66 && rune <= 0xFF9F) || // 半角片假名
        (rune >= 0x1100 && rune <= 0x11FF) || // 韩文字母
        (rune >= 0xAC00 && rune <= 0xD7AF) || // 韩文音节
        (rune >= 0x20000 && rune <= 0x2FA1F); // 汉字扩展 B 及以后
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

  List<Rect> _rowAdjustedBoxes(
    TextPainter painter,
    int startChar,
    int endChar,
    List<Rect> rows,
    double width,
  ) {
    if (endChar <= startChar) return const <Rect>[];
    final List<Rect> boxes = <Rect>[];
    for (final ui.TextBox box in painter.getBoxesForSelection(
      TextSelection(baseOffset: startChar, extentOffset: endChar),
    )) {
      final Rect rect = box.toRect();
      final double midY = (rect.top + rect.bottom) / 2.0;
      final int rowIndex = _rowIndexAt(midY, rows);
      final Rect row = (rowIndex >= 0 && rowIndex < rows.length)
          ? rows[rowIndex]
          : Rect.fromLTWH(0, 0, width, _paragraphSize.height);
      boxes.add(Rect.fromLTRB(rect.left, row.top, rect.right, row.bottom));
    }
    return boxes;
  }

  // 把一个 token 拆成单字几何
  List<_CharGeometry> _buildCharBoxes(
    TextPainter painter,
    int startChar,
    int endChar,
    String tokenText,
    List<Rect> rows,
    double width,
  ) {
    final List<_CharGeometry> result = <_CharGeometry>[];
    int cursor = startChar;
    int index = 0;
    while (cursor < endChar) {
      int next = cursor + 1;
      List<Rect> boxes = _rowAdjustedBoxes(painter, cursor, next, rows, width);
      while (boxes.isEmpty && next < endChar) {
        next += 1;
        boxes = _rowAdjustedBoxes(painter, cursor, next, rows, width);
      }
      if (boxes.isNotEmpty) {
        final int localStart = cursor - startChar;
        final int localEnd = math.min(next - startChar, tokenText.length);
        result.add(
          _CharGeometry(
            charIndex: index,
            text: localStart < localEnd
                ? tokenText.substring(localStart, localEnd)
                : '',
            boxes: boxes,
          ),
        );
        index += 1;
      }
      cursor = next;
    }
    return result;
  }

  // 为每个字构建一份只画阴影的段落
  void _attachGlowPainters({
    required List<_CharGeometry> charBoxes,
    required TextStyle style,
    required TextScaler textScaler,
    required TextDirection textDirection,
    required Locale? locale,
    required TextHeightBehavior? textHeightBehavior,
    required TextWidthBasis textWidthBasis,
    required double fontSize,
  }) {
    final LyricGlowStyle glow = _glow!;
    final List<Shadow> shadows = <Shadow>[
      Shadow(
        color: glow.color.withValues(alpha: glow.peakAlpha),
        blurRadius: glow.radiusEm * fontSize * _kGlowRadiusToSigma,
      ),
    ];
    if (glow.haloEm > 0.0) {
      shadows.add(
        Shadow(
          color: glow.color.withValues(alpha: glow.peakAlpha * 0.45),
          blurRadius: glow.haloEm * fontSize * _kGlowRadiusToSigma,
        ),
      );
    }

    final TextStyle glowStyle = style.copyWith(
      color: const Color(0x00000000),
      shadows: shadows,
    );

    for (final _CharGeometry char in charBoxes) {
      if (char.text.isEmpty) continue;
      final TextPainter painter = TextPainter(
        text: TextSpan(text: char.text, style: glowStyle),
        textDirection: textDirection,
        textScaler: textScaler,
        locale: locale,
        textHeightBehavior: textHeightBehavior,
        textWidthBasis: textWidthBasis,
      )..layout();

      final List<ui.TextBox> ownBoxes = painter.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: char.text.length),
      );
      final Rect lineBox = char.boxes.first;
      Offset origin = lineBox.topLeft;
      if (ownBoxes.isNotEmpty) {
        final Rect own = ownBoxes.first.toRect();
        origin = Offset(lineBox.left - own.left, lineBox.top - own.top);
      }
      char.glowPainter = painter;
      char.glowOrigin = origin;
      _glowPainters.add(painter);
    }
  }

  static double _emphasisWave(double x) {
    if (x <= 0.0 || x >= 1.0) return 0.0;
    return x < 0.5
        ? _kEmphasisRise.transform(x * 2.0)
        : 1.0 - _kEmphasisFall.transform(x * 2.0 - 1.0);
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

  // 单个音节/单字的上浮层
  Widget _buildFloatingLayer({
    required List<Rect> clipRects,
    required Offset offset,
    required double scale,
    required Offset scaleCenter,
    required bool wiping,
    required _FillState fill,
    required double fade,
    required Widget baseLayer,
    required Widget highlightLayer,
  }) {
    Widget content;
    if (wiping) {
      // 正在演唱中：水平擦除过渡，两层只差颜色
      content = Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (Rect bounds) => _edgeGradient(
              bounds: bounds,
              edgeX: fill.edgeX,
              fade: fade,
              highlightSide: false,
            ).createShader(bounds),
            child: baseLayer,
          ),
          ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (Rect bounds) => _edgeGradient(
              bounds: bounds,
              edgeX: fill.edgeX,
              fade: fade,
              highlightSide: true,
            ).createShader(bounds),
            child: highlightLayer,
          ),
        ],
      );
    } else {
      // 已唱完：整段高亮
      content = highlightLayer;
    }

    content = ClipPath(clipper: _RectsClipper(clipRects), child: content);

    if (scale != 1.0) {
      // 围绕该字自身中心缩放，再整体平移：合成一次变换，避免叠加两层
      final Matrix4 matrix = Matrix4.identity()
        ..translateByDouble(scaleCenter.dx, scaleCenter.dy, 0.0, 1.0)
        ..scaleByDouble(scale, scale, 1.0, 1.0)
        ..translateByDouble(-scaleCenter.dx, -scaleCenter.dy, 0.0, 1.0)
        ..translateByDouble(offset.dx, offset.dy, 0.0, 1.0);
      return Transform(
        filterQuality: FilterQuality.low,
        transform: matrix,
        child: content,
      );
    }

    return Transform.translate(
      filterQuality: FilterQuality.low,
      offset: offset,
      child: content,
    );
  }

  // 光晕层
  Widget _buildGlowLayer(
    List<_GlowFrame> frames, {
    required _FillState fill,
    required double fade,
    required double width,
    required double height,
    required double bleed,
  }) {
    final Widget paint = CustomPaint(
      key: const ValueKey<String>('karaoke-glow'),
      painter: _GlowPainter(frames),
      willChange: true,
    );
    if (fill.currentRow == null || !width.isFinite || !height.isFinite) {
      return paint;
    }

    // 遮罩盒向上下各扩 bleed：光晕会溢出字形盒，超出遮罩范围的部分不会被裁
    return Positioned(
      left: 0,
      top: -bleed,
      width: width,
      height: height + bleed * 2,
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (Rect bounds) => _edgeGradient(
          bounds: bounds,
          edgeX: fill.edgeX,
          fade: fade * _kGlowFadeScale,
          highlightSide: true,
        ).createShader(bounds),
        child: Transform.translate(offset: Offset(0, bleed), child: paint),
      ),
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

        // 主行逐字上浮幅度：约 0.095em
        final double fontSize = _emphasisFontSize;

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
          fontSize: fontSize,
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
                final List<_GlowFrame> glowFrames = <_GlowFrame>[];
                final LyricGlowStyle? glow = _glow;
                for (final _TokenGeometry geom in _geometries) {
                  if (geom.boxes.isEmpty) continue;

                  final double startMs = geom.startMs;
                  final double endMs = geom.endMs;
                  final double durationMs = geom.durationMs;
                  final double riseDuration = math.max(850.0, durationMs);
                  final double riseEndMs = startMs + riseDuration;

                  // 强调参数：只影响单字变换，与逐字擦除 / 上浮互不干扰
                  final int charCount = geom.charBoxes.length;
                  final double emphasisDuMs = math.max(
                    _kEmphasisMinTokenMs,
                    durationMs,
                  );
                  double emphasisAmount = emphasisDuMs / 2000.0;
                  emphasisAmount = emphasisAmount > 1.0
                      ? math.sqrt(emphasisAmount)
                      : emphasisAmount * emphasisAmount * emphasisAmount;
                  emphasisAmount = (emphasisAmount * 0.6).clamp(0.0, 1.2);
                  final double staggerMs = charCount > 0
                      ? emphasisDuMs / _kEmphasisStaggerSpan / charCount
                      : 0.0;
                  final double emphasisEndMs = charCount > 0
                      ? startMs +
                            emphasisDuMs +
                            staggerMs * (charCount - 1).toDouble()
                      : 0.0;
                  final double emphasisStartMs = startMs;

                  if (timeMs < startMs) {
                    // 尚未唱到的音节：保持原位未高亮
                    unsungBoxes.addAll(geom.boxes);
                  } else if (timeMs >= riseEndMs &&
                      timeMs >= endMs &&
                      timeMs >= emphasisEndMs) {
                    // 唱完、浮动到位、强调波形也已归零：沉淀到高亮层
                    settledBoxes.addAll(geom.boxes);
                  } else if (charCount > 0) {
                    // 长音节：逐字缩放 + 推挤 + 错峰以及原有的上浮
                    final double tokenFloatY = _calculateTokenFloatY(
                      geometry: geom,
                      timeMs: timeMs,
                      maxFloatDistance: maxFloatDistance,
                      highlightFactor: highlightFactor,
                    );
                    final bool isWiping = timeMs < endMs;
                    final double scaleAmount = geom.dampedEmphasis
                        ? _kCjkScaleAmount
                        : _kEmphasisScaleAmount;

                    for (final _CharGeometry char in geom.charBoxes) {
                      final double charStartMs =
                          emphasisStartMs + staggerMs * char.charIndex;
                      final double wave = _emphasisWave(
                        (timeMs - charStartMs) / emphasisDuMs,
                      );
                      final double charScale =
                          1.0 + wave * scaleAmount * emphasisAmount;
                      final double dxEm =
                          -wave *
                          _kEmphasisPushEm *
                          emphasisAmount *
                          (charCount / 2.0 - char.charIndex);
                      final double dyEm =
                          -wave * _kEmphasisLiftEm * emphasisAmount;
                      final Offset charOffset = Offset(
                        dxEm * fontSize,
                        tokenFloatY + dyEm * fontSize,
                      );
                      final Offset scaleCenter = char.boxes.first.center;

                      floatingWidgets.add(
                        _buildFloatingLayer(
                          clipRects: char.boxes,
                          offset: charOffset,
                          scale: charScale,
                          scaleCenter: scaleCenter,
                          wiping: isWiping,
                          fill: fill,
                          fade: fade,
                          baseLayer: baseLayer,
                          highlightLayer: highlightLayer,
                        ),
                      );

                      final TextPainter? glowPainter = char.glowPainter;
                      if (glow != null && glowPainter != null) {
                        final double glowAlpha = wave * highlightFactor;
                        if (glowAlpha > _kGlowMinAlpha) {
                          glowFrames.add(
                            _GlowFrame(
                              painter: glowPainter,
                              origin: char.glowOrigin,
                              box: char.boxes.first,
                              offset: charOffset,
                              scale: charScale,
                              alpha: glowAlpha.clamp(0.0, 1.0),
                              spread:
                                  (glow.radiusEm + glow.haloEm) * fontSize +
                                  4.0,
                            ),
                          );
                        }
                      }
                    }
                  } else {
                    // 普通音节：整词一起浮动
                    final double tokenFloatY = _calculateTokenFloatY(
                      geometry: geom,
                      timeMs: timeMs,
                      maxFloatDistance: maxFloatDistance,
                      highlightFactor: highlightFactor,
                    );

                    final bool isWiping = timeMs < endMs;

                    floatingWidgets.add(
                      _buildFloatingLayer(
                        clipRects: geom.boxes,
                        offset: Offset(0, tokenFloatY),
                        scale: 1.0,
                        scaleCenter: geom.boxes.first.center,
                        wiping: isWiping,
                        fill: fill,
                        fade: fade,
                        baseLayer: baseLayer,
                        highlightLayer: highlightLayer,
                      ),
                    );
                  }
                }

                // 长音节辉光：单独一层，位于所有文字之下，不受逐字裁剪影响
                if (glowFrames.isNotEmpty) {
                  layers.add(
                    _buildGlowLayer(
                      glowFrames,
                      fill: fill,
                      fade: fade,
                      width: width,
                      height: _paragraphSize.height,
                      bleed: glow == null
                          ? 0.0
                          : (glow.radiusEm + glow.haloEm) * fontSize + 8.0,
                    ),
                  );
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

// 一个正在发光的字：段落只构建一次，每帧只改图层 alpha
class _GlowFrame {
  const _GlowFrame({
    required this.painter,
    required this.origin,
    required this.box,
    required this.offset,
    required this.scale,
    required this.alpha,
    required this.spread,
  });

  final TextPainter painter;
  final Offset origin;
  final Rect box;
  final Offset offset;
  final double scale;
  final double alpha;
  final double spread;
}

class _GlowPainter extends CustomPainter {
  _GlowPainter(this.frames);

  final List<_GlowFrame> frames;

  @override
  void paint(Canvas canvas, Size size) {
    for (final _GlowFrame frame in frames) {
      final Offset center = frame.box.center;
      canvas.save();
      canvas.translate(frame.offset.dx, frame.offset.dy);
      canvas.translate(center.dx, center.dy);
      canvas.scale(frame.scale);
      canvas.translate(-center.dx, -center.dy);

      // 阴影颜色与 alpha 已烘焙进段落，这里整体调制以实现脉冲
      canvas.saveLayer(
        frame.box.inflate(frame.spread),
        Paint()..color = Color.fromRGBO(0, 0, 0, frame.alpha),
      );
      frame.painter.paint(canvas, frame.origin);
      canvas.restore();

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_GlowPainter oldDelegate) => true;
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
