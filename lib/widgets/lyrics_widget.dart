import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../page/playlist/playlist_models.dart';
import '../page/setting/settings_provider.dart';
import '../page/playlist/playlist_content_notifier.dart';
import 'interlude_animation_widget.dart';
import 'karaoke_line_text.dart';
import 'lyric_blur.dart';

// 歌词 TextButton 的内边距
const EdgeInsets _kLyricButtonPadding = EdgeInsets.fromLTRB(12, 9, 12, 9);

const double _kIdleMainLineAlpha = 0.55; // 原文/主行
const double _kIdleSecondaryLineAlpha = 0.45; // 翻译、罗马音等次级行

const Duration _kHighlightFadeInDuration = Duration(milliseconds: 160);

// 退场动画触发在高亮已经交给下一行之后
const double _kExitDurationRatio = 0.22;
const Duration _kExitMinDuration = Duration(milliseconds: 160);
const Duration _kExitMaxDuration = Duration(milliseconds: 250);

const Curve _kHighlightFadeCurve = Curves.easeOutCubic;
const Curve _kExitCurve = Curves.easeInOutCubic;

// 歌词跟随播放滚动的动画参数。
// 间奏行折叠时，折叠本身承担了这次滚动的一部分位移（见 _scrollToCurrentLine 的说明），
// 因此两者必须共用同一组参数，否则合成运动会看起来像"跳两次"。
const Duration _kLyricFollowScrollDuration = Duration(milliseconds: 300);
const Curve _kLyricFollowScrollCurve = Curves.easeInOut;

class LyricsWidget extends StatefulWidget {
  final List<LyricLine> lyrics;
  final int currentIndex;
  final int maxLinesPerLyric; // 最大行数
  final Function(int index)? onTapLine;

  const LyricsWidget({
    super.key,
    required this.lyrics,
    required this.currentIndex,
    this.maxLinesPerLyric = 1,
    this.onTapLine,
  });

  @override
  State<LyricsWidget> createState() => _LyricsWidgetState();
}

