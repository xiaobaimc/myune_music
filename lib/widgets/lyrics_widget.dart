/*
FIXME: 假设以下格式
`
[00:08.220]First [00:08.412]things [00:08.882]first[00:09.378]
[00:08.220]最初的最初
`
在 _parseLrcContent 方法中 会将第1行检测为卡拉OK格式；

而对于 `[00:08.220]最初的最初` 他没有内部时间戳 解析出"最初的最初"并添加到 groupedLyrics 中

在 LyricsWidget 中 当显示高亮行时，如果检测到该行是卡拉OK格式 即isKaraokeLine为true
则只显示卡拉OK效果 而不会显示同一时间戳下的标准LRC格式译文

当同一时间戳有多种格式的歌词时 会优先处理卡拉OK格式，导致标准LRC格式的译文在高亮行时无法显示

---

2026.1.13 修复了一部分 但仍然治标不治本 但保证了上述的案例可以正常显示
`
[00:00.940]悲[00:01.380]し[00:01.750]み
[00:00.940]沉入悲伤之海的我
[00:00.940]ka na shi mi [00:02.000]no u mi ni shi zu n da wa ta shi 假设这里有时间戳
`
1、3行有时间戳
第2行没有，仍然会导致显示异常

texts列表里有3行，但tokens列表里只有2个元素（因为只有第 1、3 行有时间戳）
如果简单的用循环索引去取，第2行就会错误地去抓取第3行的逐字数据

*/
import 'dart:ui' as ui;
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../page/playlist/playlist_models.dart';
import '../page/setting/settings_provider.dart';
import '../page/playlist/playlist_content_notifier.dart';
import 'interlude_animation_widget.dart';

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
  bool? _lastAddLyricPadding;

  bool _isUserScrolling = false; // 标记用户是否在手动滚动
  Timer? _scrollStopTimer; // 滚动停止检测定时器

  final List<GlobalKey> _elasticItemKeys = [];
  final List<double> _elasticItemHeights = [];
  final List<double> _elasticBaseYPositions = [];
  final List<double> _elasticAnimatedYPositions = [];
  final List<AnimationController> _elasticControllers = [];
  bool _elasticHeightsMeasured = false;
  int _elasticAnimationGeneration = 0;
  bool _isElasticPointerDragging = false;
  bool _didElasticPointerMove = false;
  bool _frameScheduled = false;

  int _previousIndex = 0;

  @override
  void initState() {
    super.initState();

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
    _disposeElasticControllers();
    super.dispose();
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
      _scrollToCurrentLine();
      _animateElasticToCurrent(
        previousIndex: oldWidget.currentIndex,
      ); // 👈 传入旧索引
      _previousIndex = oldWidget.currentIndex;
    }
    // 当歌词列表发生变化时（如切换歌曲），滚动到顶部
    else if (widget.lyrics != oldWidget.lyrics) {
      _resetElasticState();
      // 使用微延迟确保在新歌词加载后执行滚动
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (widget.currentIndex == 0 && _itemScrollController.isAttached) {
          _itemScrollController.jumpTo(index: 0, alignment: 0.0);
        }
        _jumpElasticToCurrent();
      });
    }
  }

  // 滚动方法
  void _scrollToCurrentLine({bool instant = false}) {
    if (!mounted || !_itemScrollController.isAttached) return;

    // 检查索引是否有效
    if (widget.currentIndex < 0 ||
        widget.currentIndex >= widget.lyrics.length) {
      return;
    }

    // 获取设置
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final addLyricPadding = settings.addLyricPadding;
    // 计算实际滚动到的索引（考虑填充项偏移）
    final int actualIndex = addLyricPadding
        ? widget.currentIndex + 1
        : widget.currentIndex;

    if (instant) {
      _itemScrollController.jumpTo(index: actualIndex, alignment: 0.0);
    } else {
      _itemScrollController.scrollTo(
        index: actualIndex,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        alignment: 0.38, // 0.38 看起来更顺眼一点
      );
    }
  }

  // 处理逐字歌词
  Widget _buildMultiLineKaraokeRichText(
    List<List<LyricToken>> multiLineTokens,
    bool isCurrent,
    double fontSize,
    ColorScheme colorScheme,
  ) {
    // 获取当前播放位置和播放状态
    final playlistNotifier = Provider.of<PlaylistContentNotifier>(
      context,
      listen: false,
    );
    final currentPosition = playlistNotifier.currentPosition;
    final isPlaying = playlistNotifier.isPlaying;

    final List<Widget> lines = [];

    final double secondaryFontSize = fontSize * 0.88;
    final Color primaryColor = colorScheme.primary;

    final Color secondaryPrimaryColor = colorScheme.primary.withValues(
      alpha: 0.88,
    );
    final Color secondarySurfaceVariantColor = colorScheme.onSurfaceVariant
        .withValues(alpha: 0.55);

    final Color surfaceVariantColor = colorScheme.onSurfaceVariant.withValues(
      alpha: 0.65,
    );

    for (int lineIndex = 0; lineIndex < multiLineTokens.length; lineIndex++) {
      final List<LyricToken> tokens = multiLineTokens[lineIndex];
      final List<InlineSpan> children = [];

      final bool isSecondaryLine = lineIndex > 0;

      final double lineFontSize = isSecondaryLine
          ? secondaryFontSize
          : fontSize;
      final FontWeight lineFontWeight = isCurrent
          ? (isSecondaryLine ? FontWeight.w600 : FontWeight.w600)
          : (isSecondaryLine ? FontWeight.w400 : FontWeight.w400);
      final Color lineBaseColor = isSecondaryLine
          ? secondarySurfaceVariantColor
          : surfaceVariantColor;
      final Color lineHighlightColor = isSecondaryLine
          ? secondaryPrimaryColor
          : primaryColor;

      for (final token in tokens) {
        children.add(
          WidgetSpan(
            child: AnimatedKaraokeWord(
              text: token.text,
              fontSize: lineFontSize,
              fontWeight: lineFontWeight,
              startTime: token.start,
              duration: token.end - token.start,
              currentTime: currentPosition,
              baseColor: lineBaseColor,
              highlightColor: lineHighlightColor,
              isPlaying: isPlaying,
            ),
          ),
        );
      }

      lines.add(
        Text.rich(
          TextSpan(children: children),
          textAlign: _lastAlignment ?? TextAlign.center,
          textHeightBehavior: const TextHeightBehavior(
            applyHeightToFirstAscent: false,
            applyHeightToLastDescent: false,
          ),
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

  Widget _withLyricEffects({
    required Widget child,
    required TextAlign lyricAlignment,
    required bool isCurrent,
    required bool shouldBlur,
    required int distance,
    required double blurStrength,
  }) {
    final double sigma = _calculateSigma(
      distance,
      shouldBlur,
      isCurrent,
      blurStrength,
    );
    final Widget effectiveChild = sigma == 0.0
        ? child
        : ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
            child: child,
          );

    return AnimatedScale(
      alignment: _getAlignmentFromTextAlign(lyricAlignment),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeInOutSine,
      scale: isCurrent ? 1.02 : 1.0,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        child: effectiveChild,
      ),
    );
  }

  TextStyle _lyricTextStyle({
    required bool isCurrent,
    required bool isSecondaryLine,
    required double fontSize,
    required ColorScheme colorScheme,
  }) {
    final double lineFontSize = isSecondaryLine ? fontSize * 0.88 : fontSize;
    final FontWeight lineFontWeight = isCurrent
        ? (isSecondaryLine ? FontWeight.w600 : FontWeight.w600)
        : (isSecondaryLine ? FontWeight.w400 : FontWeight.w400);
    final Color lineColor = isCurrent
        ? (isSecondaryLine
              ? colorScheme.primary.withValues(alpha: 0.88)
              : colorScheme.primary)
        : (isSecondaryLine
              ? colorScheme.onSurfaceVariant.withValues(alpha: 0.58)
              : colorScheme.onSurfaceVariant.withValues(alpha: 0.7));

    return TextStyle(
      fontSize: lineFontSize,
      height: 1.2,
      color: lineColor,
      fontWeight: lineFontWeight,
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
      textHeightBehavior: const TextHeightBehavior(
        applyHeightToFirstAscent: false,
        applyHeightToLastDescent: false,
      ),
    );
  }

  Widget _buildLyricItem({
    required int lyricIndex,
    required double maxWidth,
    required double fontSize,
    required double lyricVerticalSpacing,
    required TextAlign lyricAlignment,
    required bool shouldBlur,
    required ColorScheme colorScheme,
    required double blurStrength,
  }) {
    final line = widget.lyrics[lyricIndex];
    final isCurrent = lyricIndex == widget.currentIndex;
    final int distance = (lyricIndex - widget.currentIndex).abs();
    final List<Widget> columnChildren = [];
    int renderedLines = 0;
    final int maxAllowed = widget.maxLinesPerLyric;
    final int karaokeCount = (line.tokens != null) ? line.tokens!.length : 0;

    if (line.isInterlude) {
      // 间奏逻辑延后到最后处理，因为它需要直接包裹整个 Padding
    } else if (isCurrent && line.isKaraoke) {
      final int linesToTake = (karaokeCount > maxAllowed)
          ? maxAllowed
          : karaokeCount;
      final List<List<LyricToken>> tokensToRender = line.tokens!
          .take(linesToTake)
          .toList();

      renderedLines += linesToTake;

      columnChildren.add(
        _withLyricEffects(
          lyricAlignment: lyricAlignment,
          isCurrent: isCurrent,
          shouldBlur: shouldBlur,
          distance: distance,
          blurStrength: blurStrength,
          child: _buildMultiLineKaraokeRichText(
            tokensToRender,
            isCurrent,
            fontSize,
            colorScheme,
          ),
        ),
      );
    } else {
      final int mainLinesLimit = (karaokeCount > 0 ? karaokeCount : 1);
      final int linesToTake = (mainLinesLimit > maxAllowed)
          ? maxAllowed
          : mainLinesLimit;

      for (int i = 0; i < linesToTake && i < line.texts.length; i++) {
        renderedLines++;

        final bool isSecondaryLine = i > 0;

        final Widget staticText = _buildStaticLyricText(
          text: line.texts[i],
          lyricAlignment: lyricAlignment,
          style: _lyricTextStyle(
            isCurrent: isCurrent,
            isSecondaryLine: isSecondaryLine,
            fontSize: fontSize,
            colorScheme: colorScheme,
          ),
        );

        columnChildren.add(
          _withLyricEffects(
            lyricAlignment: lyricAlignment,
            isCurrent: isCurrent,
            shouldBlur: shouldBlur,
            distance: distance,
            blurStrength: blurStrength,
            child: staticText,
          ),
        );
        if (i < linesToTake - 1) {
          columnChildren.add(const SizedBox(height: 6));
        }
      }
    }

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

        final Widget translationWidget = _buildStaticLyricText(
          text: line.texts[i],
          lyricAlignment: lyricAlignment,
          style: _lyricTextStyle(
            isCurrent: isCurrent,
            isSecondaryLine: true,
            fontSize: fontSize,
            colorScheme: colorScheme,
          ),
        );

        columnChildren.add(
          _withLyricEffects(
            lyricAlignment: lyricAlignment,
            isCurrent: isCurrent,
            shouldBlur: shouldBlur,
            distance: distance,
            blurStrength: blurStrength,
            child: translationWidget,
          ),
        );

        if (i < line.texts.length - 1 && renderedLines < maxAllowed) {
          columnChildren.add(const SizedBox(height: 6));
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
                const EdgeInsets.fromLTRB(12, 9, 12, 9),
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
              child: _withLyricEffects(
                lyricAlignment: lyricAlignment,
                isCurrent: isCurrent,
                shouldBlur: shouldBlur,
                distance: distance,
                blurStrength: blurStrength,
                child: Container(
                  height: fontSize * 1.5,
                  alignment: _getAlignmentFromTextAlign(lyricAlignment),
                  padding: EdgeInsets.only(
                    left: lyricAlignment == TextAlign.left ? fontSize * 0.5 : 0,
                    right: lyricAlignment == TextAlign.right
                        ? fontSize * 0.5
                        : 0,
                  ),
                  child: InterludeAnimationWidget(
                    isCurrent: isCurrent,
                    baseColor: colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.65,
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
          ),
        );

        return TweenAnimationBuilder<double>(
          key: ValueKey('interlude_elastic_$lyricIndex'),
          tween: Tween<double>(begin: 0.0, end: 1.0),
          // 前 300ms 等待弹性滚动推开，后 200ms 淡入并放大圆点
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
    required double lyricVerticalSpacing,
    required TextAlign lyricAlignment,
    required bool addLyricPadding,
    required bool shouldBlur,
    required ColorScheme colorScheme,
    required double blurStrength,
  }) {
    if (_elasticControllers.length != widget.lyrics.length) {
      _resetElasticState();
    }

    final double paddingHeight = addLyricPadding ? viewportHeight * 0.37 : 0;
    _rebuildElasticBasePositions(topPadding: paddingHeight);
    _measureElasticItems(paddingHeight, viewportHeight);

    final double contentHeight =
        paddingHeight +
        _elasticItemHeights.fold<double>(0, (sum, height) => sum + height) +
        paddingHeight;

    double stabilizeOffset(double value, double target) {
      final diff = value - target;

      if (diff.abs() < 0.3) {
        return target;
      }

      return value;
    }

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
                  final renderOffset = stabilizeOffset(
                    _elasticControllers[index].value,
                    _elasticBaseYPositions[index],
                  );
                  return Positioned(
                    top: 0, // 固定top，交给Transform.translate处理
                    left: 0,
                    right: 0,

                    child: Transform.translate(
                      offset: Offset(0, renderOffset),
                      child: RepaintBoundary(
                        child: KeyedSubtree(
                          key: _elasticItemKeys[index],
                          child: _buildLyricItem(
                            lyricIndex: index,
                            maxWidth: maxWidth,
                            fontSize: fontSize,
                            lyricVerticalSpacing: lyricVerticalSpacing,
                            lyricAlignment: lyricAlignment,
                            shouldBlur: shouldBlur,
                            colorScheme: colorScheme,
                            blurStrength: blurStrength,
                          ),
                        ),
                      ),
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
    final fontSize = context.select<SettingsProvider, double>(
      (s) => s.fontSize,
    );
    final lyricVerticalSpacing = context.select<SettingsProvider, double>(
      (s) => s.lyricVerticalSpacing,
    );
    final addLyricPadding = context.select<SettingsProvider, bool>(
      (s) => s.addLyricPadding,
    );
    final enableLyricBlur = context.select<SettingsProvider, bool>(
      (s) => s.enableLyricBlur,
    );
    final enableLyricElasticScroll = context.select<SettingsProvider, bool>(
      (s) => s.enableLyricElasticScroll,
    );
    final lyricBlurStrength = context.select<SettingsProvider, double>(
      (s) => s.lyricBlurStrength,
    );

    final bool shouldBlur = enableLyricBlur && !_isUserScrolling;

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
            _lastAddLyricPadding != addLyricPadding;

        if (settingsChanged) {
          // 更新记录的值
          _lastEstimatedMaxWidth = maxWidth;
          _lastFontSize = fontSize;
          _lastAlignment = lyricAlignment;
          _lastMaxLinesPerLyric = widget.maxLinesPerLyric;
          _lastLyricVerticalSpacing = lyricVerticalSpacing;
          _lastAddLyricPadding = addLyricPadding;

          // 使用 Future.delayed 将滚动任务推迟到下一事件循环
          // 增加延迟用于确保布局完全稳定
          Future.delayed(const Duration(milliseconds: 50), () {
            if (mounted) {
              _scrollToCurrentLine(instant: false);
              _elasticHeightsMeasured = false;
              _animateElasticToCurrent();
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
            lyricVerticalSpacing: lyricVerticalSpacing,
            lyricAlignment: lyricAlignment,
            addLyricPadding: addLyricPadding,
            shouldBlur: shouldBlur,
            colorScheme: colorScheme,
            blurStrength: lyricBlurStrength,
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
                final isCurrent = lyricIndex == widget.currentIndex;

                line.texts.take(widget.maxLinesPerLyric);

                // 计算当前行与目标行之间的距离
                final int distance = (lyricIndex - widget.currentIndex).abs();

                // 根据距离计算模糊值，距离越远模糊越大
                double calculateSigma(int distance) {
                  if (!shouldBlur || isCurrent) return 0.0;

                  const int maxDistance = 5;
                  final double normalizedDistance = (distance / maxDistance)
                      .clamp(0.0, 1.0);
                  return normalizedDistance * lyricBlurStrength;
                }

                final List<Widget> columnChildren = [];
                int renderedLines = 0;
                final int maxAllowed = widget.maxLinesPerLyric;

                // 确定有多少行属于卡拉OK原文（如：日语原文+罗马音）
                final int karaokeCount = (line.tokens != null)
                    ? line.tokens!.length
                    : 0;

                if (line.isInterlude) {
                  // 间奏逻辑由外层统一包裹 AnimatedSize 处理
                } else if (isCurrent && line.isKaraoke) {
                  // 限制卡拉OK显示的行数，不能超过总限制
                  final int linesToTake = (karaokeCount > maxAllowed)
                      ? maxAllowed
                      : karaokeCount;
                  final List<List<LyricToken>> tokensToRender = line.tokens!
                      .take(linesToTake)
                      .toList();

                  renderedLines += linesToTake;

                  columnChildren.add(
                    AnimatedScale(
                      alignment: _getAlignmentFromTextAlign(lyricAlignment),
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeInOutSine,
                      scale: isCurrent ? 1.02 : 1,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        child: isCurrent || !shouldBlur
                            ? _buildMultiLineKaraokeRichText(
                                tokensToRender,
                                isCurrent,
                                fontSize,
                                colorScheme,
                              )
                            : ImageFiltered(
                                imageFilter: ui.ImageFilter.blur(
                                  sigmaX: calculateSigma(distance),
                                  sigmaY: calculateSigma(distance),
                                ),
                                child: _buildMultiLineKaraokeRichText(
                                  tokensToRender,
                                  isCurrent,
                                  fontSize,
                                  colorScheme,
                                ),
                              ),
                      ),
                    ),
                  );
                } else {
                  final int mainLinesLimit = (karaokeCount > 0
                      ? karaokeCount
                      : 1);
                  final int linesToTake = (mainLinesLimit > maxAllowed)
                      ? maxAllowed
                      : mainLinesLimit;

                  // 预计算样式变量
                  final double secondaryFontSize = fontSize * 0.88;
                  final Color primaryColor = colorScheme.primary;
                  final Color secondaryPrimaryColor = colorScheme.primary
                      .withValues(alpha: 0.88);
                  final Color surfaceVariantColor = colorScheme.onSurfaceVariant
                      .withValues(alpha: 0.7);
                  final Color secondarySurfaceVariantColor = colorScheme
                      .onSurfaceVariant
                      .withValues(alpha: 0.58);

                  for (
                    int i = 0;
                    i < linesToTake && i < line.texts.length;
                    i++
                  ) {
                    renderedLines++;

                    final bool isSecondaryLine = i > 0;

                    final double lineFontSize = isSecondaryLine
                        ? secondaryFontSize
                        : fontSize;
                    final FontWeight lineFontWeight = isCurrent
                        ? (isSecondaryLine ? FontWeight.w600 : FontWeight.w600)
                        : (isSecondaryLine ? FontWeight.w400 : FontWeight.w400);
                    final Color lineColor = isCurrent
                        ? (isSecondaryLine
                              ? secondaryPrimaryColor
                              : primaryColor)
                        : (isSecondaryLine
                              ? secondarySurfaceVariantColor
                              : surfaceVariantColor);

                    final Widget staticText = Text(
                      line.texts[i],
                      textAlign: lyricAlignment,
                      style: TextStyle(
                        fontSize: lineFontSize,
                        height: 1.2,
                        color: lineColor,
                        fontWeight: lineFontWeight,
                      ),
                      textHeightBehavior: const TextHeightBehavior(
                        applyHeightToFirstAscent: false,
                        applyHeightToLastDescent: false,
                      ),
                    );

                    columnChildren.add(
                      AnimatedScale(
                        alignment: _getAlignmentFromTextAlign(lyricAlignment),
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeInOutSine,
                        scale: isCurrent ? 1.02 : 1.0,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          child: isCurrent || !shouldBlur
                              ? staticText
                              : ImageFiltered(
                                  imageFilter: ui.ImageFilter.blur(
                                    sigmaX: calculateSigma(distance),
                                    sigmaY: calculateSigma(distance),
                                  ),
                                  child: staticText,
                                ),
                        ),
                      ),
                    );
                    if (i < linesToTake - 1) {
                      columnChildren.add(const SizedBox(height: 6));
                    }
                  }
                }

                final int translationStartIndex = (karaokeCount > 0
                    ? karaokeCount
                    : 1);

                if (renderedLines < maxAllowed &&
                    line.texts.length > translationStartIndex) {
                  columnChildren.add(const SizedBox(height: 6));

                  for (
                    int i = translationStartIndex;
                    i < line.texts.length && renderedLines < maxAllowed;
                    i++
                  ) {
                    renderedLines++;

                    final Widget translationWidget = Text(
                      line.texts[i],
                      textAlign: lyricAlignment,
                      style: TextStyle(
                        fontSize: fontSize * 0.88,
                        height: 1.2,
                        color: isCurrent
                            ? colorScheme.primary.withValues(alpha: 0.88)
                            : colorScheme.onSurfaceVariant.withValues(
                                alpha: 0.58,
                              ),
                        fontWeight: isCurrent
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                      textHeightBehavior: const TextHeightBehavior(
                        applyHeightToFirstAscent: false,
                        applyHeightToLastDescent: false,
                      ),
                    );

                    columnChildren.add(
                      AnimatedScale(
                        alignment: _getAlignmentFromTextAlign(lyricAlignment),
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeInOutSine,
                        scale: isCurrent ? 1.02 : 1,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          child: isCurrent || !shouldBlur
                              ? translationWidget
                              : ImageFiltered(
                                  imageFilter: ui.ImageFilter.blur(
                                    sigmaX: calculateSigma(distance),
                                    sigmaY: calculateSigma(distance),
                                  ),
                                  child: translationWidget,
                                ),
                        ),
                      ),
                    );

                    // 如果还有下一行且没达到上限，添加间距
                    if (i < line.texts.length - 1 &&
                        renderedLines < maxAllowed) {
                      columnChildren.add(const SizedBox(height: 6));
                    }
                  }
                }

                Widget itemWidget = Padding(
                  padding: EdgeInsets.symmetric(
                    vertical:
                        lyricVerticalSpacing +
                        0.4 * (fontSize / 2), // 补偿行高减少的部分
                    horizontal: 4,
                  ),
                  child: Align(
                    alignment: _getAlignmentFromTextAlign(lyricAlignment),
                    child: SizedBox(
                      width: maxWidth,
                      child: TextButton(
                        onPressed: () {
                          widget.onTapLine?.call(lyricIndex);
                          // 如果当前处于暂停状态，则开始播放
                          final playlistNotifier =
                              Provider.of<PlaylistContentNotifier>(
                                context,
                                listen: false,
                              );
                          if (!playlistNotifier.isPlaying) {
                            playlistNotifier.play();
                          }
                        },
                        style: ButtonStyle(
                          padding: WidgetStateProperty.all<EdgeInsets>(
                            const EdgeInsets.fromLTRB(12, 9, 12, 9),
                          ),
                          shape:
                              WidgetStateProperty.all<RoundedRectangleBorder>(
                                RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                          backgroundColor:
                              WidgetStateProperty.resolveWith<Color>((
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
                    final playlistNotifier =
                        Provider.of<PlaylistContentNotifier>(
                          context,
                          listen: false,
                        );
                    final Widget interludeWidget = Container(
                      height: fontSize * 1.5,
                      alignment: _getAlignmentFromTextAlign(lyricAlignment),
                      padding: EdgeInsets.only(
                        left: lyricAlignment == TextAlign.left
                            ? fontSize * 0.5
                            : 0,
                        right: lyricAlignment == TextAlign.right
                            ? fontSize * 0.5
                            : 0,
                      ),
                      child: InterludeAnimationWidget(
                        isCurrent: isCurrent,
                        baseColor: colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.65,
                        ),
                        highlightColor: colorScheme.primary.withValues(
                          alpha: 0.88,
                        ),
                        startTime: line.timestamp,
                        interludeDuration:
                            line.interludeDuration ?? Duration.zero,
                        currentTime: playlistNotifier.currentPosition,
                        isPlaying: playlistNotifier.isPlaying,
                      ),
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
                          child: AnimatedScale(
                            alignment: _getAlignmentFromTextAlign(
                              lyricAlignment,
                            ),
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeInOutSine,
                            scale: 1.02,
                            child: isCurrent || !shouldBlur
                                ? interludeWidget
                                : ImageFiltered(
                                    imageFilter: ui.ImageFilter.blur(
                                      sigmaX: calculateSigma(distance),
                                      sigmaY: calculateSigma(distance),
                                    ),
                                    child: interludeWidget,
                                  ),
                          ),
                        ),
                      ),
                    );
                  }
                  return AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    onEnd: () {
                      if (!isCurrent && mounted && !enableLyricElasticScroll) {
                        // 在普通滚动模式下，间奏折叠（高度从完整变0）会导致后续列表项瞬间上移
                        // 从而导致原本居中对齐的目标位置偏上
                        // 在高度收缩动画结束后，再补发一次滚动，将位置修正回来
                        _scrollToCurrentLine();
                      }
                    },
                    child: isCurrent
                        ? TweenAnimationBuilder<double>(
                            key: ValueKey('interlude_normal_$lyricIndex'),
                            tween: Tween<double>(begin: 0.0, end: 1.0),
                            duration: const Duration(milliseconds: 500),
                            builder: (context, value, child) {
                              final double dotValue = ((value - 0.6) / 0.4)
                                  .clamp(0.0, 1.0);
                              return Opacity(opacity: dotValue, child: child);
                            },
                            child: itemWidget,
                          )
                        : const SizedBox.shrink(),
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
    // 防止监听器响应
    for (int i = 0; i < _elasticControllers.length; i++) {
      final controller = _elasticControllers[i];
      controller.stop();
      controller.value += delta;
      _elasticAnimatedYPositions[i] = controller.value;
    }
    if (mounted) setState(() {});
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

      if (changed || !_elasticHeightsMeasured) {
        final bool shouldJump = !_elasticHeightsMeasured;
        _elasticHeightsMeasured = true;
        _rebuildElasticBasePositions(topPadding: topPadding);
        setState(() {});

        // 首次直接跳转到当前位置，后续使用动画过渡
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
      _elasticAnimatedYPositions[i] = targetY;
    }
    if (mounted) setState(() {});
  }

  void _animateElasticToCurrent({double? viewportHeight, int? previousIndex}) {
    if (!_hasValidElasticIndex || _isUserScrolling) return;

    final double vh = viewportHeight ?? _currentViewportHeight;
    final double center = vh * 0.38;
    final double offsetToCenter =
        center - _elasticBaseYPositions[widget.currentIndex];

    // 用两句之间的位移距离计算ratio
    final int fromIndex = previousIndex ?? _previousIndex;
    final double fromY =
        (fromIndex >= 0 && fromIndex < _elasticBaseYPositions.length)
        ? _elasticBaseYPositions[fromIndex]
        : _elasticBaseYPositions[widget.currentIndex];
    final double toY = _elasticBaseYPositions[widget.currentIndex];

    final double stepDistance = (toY - fromY).abs();

    // _estimatedElasticItemHeight 就是"一步"的参考单位
    final double ratio = (stepDistance / _estimatedElasticItemHeight).clamp(
      0.5,
      4.0,
    );

    final int durationMs = (480 * math.pow(ratio, 0.55)).round().clamp(
      300,
      750,
    );
    final double omega = (10.5 * math.pow(ratio, 0.45)).clamp(6.5, 15.5);
    const double zeta = 0.91;

    final curve = LyricSpringCurve(omega: omega, zeta: zeta);
    final duration = Duration(milliseconds: durationMs);

    final int generation = ++_elasticAnimationGeneration;
    final int anchorIndex = _estimateElasticAnchorIndex(vh);

    for (int i = 0; i < widget.lyrics.length; i++) {
      if (i >= _elasticControllers.length) break;

      final double targetY = _elasticBaseYPositions[i] + offsetToCenter;
      final double executionDelay = _elasticDelayFromAnchor(i, anchorIndex);

      Future.delayed(
        Duration(milliseconds: (executionDelay * 1000).toInt()),
        () {
          if (!mounted ||
              _isUserScrolling ||
              generation != _elasticAnimationGeneration) {
            return;
          }

          final controller = _elasticControllers[i];

          // 避免微小差距闪烁
          if ((controller.value - targetY).abs() < 0.2) {
            controller.value = targetY;
            controller.stop();
            return;
          }

          controller.stop();
          controller.animateTo(targetY, duration: duration, curve: curve);
        },
      );
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
    double step = 0.045;

    final int startLoopIndex = math.max(visibleTopIndex, anchorIndex);

    for (int i = startLoopIndex; i < index; i++) {
      delay += step;
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
    _elasticAnimatedYPositions
      ..clear()
      ..addAll(List.filled(widget.lyrics.length, 0));
    _elasticControllers.addAll(
      List.generate(widget.lyrics.length, (index) {
        final controller = AnimationController.unbounded(vsync: this);
        controller.addListener(() {
          _elasticAnimatedYPositions[index] = controller.value;

          _scheduleFrame();
        });
        return controller;
      }),
    );
    _elasticHeightsMeasured = false;
    _rebuildElasticBasePositions();
    _syncElasticControllersToBase();
  }

  void _scheduleFrame() {
    if (_frameScheduled) return;

    _frameScheduled = true;

    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {});
      }
      _frameScheduled = false;
    });
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
      _elasticAnimatedYPositions[i] = value;
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

class AnimatedKaraokeWord extends StatefulWidget {
  final String text;
  final double fontSize;
  final FontWeight fontWeight;
  final Duration startTime;
  final Duration duration;
  final Duration currentTime;
  final Color baseColor;
  final Color highlightColor;
  final bool isPlaying;

  const AnimatedKaraokeWord({
    super.key,
    required this.text,
    required this.fontSize,
    required this.fontWeight,
    required this.startTime,
    required this.duration,
    required this.currentTime,
    required this.baseColor,
    required this.highlightColor,
    required this.isPlaying,
  });

  @override
  State<AnimatedKaraokeWord> createState() => _AnimatedKaraokeWordState();
}

class _AnimatedKaraokeWordState extends State<AnimatedKaraokeWord>
    with TickerProviderStateMixin {
  late ValueNotifier<double> _progressNotifier;
  Duration _lastAudioTime = Duration.zero;
  DateTime? _lastAudioUpdateTime;
  Duration _uiTime = Duration.zero;
  Ticker? _ticker;

  @override
  void initState() {
    super.initState();
    _progressNotifier = ValueNotifier<double>(0.0);

    _lastAudioTime = widget.currentTime;
    _lastAudioUpdateTime = DateTime.now();

    _startTicker();
  }

  @override
  void didUpdateWidget(AnimatedKaraokeWord oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 检查音频时间是否更新
    if (oldWidget.currentTime != widget.currentTime) {
      _lastAudioTime = widget.currentTime;
      _lastAudioUpdateTime = DateTime.now();
    }

    // 检查播放状态是否变化
    if (oldWidget.isPlaying != widget.isPlaying) {
      if (widget.isPlaying) {
        // 从暂停恢复播放，更新参考时间
        _lastAudioUpdateTime = DateTime.now();
      }
    }
  }

  void _startTicker() {
    // 创建一个每帧更新的Ticker
    _ticker = createTicker((elapsed) {
      if (widget.isPlaying) {
        // 基于上次音频时间 + 经过的时间
        if (_lastAudioUpdateTime != null) {
          final now = DateTime.now();
          final timeSinceLastUpdate = now.difference(_lastAudioUpdateTime!);
          _uiTime = _lastAudioTime + timeSinceLastUpdate;
        }
      } else {
        _uiTime = _lastAudioTime;
      }

      // 更新进度值
      final progress = _calculateProgress(_uiTime).clamp(0.0, 1.0);
      _progressNotifier.value = progress;
    });
    _ticker!.start();
  }

  double _calculateProgress(Duration currentTime) {
    if (currentTime < widget.startTime) {
      return 0.0;
    } else if (currentTime >= widget.startTime + widget.duration) {
      return 1.0;
    } else {
      final elapsed = (currentTime - widget.startTime).inMilliseconds
          .toDouble();
      final total = widget.duration.inMilliseconds.toDouble();
      return total > 0 ? elapsed / total : 0.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: _progressNotifier,
      builder: (context, progress, child) {
        return Stack(
          children: [
            ClipRect(
              clipper: _LyricsClipper(startPercent: progress, endPercent: 1.0),
              child: Text(
                widget.text,
                style: TextStyle(
                  fontSize: widget.fontSize,
                  fontWeight: widget.fontWeight,
                  color: widget.baseColor,
                  height: 1.2,
                ),
                textHeightBehavior: const TextHeightBehavior(
                  applyHeightToFirstAscent: false,
                  applyHeightToLastDescent: false,
                ),
              ),
            ),

            ClipRect(
              clipper: _LyricsClipper(startPercent: 0.0, endPercent: progress),
              child: Text(
                widget.text,
                style: TextStyle(
                  fontSize: widget.fontSize,
                  fontWeight: widget.fontWeight,
                  color: widget.highlightColor,
                  height: 1.2,
                ),
                textHeightBehavior: const TextHeightBehavior(
                  applyHeightToFirstAscent: false,
                  applyHeightToLastDescent: false,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _ticker?.stop();
    _ticker?.dispose();
    _progressNotifier.dispose();
    super.dispose();
  }
}

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
