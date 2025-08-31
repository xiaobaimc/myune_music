import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    // 首次构建后滚动到当前行
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollToCurrentLine(instant: true),
    );
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

    if (instant) {
      _itemScrollController.jumpTo(index: widget.currentIndex, alignment: 0.0);
    } else {
      _itemScrollController.scrollTo(
        index: widget.currentIndex,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        alignment: 0.4, // 0.4 看起来更顺眼一点
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

    return LayoutBuilder(
      builder: (context, constraints) {
        // 与下方 Container 宽度保持一致（减去 padding）
        final double maxWidth = constraints.maxWidth - 12;

        final bool settingsChanged =
            _lastEstimatedMaxWidth != maxWidth ||
            _lastFontSize != fontSize ||
            _lastAlignment != lyricAlignment ||
            _lastMaxLinesPerLyric != widget.maxLinesPerLyric ||
            _lastLyricVerticalSpacing != lyricVerticalSpacing;

        if (settingsChanged) {
          // 更新记录的值
          _lastEstimatedMaxWidth = maxWidth;
          _lastFontSize = fontSize;
          _lastAlignment = lyricAlignment;
          _lastMaxLinesPerLyric = widget.maxLinesPerLyric;
          _lastLyricVerticalSpacing = lyricVerticalSpacing;

          // 使用 Future.delayed 将滚动任务推迟到下一事件循环
          // 增加延迟用于确保布局完全稳定
          Future.delayed(const Duration(milliseconds: 50), () {
            if (mounted) {
              _scrollToCurrentLine(instant: false);
            }
          });
        }

        return ScrollConfiguration(
          behavior: const ScrollBehavior().copyWith(scrollbars: false),
          child: ScrollablePositionedList.builder(
            itemScrollController: _itemScrollController,
            itemPositionsListener: _itemPositionsListener,
            itemCount: widget.lyrics.length,
            itemBuilder: (context, index) {
              final line = widget.lyrics[index];
              final isCurrent = index == widget.currentIndex;
              final visibleTexts = line.texts.take(widget.maxLinesPerLyric);

              final List<Widget> columnChildren = [
                for (final text in visibleTexts)
                  Text(
                    text,
                    textAlign: lyricAlignment,
                    style: TextStyle(
                      fontSize: fontSize, // 动态字体大小
                      height: 1.6,
                      color: isCurrent
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                      fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
              ];

              return Padding(
                padding: EdgeInsets.symmetric(
                  vertical: lyricVerticalSpacing,
                  horizontal: 4,
                ),
                child: Align(
                  alignment: _getAlignmentFromTextAlign(lyricAlignment),
                  child: SizedBox(
                    width: maxWidth,
                    child: TextButton(
                      onPressed: () {
                        widget.onTapLine?.call(index);
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
                        shape: WidgetStateProperty.all<RoundedRectangleBorder>(
                          RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        backgroundColor: WidgetStateProperty.resolveWith<Color>(
                          (Set<WidgetState> states) {
                            if (states.contains(WidgetState.hovered)) {
                              return Colors.grey.withValues(alpha: 0.2);
                            }
                            return Colors.transparent;
                          },
                        ),
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

        return LyricsWidget(
          lyrics: currentLyrics,
          currentIndex: currentLyricLineIndex,
          maxLinesPerLyric: maxLinesPerLyric,
          onTapLine: onTapLine,
        );
      },
    );
  }
}