class _LyricsWidgetState extends State<LyricsWidget>
    with TickerProviderStateMixin {
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();

  double? _lastEstimatedMaxWidth;
  double? _lastFontSize;
  TextAlign? _lastAlignment;
  int? _lastMaxLinesPerLyric;
  double? _lastLyricVerticalSpacing;
  int? _lastLyricFontWeight;
  bool? _lastAddLyricPadding;

  bool _isUserScrolling = false; // 标记用户是否在手动滚动
  Timer? _scrollStopTimer; // 滚动停止检测定时器

  final List<GlobalKey> _elasticItemKeys = [];
  final List<double> _elasticItemHeights = [];
  final List<double> _elasticBaseYPositions = [];
  final List<AnimationController> _elasticControllers = [];
  bool _elasticHeightsMeasured = false;
  bool _elasticNeedsMeasure = false;
  bool _elasticPendingJump = true;
  TextScaler? _lastElasticTextScaler;

  // 非当前行的行内容缓存
  final Map<int, _ElasticRowCacheEntry> _elasticRowCache =
      <int, _ElasticRowCacheEntry>{};
  int _elasticAnimationGeneration = 0;

  // 最近一次布局用的顶部填充高度
  double _elasticTopPadding = 0;
  bool _isElasticPointerDragging = false;
  bool _didElasticPointerMove = false;

  int _previousIndex = 0;

  // 当前行高亮的点亮程度
  late final AnimationController _highlightFade;

  // 上一行的退场程度：1 = 还保持高亮时的样子，0 = 完全熄灭、位移归零。
  // 在 currentIndex 切到下一行的同一时刻从 1 走到 0，退场因此发生在“交接之后”。
  late final AnimationController _exitFade;

  bool _fadeInScheduled = false;

  int? _fadeInPendingIndex;

  @override
  void initState() {
    super.initState();

    _highlightFade = AnimationController(
      vsync: this,
      duration: _kHighlightFadeInDuration,
      value: 1.0, // 首次进入时直接点亮，不做淡入
    );
    _exitFade = AnimationController(
      vsync: this,
      duration: _kExitMaxDuration,
      value: 0.0,
    );
    _exitFade.addStatusListener(_onExitFadeStatus);

    final settings = context.read<SettingsProvider>();
    if (settings.enableLyricElasticScroll) {
      _resetElasticState();
    }

    // 首次构建后滚动到当前行
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToCurrentLine(instant: true);

      if (settings.enableLyricElasticScroll) {
        _jumpElasticToCurrent();
      }
    });
  }

  @override
  void dispose() {
    _scrollStopTimer?.cancel();
    _exitFade.removeStatusListener(_onExitFadeStatus);
    _exitFade.dispose();
    _highlightFade.dispose();
    _disposeElasticControllers();
    super.dispose();
  }

  // 上一行的退场时长：按它的跨度自适应
  Duration _exitDuration(int index) {
    if (index < 0 || index + 1 >= widget.lyrics.length) {
      return _kExitMinDuration;
    }
    final Duration span =
        widget.lyrics[index + 1].timestamp - widget.lyrics[index].timestamp;
    final double ms = span.inMicroseconds / 1000.0 * _kExitDurationRatio;
    return Duration(
      milliseconds: ms
          .clamp(
            _kExitMinDuration.inMilliseconds.toDouble(),
            _kExitMaxDuration.inMilliseconds.toDouble(),
          )
          .round(),
    );
  }

  void _startExitFade(int previousIndex) {
    if (previousIndex < 0 || previousIndex + 1 != widget.currentIndex) {
      _exitFade.value = 0.0;
      return;
    }
    // 从交接前那一帧的真实高亮程度起步，连超短行的淡入中途也接得上
    _exitFade.value = _highlightFade.value.clamp(0.0, 1.0);
    if (_exitFade.value <= 0.0) return;
    _exitFade.animateBack(
      0.0,
      duration: _exitDuration(previousIndex),
      curve: _kExitCurve,
    );
  }

  // 退场结束后让列表重建一次，把上一行切回普通静态文本渲染
  void _onExitFadeStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && mounted) {
      setState(() {});
    }
  }

  void _scheduleHighlightFadeIn() {
    // 从换行到控制器清零之间有一帧空窗，这期间 build 先按 0 画
    _fadeInPendingIndex = widget.currentIndex;
    if (_fadeInScheduled) return;
    _fadeInScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fadeInScheduled = false;
      if (!mounted) return;
      _fadeInPendingIndex = null;
      _highlightFade.value = 0.0;
      _highlightFade.animateTo(
        1.0,
        duration: _kHighlightFadeInDuration,
        curve: _kHighlightFadeCurve,
      );
    });
  }

  double get _currentLineHighlightFactor {
    if (_fadeInPendingIndex == widget.currentIndex) return 0.0;
    return _highlightFade.value;
  }

  // 直接点亮（换歌等场景），不做淡入
  void _scheduleHighlightFadeToLit() {
    _fadeInPendingIndex = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _highlightFade.value = 1.0;
    });
  }

  // 直接监听滚轮判断用户是否手动滚动
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      if (!_isUserScrolling) {
        setState(() {
          _isUserScrolling = true;
        });
      }

      _scrollStopTimer?.cancel();
      _scrollStopTimer = Timer(const Duration(milliseconds: 1000), () {
        if (mounted) {
          setState(() {
            _isUserScrolling = false;
          });
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant LyricsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 当前行变化，滚动到对应行
    if (widget.currentIndex != oldWidget.currentIndex) {
      final int previousIndex = oldWidget.currentIndex;
      // AnimatedSize 收起间奏行的高度 h 时，它后面的内容整体上移 h，
      // 于是下一行正好接过间奏行原来的位置：滚动目标 = 间奏行当前所在位置
      // 剩下的位移由折叠补齐（同样的时长与曲线，合成一次平滑移动）
      //
      // 若这里照常滚动到下一行
      // ScrollablePositionedList.scrollTo 的目标偏移是按折叠前的布局算出来的，会多走 h
      // 再叠加折叠的 h —— 看起来就是先冲过头、动画结束又被拉回来，跳两次
      final bool interludeHandoff =
          widget.currentIndex == previousIndex + 1 &&
          previousIndex >= 0 &&
          previousIndex < widget.lyrics.length &&
          widget.lyrics[previousIndex].isInterlude;

      _applyElasticInterludeHeights();
      // 换行后当前行可能在"静态文本"和"逐字歌词"之间切换，需要重测一次
      _elasticNeedsMeasure = true;
      _scrollToCurrentLine(
        targetIndex: interludeHandoff ? previousIndex : null,
      );

      final int animateTarget = widget.currentIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || widget.currentIndex != animateTarget) return;
        _animateElasticToCurrent(previousIndex: previousIndex);
      });
      _previousIndex = oldWidget.currentIndex;
      // 上一行开始退场（熄灭 + 上浮位移落回），新的一行从暗到亮淡入
      _startExitFade(previousIndex);
      _scheduleHighlightFadeIn();
    }
    // 当歌词列表发生变化时（如切换歌曲），滚动到顶部
    else if (widget.lyrics != oldWidget.lyrics) {
      _resetElasticState();
      // 换歌不做上一行的退场
      _exitFade.value = 0.0;
      // 使用微延迟确保在新歌词加载后执行滚动
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (widget.currentIndex == 0 && _itemScrollController.isAttached) {
          _itemScrollController.jumpTo(index: 0, alignment: 0.0);
        }
        _jumpElasticToCurrent();
      });
      // 直接点亮，不播放淡入
      _scheduleHighlightFadeToLit();
    }
  }

  // 滚动方法
  void _scrollToCurrentLine({bool instant = false, int? targetIndex}) {
    if (!mounted || !_itemScrollController.isAttached) return;

    final int index = targetIndex ?? widget.currentIndex;

    // 检查索引是否有效
    if (index < 0 || index >= widget.lyrics.length) {
      return;
    }

    // 获取设置
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final addLyricPadding = settings.addLyricPadding;
    // 计算实际滚动到的索引（考虑填充项偏移）
    final int actualIndex = addLyricPadding ? index + 1 : index;

    if (instant) {
      _itemScrollController.jumpTo(index: actualIndex, alignment: 0.0);
    } else {
      _itemScrollController.scrollTo(
        index: actualIndex,
        duration: _kLyricFollowScrollDuration,
        curve: _kLyricFollowScrollCurve,
        alignment: 0.38, // 0.38 看起来更顺眼一点
      );
    }
  }

  // 处理逐字歌词：整行一个段落（KaraokeLineText），不再用 WidgetSpan
  Widget _buildMultiLineKaraokeRichText(
    List<List<LyricToken>> multiLineTokens,
    double fontSize,
    FontWeight fontWeight,
    double highlightFactor,
    ColorScheme colorScheme, {
    bool forceSecondary = false,
    double blurSigma = 0.0,
    bool enableFloating = true,
  }) {
    // 获取当前播放位置和播放状态
    final playlistNotifier = Provider.of<PlaylistContentNotifier>(
      context,
      listen: false,
    );
    final currentPosition = playlistNotifier.currentPosition;
    final isPlaying = playlistNotifier.isPlaying;

    final List<Widget> lines = [];

    for (int lineIndex = 0; lineIndex < multiLineTokens.length; lineIndex++) {
      final List<LyricToken> tokens = multiLineTokens[lineIndex];

      // forceSecondary：强制使用次级样式（如罗马音行）
      final bool isSecondaryLine = forceSecondary || lineIndex > 0;

      // 两层样式只差颜色
      final TextStyle baseStyle = _lyricTextStyle(
        highlightFactor: 0.0,
        isSecondaryLine: isSecondaryLine,
        fontSize: fontSize,
        fontWeight: fontWeight,
        colorScheme: colorScheme,
        blurSigma: blurSigma,
      );
      final TextStyle highlightStyle = _lyricTextStyle(
        highlightFactor: highlightFactor,
        isSecondaryLine: isSecondaryLine,
        fontSize: fontSize,
        fontWeight: fontWeight,
        colorScheme: colorScheme,
        blurSigma: blurSigma,
      );

      lines.add(
        KaraokeLineText(
          tokens: tokens,
          baseStyle: baseStyle,
          highlightStyle: highlightStyle,
          currentTime: currentPosition,
          isPlaying: isPlaying,
          textAlign: _lastAlignment ?? TextAlign.center,
          highlightFactor: highlightFactor,
          // 只有主行参与上浮
          enableFloating: enableFloating && !isSecondaryLine,
        ),
      );

      // 如果不是最后一行，添加一些间距
      if (lineIndex < multiLineTokens.length - 1) {
        lines.add(const SizedBox(height: 6));
      }
    }

    // 根据文本对齐方式设置Column的对齐方式
    CrossAxisAlignment columnAlignment = CrossAxisAlignment.start;
    if (_lastAlignment == TextAlign.center) {
      columnAlignment = CrossAxisAlignment.center;
    } else if (_lastAlignment == TextAlign.right) {
      columnAlignment = CrossAxisAlignment.end;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: columnAlignment, // 容器对齐
      children: lines,
    );
  }

  // 间奏行只有在播放到它时才占位
  bool _isCollapsedInterlude(int index) =>
      index >= 0 &&
      index < widget.lyrics.length &&
      index != widget.currentIndex &&
      widget.lyrics[index].isInterlude;

  List<int> _buildVisualRanks() {
    final List<int> ranks = List<int>.filled(widget.lyrics.length, 0);
    int rank = 0;
    for (int i = 0; i < widget.lyrics.length; i++) {
      ranks[i] = rank;
      if (!_isCollapsedInterlude(i)) rank++;
    }
    return ranks;
  }

  int _visualDistance(int index, List<int> visualRanks) {
    if (index < 0 || index >= visualRanks.length) return 0;
    final int currentIndex = widget.currentIndex;
    final int currentRank =
        currentIndex >= 0 && currentIndex < visualRanks.length
        ? visualRanks[currentIndex]
        : 0;
    return (visualRanks[index] - currentRank).abs();
  }

  // 间奏行展开时的高度
  double _interludeRowHeight(double fontSize, double lyricVerticalSpacing) =>
      fontSize * 1.5 + (lyricVerticalSpacing + 0.4 * (fontSize / 2)) * 2;

  // 把间奏行当前该有多高提前写进弹性布局
  void _applyElasticInterludeHeights() {
    if (_elasticItemHeights.length != widget.lyrics.length) return;

    final double fontSize = _lastFontSize ?? 20.0;
    final double spacing = _lastLyricVerticalSpacing ?? 6.0;
    final double expandedHeight = _interludeRowHeight(fontSize, spacing);

    bool changed = false;
    for (int i = 0; i < widget.lyrics.length; i++) {
      if (!widget.lyrics[i].isInterlude) continue;
      final double height = i == widget.currentIndex ? expandedHeight : 0.0;
      if ((_elasticItemHeights[i] - height).abs() > 0.5) {
        _elasticItemHeights[i] = height;
        changed = true;
      }
    }

    if (changed) {
      _rebuildElasticBasePositions(topPadding: _elasticTopPadding);
    }
  }

  double _calculateSigma(
    int distance,
    bool shouldBlur,
    bool isCurrent,
    double blurStrength,
  ) {
    if (!shouldBlur || isCurrent) return 0.0;

    const int maxDistance = 5;
    final double normalizedDistance = (distance / maxDistance).clamp(0.0, 1.0);
    return normalizedDistance * blurStrength;
  }

  TextStyle _lyricTextStyle({
    required double highlightFactor,
    required bool isSecondaryLine,
    required double fontSize,
    required FontWeight fontWeight,
    required ColorScheme colorScheme,
    double blurSigma = 0.0,
  }) {
    final double lineFontSize = isSecondaryLine ? fontSize * 0.88 : fontSize;
    final Color idleColor = isSecondaryLine
        ? colorScheme.onSurfaceVariant.withValues(
            alpha: _kIdleSecondaryLineAlpha,
          )
        : colorScheme.onSurfaceVariant.withValues(alpha: _kIdleMainLineAlpha);
    final Color litColor = isSecondaryLine
        ? colorScheme.primary.withValues(alpha: 0.88)
        : colorScheme.primary;
    final Color lineColor = Color.lerp(idleColor, litColor, highlightFactor)!;

    return buildLyricTextStyle(
      lineColor: lineColor,
      fontSize: lineFontSize,
      fontWeight: fontWeight,
      blurSigma: blurSigma,
    );
  }

  Widget _buildStaticLyricText({
    required String text,
    required TextAlign lyricAlignment,
    required TextStyle style,
  }) {
    return Text(
      text,
      textAlign: lyricAlignment,
      style: style,
      // textHeightBehavior: const TextHeightBehavior(
      //   applyHeightToFirstAscent: false,
      //   applyHeightToLastDescent: false,
      // ),
    );
  }

  Widget _buildLyricItem({
    required int lyricIndex,
    required int distance,
    required double maxWidth,
    required double fontSize,
    required FontWeight fontWeight,
    required double lyricVerticalSpacing,
    required TextAlign lyricAlignment,
    required bool shouldBlur,
    required ColorScheme colorScheme,
    required double blurStrength,
    bool enableFloating = true,
  }) {
    final line = widget.lyrics[lyricIndex];
    final bool isCurrent = lyricIndex == widget.currentIndex;

    // 上一行交接出去之后的一小段退场期
    final bool isExiting =
        !isCurrent &&
        lyricIndex == widget.currentIndex - 1 &&
        _exitFade.value > 0.0;

    // 本行的模糊强度，直接写进文字样式（见 _lyricTextStyle）
    final double blurSigma = _calculateSigma(
      distance,
      shouldBlur,
      isCurrent,
      blurStrength,
    );

    // 当前行跟着点亮动画；上一行在退场期跟着 _exitFade；其余行永远保持暗色
    // 非当前行用常量动画，不会被通知
    Widget withHighlight(Widget Function(double factor) builder) {
      if (isCurrent) {
        return AnimatedBuilder(
          animation: _highlightFade,
          builder: (BuildContext context, Widget? _) =>
              builder(_currentLineHighlightFactor),
        );
      }
      if (isExiting) {
        return AnimatedBuilder(
          animation: _exitFade,
          builder: (BuildContext context, Widget? _) =>
              builder(_exitFade.value),
        );
      }
      return builder(0.0);
    }

    final List<Widget> columnChildren = [];
    int renderedLines = 0;
    final int maxAllowed = widget.maxLinesPerLyric;

    if (line.isInterlude) {
      // 间奏逻辑延后到最后处理，因为它需要直接包裹整个 Padding
    } else if (line.isKaraoke && line.karaokeTextIndices != null) {
      // 有精确索引映射时按 texts 顺序遍历，逐行判断类型
      // 解析器用 -1 标记"有 tokens 但没有对应 texts 行"的 token 组
      // 这里要跳过，避免它去认领别的歌词行
      final Map<int, int> textIndexToTokenGroup = {};
      for (int k = 0; k < line.karaokeTextIndices!.length; k++) {
        final int textIndex = line.karaokeTextIndices![k];
        if (textIndex >= 0 && k < line.tokens!.length) {
          textIndexToTokenGroup[textIndex] = k;
        }
      }

      bool firstChild = true;

      for (
        int i = 0;
        i < line.texts.length && renderedLines < maxAllowed;
        i++
      ) {
        final int? tokenGroupIndex = textIndexToTokenGroup[i];

        Widget lineWidget;

        if (tokenGroupIndex != null && (isCurrent || isExiting)) {
          // 当前高亮行 / 正在退场的上一行：渲染为逐字动画效果
          final bool isSecondaryKaraoke = tokenGroupIndex > 0;
          final List<LyricToken> tokens = line.tokens![tokenGroupIndex];
          lineWidget = withHighlight(
            (double factor) => _buildMultiLineKaraokeRichText(
              [tokens],
              fontSize,
              fontWeight,
              factor,
              colorScheme,
              forceSecondary: isSecondaryKaraoke,
              enableFloating: enableFloating,
              blurSigma: blurSigma,
            ),
          );
        } else {
          // 非高亮行，或该行是翻译行：渲染为静态文本
          final bool isSecondaryLine =
              tokenGroupIndex == null || tokenGroupIndex > 0;
          final String displayText = tokenGroupIndex != null
              ? line.tokens![tokenGroupIndex]
                    .map((LyricToken token) => token.text)
                    .join()
              : line.texts[i];
          lineWidget = withHighlight(
            (double factor) => _buildStaticLyricText(
              text: displayText,
              lyricAlignment: lyricAlignment,
              style: _lyricTextStyle(
                highlightFactor: factor,
                isSecondaryLine: isSecondaryLine,
                fontSize: fontSize,
                fontWeight: fontWeight,
                colorScheme: colorScheme,
                blurSigma: blurSigma,
              ),
            ),
          );
        }

        if (!firstChild) {
          columnChildren.add(const SizedBox(height: 6));
        }
        firstChild = false;
        renderedLines++;

        columnChildren.add(lineWidget);
      }
    } else if ((isCurrent || isExiting) && line.isKaraoke) {
      // 没有 karaokeTextIndices 时，沿用原有的批量渲染逻辑
      final int karaokeCount = line.tokens!.length;
      final int linesToTake = (karaokeCount > maxAllowed)
          ? maxAllowed
          : karaokeCount;
      final List<List<LyricToken>> tokensToRender = line.tokens!
          .take(linesToTake)
          .toList();

      renderedLines += linesToTake;

      columnChildren.add(
        withHighlight(
          (double factor) => _buildMultiLineKaraokeRichText(
            tokensToRender,
            enableFloating: enableFloating,
            fontSize,
            fontWeight,
            factor,
            colorScheme,
            blurSigma: blurSigma,
          ),
        ),
      );
    } else {
      final int karaokeCount = (line.tokens != null) ? line.tokens!.length : 0;
      final int mainLinesLimit = (karaokeCount > 0 ? karaokeCount : 1);
      final int linesToTake = (mainLinesLimit > maxAllowed)
          ? maxAllowed
          : mainLinesLimit;

      for (int i = 0; i < linesToTake && i < line.texts.length; i++) {
        renderedLines++;

        final bool isSecondaryLine = i > 0;

        final Widget staticText = withHighlight(
          (double factor) => _buildStaticLyricText(
            text: line.texts[i],
            lyricAlignment: lyricAlignment,
            style: _lyricTextStyle(
              highlightFactor: factor,
              isSecondaryLine: isSecondaryLine,
              fontSize: fontSize,
              fontWeight: fontWeight,
              colorScheme: colorScheme,
              blurSigma: blurSigma,
            ),
          ),
        );

        columnChildren.add(staticText);
        if (i < linesToTake - 1) {
          columnChildren.add(const SizedBox(height: 6));
        }
      }
    }

    // 追加翻译行仅适用于旧格式兼容路径
    if (line.karaokeTextIndices == null) {
      final int karaokeCount = (line.tokens != null) ? line.tokens!.length : 0;
      final int translationStartIndex = (karaokeCount > 0 ? karaokeCount : 1);

      if (renderedLines < maxAllowed &&
          line.texts.length > translationStartIndex) {
        columnChildren.add(const SizedBox(height: 6));

        for (
          int i = translationStartIndex;
          i < line.texts.length && renderedLines < maxAllowed;
          i++
        ) {
          renderedLines++;

          final Widget translationWidget = withHighlight(
            (double factor) => _buildStaticLyricText(
              text: line.texts[i],
              lyricAlignment: lyricAlignment,
              style: _lyricTextStyle(
                highlightFactor: factor,
                isSecondaryLine: true,
                fontSize: fontSize,
                fontWeight: fontWeight,
                colorScheme: colorScheme,
                blurSigma: blurSigma,
              ),
            ),
          );

          columnChildren.add(translationWidget);

          if (i < line.texts.length - 1 && renderedLines < maxAllowed) {
            columnChildren.add(const SizedBox(height: 6));
          }
        }
      }
    }

    Widget itemWidget = Padding(
      padding: EdgeInsets.symmetric(
        vertical: lyricVerticalSpacing + 0.4 * (fontSize / 2),
        horizontal: 4,
      ),
      child: Align(
        alignment: _getAlignmentFromTextAlign(lyricAlignment),
        child: SizedBox(
          width: maxWidth,
          child: TextButton(
            onPressed: () {
              widget.onTapLine?.call(lyricIndex);
              final playlistNotifier = Provider.of<PlaylistContentNotifier>(
                context,
                listen: false,
              );
              if (!playlistNotifier.isPlaying) {
                playlistNotifier.play();
              }
            },
            style: ButtonStyle(
              padding: WidgetStateProperty.all<EdgeInsets>(
                _kLyricButtonPadding,
              ),
              shape: WidgetStateProperty.all<RoundedRectangleBorder>(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              backgroundColor: WidgetStateProperty.resolveWith<Color>((
                Set<WidgetState> states,
              ) {
                if (states.contains(WidgetState.hovered)) {
                  return Colors.grey.withValues(alpha: 0.2);
                }
                return Colors.transparent;
              }),
              overlayColor: WidgetStateProperty.resolveWith<Color>((
                Set<WidgetState> states,
              ) {
                if (states.contains(WidgetState.pressed)) {
                  return Colors.grey.withValues(alpha: 0.3);
                }
                return Colors.transparent;
              }),
              alignment: _getAlignmentFromTextAlign(lyricAlignment),
            ),
            // 模糊写在各行文字样式里（见 _lyricTextStyle），整行不再包离屏滤镜
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: columnChildren,
            ),
          ),
        ),
      ),
    );

    if (line.isInterlude) {
      if (isCurrent) {
        final playlistNotifier = Provider.of<PlaylistContentNotifier>(
          context,
          listen: false,
        );
        itemWidget = Padding(
          padding: EdgeInsets.symmetric(
            vertical: lyricVerticalSpacing + 0.4 * (fontSize / 2),
            horizontal: 4,
          ),
          child: Align(
            alignment: _getAlignmentFromTextAlign(lyricAlignment),
            child: SizedBox(
              width: maxWidth,
              child: Container(
                height: fontSize * 1.5,
                alignment: _getAlignmentFromTextAlign(lyricAlignment),
                padding: EdgeInsets.only(
                  left: lyricAlignment == TextAlign.left ? fontSize * 0.5 : 0,
                  right: lyricAlignment == TextAlign.right ? fontSize * 0.5 : 0,
                ),
                child: InterludeAnimationWidget(
                  isCurrent: isCurrent,
                  baseColor: colorScheme.onSurfaceVariant.withValues(
                    alpha: _kIdleMainLineAlpha,
                  ),
                  highlightColor: colorScheme.primary.withValues(alpha: 0.88),
                  startTime: line.timestamp,
                  interludeDuration: line.interludeDuration ?? Duration.zero,
                  currentTime: playlistNotifier.currentPosition,
                  isPlaying: playlistNotifier.isPlaying,
                ),
              ),
            ),
          ),
        );

        return TweenAnimationBuilder<double>(
          // 弹性滚动与非弹性列表共用，key 不再带分支名
          key: ValueKey('interlude_$lyricIndex'),
          tween: Tween<double>(begin: 0.0, end: 1.0),
          // 前 300ms 等待跟随滚动推开，后 200ms 淡入并放大圆点
          duration: const Duration(milliseconds: 500),
          builder: (context, value, child) {
            final double dotValue = ((value - 0.6) / 0.4).clamp(0.0, 1.0);
            return Opacity(opacity: dotValue, child: child);
          },
          child: itemWidget,
        );
      }

      return const SizedBox.shrink();
    }

    return itemWidget;
  }

  Widget _buildElasticLyrics({
    required double viewportHeight,
    required double maxWidth,
    required double fontSize,
    required FontWeight fontWeight,
    required double lyricVerticalSpacing,
    required TextAlign lyricAlignment,
    required bool addLyricPadding,
    required bool shouldBlur,
    required ColorScheme colorScheme,
    required double blurStrength,
    bool enableFloating = true,
    required List<int> visualRanks,
  }) {
    if (_elasticControllers.length != widget.lyrics.length) {
      _resetElasticState();
    }

    final double paddingHeight = addLyricPadding ? viewportHeight * 0.37 : 0;
    _elasticTopPadding = paddingHeight;
    _rebuildElasticBasePositions(topPadding: paddingHeight);

    final TextScaler textScaler = MediaQuery.textScalerOf(context);
    if (textScaler != _lastElasticTextScaler) {
      _lastElasticTextScaler = textScaler;
      _elasticNeedsMeasure = true;
    }
    if (_elasticNeedsMeasure) {
      _elasticNeedsMeasure = false;
      _measureElasticItems(paddingHeight, viewportHeight);
    }

    // 视口外多留一点才跳过绘制
    final double cullMargin = 24.0 + (shouldBlur ? blurStrength * 3.0 : 0.0);

    final double contentHeight =
        paddingHeight +
        _elasticItemHeights.fold<double>(0, (sum, height) => sum + height) +
        paddingHeight;

    // 影响"整行渲染结果"的参数
    // 变化时需要重建行内容
    final int configHash = Object.hash(
      widget.lyrics,
      widget.maxLinesPerLyric,
      maxWidth,
      fontSize,
      fontWeight,
      lyricVerticalSpacing,
      lyricAlignment,
      shouldBlur,
      blurStrength,
      colorScheme,
    );

    return Listener(
      onPointerSignal: _onElasticPointerSignal,
      onPointerDown: _onElasticPointerDown,
      onPointerMove: _onElasticPointerMove,
      onPointerUp: _onElasticPointerUp,
      onPointerCancel: _onElasticPointerCancel,
      behavior: HitTestBehavior.translucent,
      child: ClipRect(
        child: SizedBox(
          width: double.infinity,
          height: viewportHeight,
          child: OverflowBox(
            alignment: Alignment.topCenter,
            minHeight: contentHeight,
            maxHeight: contentHeight,
            child: SizedBox(
              height: contentHeight,
              child: Stack(
                clipBehavior: Clip.none,
                children: List.generate(widget.lyrics.length, (index) {
                  final AnimationController controller =
                      _elasticControllers[index];
                  final int distance = _visualDistance(index, visualRanks);
                  final bool isCurrent = index == widget.currentIndex;
                  // 正在退场的上一行不能进行缓存
                  final bool isExitingRow =
                      !isCurrent &&
                      index == widget.currentIndex - 1 &&
                      _exitFade.value > 0.0;
                  final int rowHash = Object.hash(
                    index,
                    _calculateSigma(
                      distance,
                      shouldBlur,
                      isCurrent,
                      blurStrength,
                    ),
                    configHash,
                  );
                  final _ElasticRowCacheEntry? cached =
                      (isCurrent || isExitingRow)
                      ? null
                      : _elasticRowCache[index];
                  Widget row;
                  if (cached != null && cached.hash == rowHash) {
                    row = cached.widget;
                  } else {
                    row = _buildLyricItem(
                      lyricIndex: index,
                      distance: distance,
                      maxWidth: maxWidth,
                      fontSize: fontSize,
                      fontWeight: fontWeight,
                      lyricVerticalSpacing: lyricVerticalSpacing,
                      lyricAlignment: lyricAlignment,
                      shouldBlur: shouldBlur,
                      colorScheme: colorScheme,
                      blurStrength: blurStrength,
                      enableFloating: enableFloating,
                    );
                    if (isCurrent || isExitingRow) {
                      _elasticRowCache.remove(index);
                    } else {
                      _elasticRowCache[index] = _ElasticRowCacheEntry(
                        rowHash,
                        row,
                      );
                    }
                  }
                  return Positioned(
                    top: 0, // 固定top，交给Transform.translate处理
                    left: 0,
                    right: 0,
                    child: AnimatedBuilder(
                      animation: controller,
                      child: RepaintBoundary(
                        child: KeyedSubtree(
                          key: _elasticItemKeys[index],
                          child: row,
                        ),
                      ),
                      builder: (BuildContext context, Widget? child) {
                        final double paintOffset = controller.value;
                        // 视口外的行不参与绘制
                        final double rowHeight =
                            index < _elasticItemHeights.length
                            ? _elasticItemHeights[index]
                            : _estimatedElasticItemHeight;
                        final bool offscreen =
                            paintOffset + rowHeight < -cullMargin ||
                            paintOffset > viewportHeight + cullMargin;
                        return Transform.translate(
                          filterQuality: FilterQuality.low, // 双线性过滤，解决文字抖动
                          offset: Offset(0, paintOffset),
                          child: Opacity(
                            opacity: offscreen ? 0.0 : 1.0,
                            child: child,
                          ),
                        );
                      },
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    // 一次性读取设置，减少重复 Provider 读取与重建
    final lyricAlignment = context.select<SettingsProvider, TextAlign>(
      (s) => s.lyricAlignment,
    );
    final autoAdjustLyricLayout = context.select<SettingsProvider, bool>(
      (s) => s.autoAdjustLyricLayout,
    );
    double fontSize = context.select<SettingsProvider, double>(
      (s) => s.fontSize,
    );
    double lyricVerticalSpacing = context.select<SettingsProvider, double>(
      (s) => s.lyricVerticalSpacing,
    );
    final int lyricFontWeightValue = context.select<SettingsProvider, int>(
      (s) => s.lyricFontWeight,
    );
    final FontWeight lyricFontWeight = FontWeight(lyricFontWeightValue);
    final addLyricPadding = context.select<SettingsProvider, bool>(
      (s) => s.addLyricPadding,
    );

    if (autoAdjustLyricLayout) {
      final size = MediaQuery.of(context).size;
      final double width = size.width > 0 ? size.width : 1150.0;
      final double height = size.height > 0 ? size.height : 620.0;
      final double scale = (math.sqrt(
        (width * height) / (1150.0 * 620.0),
      )).clamp(0.5, 2.0);
      fontSize = 22.0 * scale;
      lyricVerticalSpacing = 6.0 * scale;
    }
    final enableLyricBlur = context.select<SettingsProvider, bool>(
      (s) => s.enableLyricBlur,
    );
    final enableLyricElasticScroll = context.select<SettingsProvider, bool>(
      (s) => s.enableLyricElasticScroll,
    );
    final enableLyricFloatingAnimation = context.select<SettingsProvider, bool>(
      (s) => s.enableLyricFloatingAnimation,
    );
    final lyricBlurStrength = context.select<SettingsProvider, double>(
      (s) => s.lyricBlurStrength,
    );

    final shouldBlur = enableLyricBlur && !_isUserScrolling;

    // 折叠中的间奏行不可见，模糊梯度需要按看得见的计算
    final List<int> visualRanks = _buildVisualRanks();

    return LayoutBuilder(
      builder: (context, constraints) {
        // 与下方 Container 宽度保持一致（减去 padding）
        final double maxWidth = constraints.maxWidth - 12;

        final bool settingsChanged =
            _lastEstimatedMaxWidth != maxWidth ||
            _lastFontSize != fontSize ||
            _lastAlignment != lyricAlignment ||
            _lastMaxLinesPerLyric != widget.maxLinesPerLyric ||
            _lastLyricVerticalSpacing != lyricVerticalSpacing ||
            _lastLyricFontWeight != lyricFontWeightValue ||
            _lastAddLyricPadding != addLyricPadding;

        if (settingsChanged) {
          // 更新记录的值
          _lastEstimatedMaxWidth = maxWidth;
          _lastFontSize = fontSize;
          _lastAlignment = lyricAlignment;
          _lastMaxLinesPerLyric = widget.maxLinesPerLyric;
          _lastLyricVerticalSpacing = lyricVerticalSpacing;
          _lastLyricFontWeight = lyricFontWeightValue;
          _lastAddLyricPadding = addLyricPadding;
          _elasticNeedsMeasure = true;

          // 使用 Future.delayed 将滚动任务推迟到下一事件循环
          // 增加延迟用于确保布局完全稳定
          Future.delayed(const Duration(milliseconds: 50), () {
            if (mounted) {
              _scrollToCurrentLine(instant: false);
              // 字号/行距/宽度变了，行高和顶部补位都要按新布局重算
              // 弹性动画不再逐帧 build，只改标记不会自己触发测量，所以这里显式重建一次
              // 量完直接跳到当前行，而不是从旧布局动画过去
              _elasticHeightsMeasured = false;
              _elasticPendingJump = true;
              setState(() {
                _elasticNeedsMeasure = true;
              });
            }
          });
        }

        // 计算填充项数量，如果启用补位则添加1个填充项，否则不添加
        final int paddingItemCount = addLyricPadding ? 1 : 0;
        // 实际的歌词行数
        final int actualLyricsCount = widget.lyrics.length;
        // 总的项数（包括填充项）
        final int totalItemCount = actualLyricsCount + 2 * paddingItemCount;

        if (enableLyricElasticScroll) {
          return _buildElasticLyrics(
            viewportHeight: constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : MediaQuery.of(context).size.height,
            maxWidth: maxWidth,
            fontSize: fontSize,
            fontWeight: lyricFontWeight,
            lyricVerticalSpacing: lyricVerticalSpacing,
            lyricAlignment: lyricAlignment,
            addLyricPadding: addLyricPadding,
            shouldBlur: shouldBlur,
            colorScheme: colorScheme,
            blurStrength: lyricBlurStrength,
            enableFloating: enableLyricFloatingAnimation,
            visualRanks: visualRanks,
          );
        }

        return Listener(
          onPointerSignal: _onPointerSignal,
          child: ScrollConfiguration(
            behavior: const ScrollBehavior().copyWith(scrollbars: false),
            child: ScrollablePositionedList.builder(
              itemScrollController: _itemScrollController,
              itemPositionsListener: _itemPositionsListener,
              itemCount: totalItemCount,
              itemBuilder: (context, index) {
                // 处理顶部填充项
                if (index < paddingItemCount) {
                  return SizedBox(
                    height:
                        MediaQuery.of(context).size.height *
                        0.37, // 使用屏幕高度的37%作为空白区域
                  );
                }

                // 处理底部填充项
                if (index >= actualLyricsCount + paddingItemCount) {
                  return SizedBox(
                    height:
                        MediaQuery.of(context).size.height *
                        0.37, // 使用屏幕高度的37%作为空白区域
                  );
                }

                // 处理实际歌词项
                final int lyricIndex = index - paddingItemCount;
                final line = widget.lyrics[lyricIndex];

                // 复用 _buildLyricItem，让非弹性列表与弹性滚动走同一套行渲染逻辑
                final Widget itemWidget = _buildLyricItem(
                  lyricIndex: lyricIndex,
                  distance: _visualDistance(lyricIndex, visualRanks),
                  maxWidth: maxWidth,
                  fontSize: fontSize,
                  fontWeight: lyricFontWeight,
                  lyricVerticalSpacing: lyricVerticalSpacing,
                  lyricAlignment: lyricAlignment,
                  shouldBlur: shouldBlur,
                  colorScheme: colorScheme,
                  blurStrength: lyricBlurStrength,
                  enableFloating: enableLyricFloatingAnimation,
                );

                if (line.isInterlude) {
                  // 间奏行折叠时由 AnimatedSize 承担高度变化，
                  // 与 _kLyricFollowScrollDuration 合成一次平滑滚动
                  // （见 didUpdateWidget 中 interludeHandoff 的说明）
                  return AnimatedSize(
                    duration: _kLyricFollowScrollDuration,
                    curve: _kLyricFollowScrollCurve,
                    child: itemWidget,
                  );
                }

                return itemWidget;
              },
            ),
          ),
        );
      },
    );
  }

  Alignment _getAlignmentFromTextAlign(TextAlign textAlign) {
    switch (textAlign) {
      case TextAlign.left:
        return Alignment.centerLeft;
      case TextAlign.right:
        return Alignment.centerRight;
      case TextAlign.center:
      default:
        return Alignment.center;
    }
  }

  // --- 辅助函数 ---

  void _onElasticPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      _shiftElasticItems(-event.scrollDelta.dy);
      _scheduleElasticScrollEnd();
    }
  }

  void _onElasticPointerDown(PointerDownEvent event) {
    _isElasticPointerDragging = true;
    _didElasticPointerMove = false;
  }

  void _onElasticPointerMove(PointerMoveEvent event) {
    if (!_isElasticPointerDragging || event.delta.dy == 0) return;
    _didElasticPointerMove = true;
    _shiftElasticItems(event.delta.dy);
  }

  void _onElasticPointerUp(PointerUpEvent event) {
    _isElasticPointerDragging = false;
    if (_didElasticPointerMove) {
      // 拖动时需要将动画调度到当前位置
      _scheduleElasticScrollEnd();
    }
    _didElasticPointerMove = false;
  }

  void _onElasticPointerCancel(PointerCancelEvent event) {
    _isElasticPointerDragging = false;
    if (_didElasticPointerMove) {
      _scheduleElasticScrollEnd(); // 处理取消事件，如触摸中断
    }
    _didElasticPointerMove = false;
  }

  void _startElasticUserScroll() {
    _scrollStopTimer?.cancel();
    if (!_isUserScrolling) {
      setState(() {
        _isUserScrolling = true;
      });
    }
  }

  // 根据拖动距离移动所有歌词项
  void _shiftElasticItems(double delta) {
    _startElasticUserScroll();
    // 更新动画代数，防止冲突
    _elasticAnimationGeneration++;
    // 直接写控制器值即可，每行的 AnimatedBuilder 会自己刷新位移
    for (int i = 0; i < _elasticControllers.length; i++) {
      final controller = _elasticControllers[i];
      controller.stop();
      controller.value += delta;
    }
  }

  // 安排滚动结束后自动回到当前播放位置
  void _scheduleElasticScrollEnd() {
    _scrollStopTimer?.cancel();
    _scrollStopTimer = Timer(const Duration(milliseconds: 1000), () {
      if (!mounted) return;
      _isElasticPointerDragging = false;
      setState(() {
        _isUserScrolling = false;
      });
      _animateElasticToCurrent();
    });
  }

  // 测量每个歌词项的实际高度
  void _measureElasticItems(double topPadding, double viewportHeight) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _elasticItemKeys.length != widget.lyrics.length) return;

      bool changed = false;
      for (int i = 0; i < _elasticItemKeys.length; i++) {
        if (_isCollapsedInterlude(i)) continue;
        final context = _elasticItemKeys[i].currentContext;
        final renderObject = context?.findRenderObject();
        if (renderObject is RenderBox && renderObject.hasSize) {
          final height = renderObject.size.height;
          if ((height - _elasticItemHeights[i]).abs() > 0.5) {
            _elasticItemHeights[i] = height;
            changed = true;
          }
        }
      }

      final bool shouldJump = _elasticPendingJump;
      _elasticPendingJump = false;

      if (changed || !_elasticHeightsMeasured) {
        _elasticHeightsMeasured = true;
        _rebuildElasticBasePositions(topPadding: topPadding);
        setState(() {});

        // 切歌/改设置后直接跳到位，换行时走动画
        if (shouldJump) {
          _jumpElasticToCurrent(viewportHeight: viewportHeight);
        } else {
          _animateElasticToCurrent(viewportHeight: viewportHeight);
        }
      }
    });
  }

  // 立即跳转到当前播放的歌词位置
  void _jumpElasticToCurrent({double? viewportHeight}) {
    if (!_hasValidElasticIndex) return;

    _elasticAnimationGeneration++;
    final double center =
        (viewportHeight ?? _currentViewportHeight) * 0.38; // 高亮在0.38的位置
    final double offsetToCenter =
        center - _elasticBaseYPositions[widget.currentIndex];
    for (int i = 0; i < _elasticControllers.length; i++) {
      final double targetY = _elasticBaseYPositions[i] + offsetToCenter;
      _elasticControllers[i].stop();
      _elasticControllers[i].value = targetY;
    }
  }

  void _animateElasticToCurrent({double? viewportHeight, int? previousIndex}) {
    if (!_hasValidElasticIndex || _isUserScrolling) return;

    final double vh = viewportHeight ?? _currentViewportHeight;
    final double center = vh * 0.38;
    final double offsetToCenter =
        center - _elasticBaseYPositions[widget.currentIndex];

    // 上一行移动的行数与时间差
    final int fromIndex = previousIndex ?? _previousIndex;
    final int lineDiff = (widget.currentIndex - fromIndex).abs();

    int timeDiffMs = 1000;
    if (fromIndex >= 0 &&
        fromIndex < widget.lyrics.length &&
        widget.currentIndex >= 0 &&
        widget.currentIndex < widget.lyrics.length) {
      timeDiffMs =
          (widget.lyrics[widget.currentIndex].timestamp -
                  widget.lyrics[fromIndex].timestamp)
              .abs()
              .inMilliseconds;
    }

    // 小于500毫秒或大于7行，不同步延迟
    final bool shouldTriggerWave = timeDiffMs >= 500 && lineDiff <= 7;

    final springDesc = SpringDescription.withDampingRatio(
      mass: 1.0,
      stiffness: 280.0,
      ratio: 0.91,
    );
    const tolerance = Tolerance(distance: 0.1, velocity: 0.5);

    final int generation = ++_elasticAnimationGeneration;
    final int anchorIndex = _estimateElasticAnchorIndex(vh);

    void startSpringAnimation(AnimationController controller, double targetY) {
      if ((controller.value - targetY).abs() < 0.1) {
        controller.value = targetY;
        controller.stop();
        return;
      }

      final double currentVelocity =
          controller.isAnimating && controller.velocity.isFinite
          ? controller.velocity
          : 0.0;

      final simulation = SpringSimulation(
        springDesc,
        controller.value,
        targetY,
        currentVelocity,
        tolerance: tolerance,
      );

      controller.animateWith(simulation).whenCompleteOrCancel(() {
        if (mounted && (controller.value - targetY).abs() < 0.2) {
          controller.value = targetY;
        }
      });
    }

    for (int i = 0; i < widget.lyrics.length; i++) {
      if (i >= _elasticControllers.length) break;

      final double targetY = _elasticBaseYPositions[i] + offsetToCenter;
      final double executionDelay = shouldTriggerWave
          ? _elasticDelayFromAnchor(i, anchorIndex)
          : 0.0;

      if (executionDelay > 0.0) {
        Future.delayed(
          Duration(milliseconds: (executionDelay * 1000).toInt()),
          () {
            if (!mounted ||
                _isUserScrolling ||
                generation != _elasticAnimationGeneration) {
              return;
            }

            startSpringAnimation(_elasticControllers[i], targetY);
          },
        );
      } else {
        startSpringAnimation(_elasticControllers[i], targetY);
      }
    }
  }

  // 计算从锚点到指定索引的延迟时间
  double _elasticDelayFromAnchor(int index, int anchorIndex) {
    int visibleTopIndex = widget.currentIndex;
    for (int i = 0; i < _elasticControllers.length; i++) {
      // 当 value >= -20 时，说明它刚刚好处于屏幕顶端边缘或刚进入屏幕
      if (_elasticControllers[i].value >= -20) {
        visibleTopIndex = i;
        break;
      }
    }

    if (index <= visibleTopIndex) return 0.0;
    if (index <= anchorIndex) return 0.0;

    double delay = 0.0;
    double step = 0.05;

    final double baseHeight = _estimatedElasticItemHeight;
    final int startLoopIndex = math.max(visibleTopIndex, anchorIndex);

    for (int i = startLoopIndex; i < index; i++) {
      if (_isCollapsedInterlude(i)) continue;
      final double itemHeight = (i < _elasticItemHeights.length)
          ? _elasticItemHeights[i]
          : baseHeight;
      // 比值下限钳制为 1.0：短行保持原始步长不缩小（与修改前行为一致）
      // 比标准行更高的行（如含翻译）才等比放大步长，保持视觉波浪一致
      final double heightRatio = math.max(1.0, itemHeight / baseHeight);
      delay += step * heightRatio;
      step /= 1.05;
    }

    return delay;
  }

  // 估算动画的锚点索引（可见位置往上一点）
  int _estimateElasticAnchorIndex(double viewportHeight) {
    if (!_hasValidElasticIndex) return widget.currentIndex;

    final double currentTop = _elasticBaseYPositions[widget.currentIndex];
    final double anchorY =
        currentTop - viewportHeight * 0.88; // 动画触发在不可见的位置，只需要使用它的涟漪就好

    // 前几行上面没有东西作为锚点
    if (anchorY < _elasticBaseYPositions[0]) {
      final double estimatedHeight = _estimatedElasticItemHeight;
      final double missingHeight = _elasticBaseYPositions[0] - anchorY;
      final int virtualOffset = (missingHeight / estimatedHeight).ceil();
      return -virtualOffset;
    }

    int anchorIndex = widget.currentIndex;
    for (int i = widget.currentIndex; i >= 0; i--) {
      if (_elasticBaseYPositions[i] <= anchorY) {
        anchorIndex = i;
        break;
      }
    }
    return anchorIndex;
  }

  bool get _hasValidElasticIndex =>
      widget.currentIndex >= 0 &&
      widget.currentIndex < widget.lyrics.length &&
      _elasticControllers.length == widget.lyrics.length;

  double get _currentViewportHeight {
    final renderObject = context.findRenderObject();
    if (renderObject is RenderBox && renderObject.hasSize) {
      return renderObject.size.height;
    }
    return MediaQuery.of(context).size.height;
  }

  void _disposeElasticControllers() {
    for (final controller in _elasticControllers) {
      controller.dispose();
    }
    _elasticControllers.clear();
  }

  void _resetElasticState() {
    _elasticAnimationGeneration++;
    _elasticRowCache.clear();
    _disposeElasticControllers();
    _elasticItemKeys
      ..clear()
      ..addAll(List.generate(widget.lyrics.length, (_) => GlobalKey()));
    _elasticItemHeights
      ..clear()
      ..addAll(List.filled(widget.lyrics.length, _estimatedElasticItemHeight));
    _elasticBaseYPositions
      ..clear()
      ..addAll(List.filled(widget.lyrics.length, 0));
    _elasticControllers.addAll(
      List.generate(
        widget.lyrics.length,
        (index) => AnimationController.unbounded(vsync: this),
      ),
    );
    _elasticHeightsMeasured = false;
    _elasticNeedsMeasure = true;
    _elasticPendingJump = true;
    _rebuildElasticBasePositions();
    _syncElasticControllersToBase();
  }

  double get _estimatedElasticItemHeight {
    final double fontSize = _lastFontSize ?? 20;
    final double spacing = _lastLyricVerticalSpacing ?? 6;
    return (fontSize * 2.5) + (spacing * 2);
  }

  void _rebuildElasticBasePositions({double topPadding = 0}) {
    double y = topPadding;
    for (int i = 0; i < _elasticItemHeights.length; i++) {
      _elasticBaseYPositions[i] = y;
      y += _elasticItemHeights[i];
    }
  }

  void _syncElasticControllersToBase() {
    for (int i = 0; i < _elasticControllers.length; i++) {
      final double value = _elasticBaseYPositions[i];
      _elasticControllers[i].value = value;
    }
  }
}

class LyricsView extends StatelessWidget {
  final int maxLinesPerLyric;
  final Function(int index)? onTapLine;

  const LyricsView({super.key, this.maxLinesPerLyric = 1, this.onTapLine});

  @override
  Widget build(BuildContext context) {
    final playlistNotifier = Provider.of<PlaylistContentNotifier>(
      context,
      listen: true,
    );

    // 使用StreamBuilder监听播放状态变化，但不是用于直接驱动UI动画
    return StreamBuilder<bool>(
      stream: playlistNotifier.mediaPlayer.stream.playing,
      builder: (context, playingSnapshot) {
        final currentLyricLineIndex = playlistNotifier.currentLyricLineIndex;
        final currentLyrics = playlistNotifier.currentLyrics;

        final lyricsWidget = LyricsWidget(
          lyrics: currentLyrics,
          currentIndex: currentLyricLineIndex,
          maxLinesPerLyric: maxLinesPerLyric,
          onTapLine: onTapLine,
        );

        final settings = Provider.of<SettingsProvider>(context, listen: false);
        final enableLyricBlur = settings.enableLyricBlur;
        final addLyricPadding = settings.addLyricPadding;

        if (enableLyricBlur) {
          return ShaderMask(
            shaderCallback: (Rect bounds) {
              final themeColor = Theme.of(context).colorScheme.onSurface;

              // 如果启用了歌词补位，或者当前行不在顶部/底部，则使用标准stops
              if (addLyricPadding ||
                  (currentLyricLineIndex > 2 &&
                      currentLyricLineIndex < currentLyrics.length - 3) ||
                  currentLyrics.length <= 5) {
                // 使用标准渐变
                return LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    themeColor,
                    themeColor,
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.05, 0.95, 1.0],
                ).createShader(bounds);
              } else {
                // 当前行在顶部附近
                if (currentLyricLineIndex <= 2) {
                  return LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      themeColor,
                      themeColor,
                      themeColor,
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.02, 0.95, 1.0],
                  ).createShader(bounds);
                }
                // 当前行在底部附近
                else {
                  return LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      themeColor,
                      themeColor,
                      themeColor,
                    ],
                    stops: const [0.0, 0.05, 0.98, 1.0],
                  ).createShader(bounds);
                }
              }
            },
            blendMode: BlendMode.dstIn,
            child: lyricsWidget,
          );
        } else {
          return lyricsWidget;
        }
      },
    );
  }
}

