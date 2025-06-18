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

  double _getActualTextLineHeight(double fontSize, double heightMultiplier) {
    return fontSize * heightMultiplier;
  }

  void _scrollToCurrentLine() {
    final targetKey = _itemKeys[widget.currentIndex];

    if (targetKey != null && targetKey.currentContext != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Scrollable.ensureVisible(
          targetKey.currentContext!,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          alignment: 0.5,
        );
      });
    } else {
      const double currentTextStyleHeightMultiplier = 1.6;
      const double fontSize = 20.0;
      const double verticalPaddingPerItem = 16.0;

      // 计算当前每个歌词项的实际估算高度
      final actualSingleLineHeight = _getActualTextLineHeight(
        fontSize,
        currentTextStyleHeightMultiplier,
      );
      final itemHeight =
          widget.maxLinesPerLyric * actualSingleLineHeight +
          verticalPaddingPerItem;

      // 计算滚动偏移量
      final offset =
          (widget.currentIndex - 3).clamp(0, widget.lyrics.length) * itemHeight;

      _scrollController.animateTo(
        offset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
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
}
