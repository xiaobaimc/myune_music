import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../page/playlist/playlist_models.dart';
import '../page/setting/settings_provider.dart';

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
    final settingsProvider = Provider.of<SettingsProvider>(
      context,
      listen: false,
    );
    final oldSettingsProvider = Provider.of<SettingsProvider>(
      context,
      listen: false,
    );
    if (widget.currentIndex != oldWidget.currentIndex ||
        settingsProvider.lyricAlignment != oldSettingsProvider.lyricAlignment ||
        settingsProvider.fontSize != oldSettingsProvider.fontSize) {
      _cachedItemHeights.clear(); // 清除高度缓存
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
              textAlign: Provider.of<SettingsProvider>(context).lyricAlignment,
              style: TextStyle(
                fontSize: Provider.of<SettingsProvider>(
                  context,
                ).fontSize, // 动态字体大小
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
                alignment: _getAlignmentFromTextAlign(
                  Provider.of<SettingsProvider>(context).lyricAlignment,
                ),
                child: Container(
                  key: itemKey,
                  width:
                      MediaQuery.of(context).size.width -
                      12, // 使用固定宽度，减去padding
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
                    crossAxisAlignment: CrossAxisAlignment.stretch, // 拉伸以填充容器宽度
                    children: columnChildren,
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
  double _measureTextHeight(String text, double fontSize, double maxWidth) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: fontSize, height: 1.6), // 使用动态字体大小
      ),
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
    // 从 SettingsProvider 获取动态字体大小
    final double fontSize = Provider.of<SettingsProvider>(
      context,
      listen: false,
    ).fontSize;
    final double estimatedMaxWidth =
        MediaQuery.of(context).size.width - (6 * 2);

    double totalTextHeight = 0;
    for (final String text in visibleTexts) {
      // 测量每段文本的高度
      totalTextHeight += _measureTextHeight(text, fontSize, estimatedMaxWidth);
    }

    // 加上歌词项的垂直内边距
    const double verticalPaddingPerItem = 16.0;
    final double estimatedHeight = totalTextHeight + verticalPaddingPerItem;

    // 缓存高度
    _cachedItemHeights[index] = estimatedHeight;
    return estimatedHeight;
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