// ignore: unused_element
class _LyricsClipper extends CustomClipper<Rect> {
  final double startPercent;
  final double endPercent;

  _LyricsClipper({required this.startPercent, required this.endPercent});

  @override
  Rect getClip(Size size) {
    return Rect.fromLTRB(
      size.width * startPercent,
      0,
      size.width * endPercent,
      size.height,
    );
  }

  @override
  bool shouldReclip(_LyricsClipper oldClipper) {
    return oldClipper.startPercent != startPercent ||
        oldClipper.endPercent != endPercent;
  }
}

class LyricSpringCurve extends Curve {
  final double omega;
  final double zeta;

  const LyricSpringCurve({this.omega = 12.0, this.zeta = 0.95});

  @override
  double transformInternal(double t) {
    if (t <= 0.0) return 0.0;
    if (t >= 1.0) return 1.0;

    final double wd = omega * math.sqrt(1.0 - zeta * zeta);
    final double envelope = math.exp(-zeta * omega * t);
    final double phase =
        math.cos(wd * t) +
        (zeta / math.sqrt(1.0 - zeta * zeta)) * math.sin(wd * t);

    return (1.0 - envelope * phase).clamp(0.0, 1.0);
  }
}

// 弹性滚动里这一行长什么样的缓存条目
class _ElasticRowCacheEntry {
  const _ElasticRowCacheEntry(this.hash, this.widget);

  final int hash;
  final Widget widget;
}

// class LyricSpringCurve extends Curve {
//   final double stiffnessFactor;

//   const LyricSpringCurve({this.stiffnessFactor = 1.0});

//   @override
//   double transformInternal(double t) {
//     final double decay1 = -7.85 * stiffnessFactor;
//     final double decay2 = -20.41 * stiffnessFactor;

//     double getRaw(double time) {
//       final double currentTime = time * 0.55;
//       final double term1 = 1.625 * math.exp(decay1 * currentTime);
//       final double term2 = 0.625 * math.exp(decay2 * currentTime);
//       return 1.0 - term1 + term2;
//     }

//     final double startRaw = getRaw(0.0);
//     final double endRaw = getRaw(1.0);

//     final double normalized = (getRaw(t) - startRaw) / (endRaw - startRaw);

//     final double fade = t * t * (3.0 - 2.0 * t);
//     return normalized + fade * (1.0 - normalized);
//   }
// }
