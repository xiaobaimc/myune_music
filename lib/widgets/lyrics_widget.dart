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

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../page/playlist/playlist_models.dart';
import '../page/setting/settings_provider.dart';
import '../page/playlist/playlist_content_notifier.dart';

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

class _LyricsWidgetState extends State<LyricsWidget> {
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

  @override
  void initState() {
    super.initState();
    // 首次构建后滚动到当前行
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollToCurrentLine(instant: true),
    );
  }

  @override
  void dispose() {
    _scrollStopTimer?.cancel();
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
    }
    // 当歌词列表发生变化时（如切换歌曲），滚动到顶部
    else if (widget.lyrics != oldWidget.lyrics) {
      // 使用微延迟确保在新歌词加载后执行滚动
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (widget.currentIndex == 0 && _itemScrollController.isAttached) {
          _itemScrollController.jumpTo(index: 0, alignment: 0.0);
        }
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

    // 这里通常应该保持与普通Text的颜色一致
    // 但是在AnimatedKaraokeWord.build里，Stack里两层Text 而且两层颜色都是半透明
    // 这会导致 alpha 被叠加混合，而普通歌词只画了一次
    // 这里简单粗暴计算 alpha_eff = 1 - (1 - alpha_new) * (1 - alpha_new) ≈ 0.88
    // 得出alpha_new大约为0.6536
    final Color secondaryPrimaryColor = colorScheme.primary.withValues(
      alpha: 0.65,
    );
    final Color secondarySurfaceVariantColor = colorScheme.onSurfaceVariant
        .withValues(alpha: 0.58);

    final Color surfaceVariantColor = colorScheme.onSurfaceVariant.withValues(
      alpha: 0.7,
    );

    for (int lineIndex = 0; lineIndex < multiLineTokens.length; lineIndex++) {
      final List<LyricToken> tokens = multiLineTokens[lineIndex];
      final List<InlineSpan> children = [];

      final bool isSecondaryLine = lineIndex > 0;

      final double lineFontSize = isSecondaryLine
          ? secondaryFontSize
          : fontSize;
      final FontWeight lineFontWeight = isCurrent
          ? (isSecondaryLine ? FontWeight.w600 : FontWeight.w700)
          : (isSecondaryLine ? FontWeight.w400 : FontWeight.w500);
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
            }
          });
        }

        // 计算填充项数量，如果启用补位则添加1个填充项，否则不添加
        final int paddingItemCount = addLyricPadding ? 1 : 0;
        // 实际的歌词行数
        final int actualLyricsCount = widget.lyrics.length;
        // 总的项数（包括填充项）
        final int totalItemCount = actualLyricsCount + 2 * paddingItemCount;

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

                  // 针对小范围歌词显示进行优化
                  const double maxSigma = 2.5;
                  const int maxDistance = 5;

                  // 使用线性函数创建平滑的过渡效果
                  double normalizedDistance = distance / maxDistance;
                  if (normalizedDistance > 1.0) normalizedDistance = 1.0;

                  // 简单线性过渡，确保相邻行差异较小
                  return normalizedDistance * maxSigma;
                }

                final List<Widget> columnChildren = [];
                int renderedLines = 0;
                final int maxAllowed = widget.maxLinesPerLyric;

                // 确定有多少行属于卡拉OK原文（如：日语原文+罗马音）
                final int karaokeCount = (line.tokens != null)
                    ? line.tokens!.length
                    : 0;

                if (isCurrent && line.isKaraoke) {
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
                        ? (isSecondaryLine ? FontWeight.w600 : FontWeight.w700)
                        : (isSecondaryLine ? FontWeight.w400 : FontWeight.w500);
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

                return Padding(
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
    return ValueListenableBuilder(
      valueListenable: _progressNotifier,
      builder: (context, progress, child) {
        return Stack(
          children: [
            // 基础颜色文字
            Text(
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
            // 高亮颜色文字
            ClipRect(
              clipper: _TextClipper(progress),
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

class _TextClipper extends CustomClipper<Rect> {
  final double progress;

  _TextClipper(this.progress);

  @override
  Rect getClip(Size size) {
    return Rect.fromLTWH(0, 0, size.width * progress, size.height);
  }

  @override
  bool shouldReclip(_TextClipper oldClipper) {
    return oldClipper.progress != progress;
  }
}
