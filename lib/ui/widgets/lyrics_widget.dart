import 'package:flutter/material.dart';
import '../page/playlist/playlist_models.dart';

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
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _itemKeys = {};
  int? _hoveredIndex;

  @override
  void didUpdateWidget(covariant LyricsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentIndex != oldWidget.currentIndex) {
      _scrollToCurrentLine();
    }
  }

  void _scrollToCurrentLine() {
    final targetKey = _itemKeys[widget.currentIndex];

    if (targetKey != null && targetKey.currentContext != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Scrollable.ensureVisible(
          targetKey.currentContext!,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          alignment: 0.5, // 目标歌词行居中
        );
      });
    } else {
      // 如果 GlobalKey 不可用，使用估算滚动
      WidgetsBinding.instance.addPostFrameCallback((_) {
        double offset = 0;
        // 累加从列表开始到目标歌词行之前的每一个歌词项的估算高度
        for (int i = 0; i < widget.currentIndex; i++) {
          offset += _estimateLyricItemHeight(i);
        }

        // 调整偏移量，使目标歌词行大致居中
        final double listViewHeight =
            _scrollController.position.viewportDimension;
        offset -= (listViewHeight / 2);
        offset += _estimateLyricItemHeight(widget.currentIndex) / 2;

        // 限制偏移量在滚动范围之内，避免超出内容区域
        offset = offset.clamp(
          _scrollController.position.minScrollExtent,
          _scrollController.position.maxScrollExtent,
        );

        _scrollController.animateTo(
          offset,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return ScrollConfiguration(
      behavior: const ScrollBehavior().copyWith(scrollbars: false),
      child: ListView.builder(
        controller: _scrollController,
        itemCount: widget.lyrics.length,
        itemBuilder: (context, index) {
          final line = widget.lyrics[index];
          final isCurrent = index == widget.currentIndex;
          final visibleTexts = line.texts.take(widget.maxLinesPerLyric);

          final itemKey = _itemKeys.putIfAbsent(index, () => GlobalKey());

          final List<Widget> columnChildren = visibleTexts.map((text) {
            return Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                height: 1.6,
                color: isCurrent
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
              ),
            );
          }).toList();

          return MouseRegion(
            onEnter: (_) => setState(() => _hoveredIndex = index),
            onExit: (_) => setState(() => _hoveredIndex = null),
            child: GestureDetector(
              onTap: () {
                widget.onTapLine?.call(index);
              },
              child: Align(
                alignment: Alignment.center,
                child: IntrinsicWidth(
                  child: Container(
                    key: itemKey,
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
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: columnChildren,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // 测量单行文本在给定样式和最大宽度下的实际高度
  double _measureTextHeight(String text, TextStyle style, double maxWidth) {
    final textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1, // 测量单段文本的高度，无论它有多少行
    );
    textPainter.layout(maxWidth: maxWidth);
    return textPainter.height;
  }

  final Map<int, double> _cachedItemHeights = {};
  double _estimateLyricItemHeight(int index) {
    // 如果已经缓存，直接返回
    if (_cachedItemHeights.containsKey(index)) {
      return _cachedItemHeights[index]!;
    }

    // 边界检查
    if (index < 0 || index >= widget.lyrics.length) {
      return 0.0;
    }
    final LyricLine line = widget.lyrics[index];
    final visibleTexts = line.texts.take(widget.maxLinesPerLyric);
    const TextStyle textStyle = TextStyle(fontSize: 20, height: 1.6);
    final double estimatedMaxWidth =
        MediaQuery.of(context).size.width - (6 * 2);

    double totalTextHeight = 0;
    for (final String text in visibleTexts) {
      // 测量每段文本的高度
      totalTextHeight += _measureTextHeight(text, textStyle, estimatedMaxWidth);
    }

    // 加上歌词项的垂直
    const double verticalPaddingPerItem = 16.0;
    final double estimatedHeight = totalTextHeight + verticalPaddingPerItem;

    // 缓存高度
    _cachedItemHeights[index] = estimatedHeight;
    return estimatedHeight;
  }
}
