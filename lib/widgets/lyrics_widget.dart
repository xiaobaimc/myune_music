import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'dart:ui' as ui;
import 'dart:async';
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
                final visibleTexts = line.texts.take(widget.maxLinesPerLyric);

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

                for (int i = 0; i < visibleTexts.length; i++) {
                  final textWidget = Text(
                    visibleTexts.elementAt(i),
                    textAlign: lyricAlignment,
                    style: TextStyle(
                      fontSize: fontSize, // 动态字体大小
                      height: 1.2,
                      color: isCurrent
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                      fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
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
                            ? textWidget
                            : ImageFiltered(
                                imageFilter: ui.ImageFilter.blur(
                                  sigmaX: calculateSigma(distance),
                                  sigmaY: calculateSigma(distance),
                                ),
                                child: textWidget,
                              ),
                      ),
                    ),
                  );

                  // 在每行歌词之间添加间距（除了最后一行）
                  if (i < visibleTexts.length - 1) {
                    columnChildren.add(const SizedBox(height: 10));
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

    return StreamBuilder<int>(
      stream: playlistNotifier.lyricLineIndexStream,
      initialData: playlistNotifier.currentLyricLineIndex,
      builder: (context, snapshot) {
        final currentLyricLineIndex = snapshot.data ?? -1;
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
