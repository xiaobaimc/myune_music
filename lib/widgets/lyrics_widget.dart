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
  int? _hoveredIndex;

  double? _lastEstimatedMaxWidth;
  double? _lastFontSize;
  TextAlign? _lastAlignment;
  int? _lastMaxLinesPerLyric;

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
      _itemScrollController.jumpTo(index: widget.currentIndex, alignment: 0.5);
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

    return LayoutBuilder(
      builder: (context, constraints) {
        // 与下方 Container 宽度保持一致（减去 padding）
        final double maxWidth = constraints.maxWidth - 12;

        final bool settingsChanged =
            _lastEstimatedMaxWidth != maxWidth ||
            _lastFontSize != fontSize ||
            _lastAlignment != lyricAlignment ||
            _lastMaxLinesPerLyric != widget.maxLinesPerLyric;

        if (settingsChanged) {
          // 更新记录的值
          _lastEstimatedMaxWidth = maxWidth;
          _lastFontSize = fontSize;
          _lastAlignment = lyricAlignment;
          _lastMaxLinesPerLyric = widget.maxLinesPerLyric;

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

              return MouseRegion(
                onEnter: (_) => setState(() => _hoveredIndex = index),
                onExit: (_) => setState(() => _hoveredIndex = null),
                child: GestureDetector(
                  onTap: () {
                    widget.onTapLine?.call(index);
                  },
                  child: Align(
                    alignment: _getAlignmentFromTextAlign(lyricAlignment),
                    child: Container(
                      width: maxWidth, // 使用固定宽度，减去padding
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _hoveredIndex == index
                            ? Colors.grey.withValues(alpha: 0.2)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.stretch, // 拉伸以填充容器宽度
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
