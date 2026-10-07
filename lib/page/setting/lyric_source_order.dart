import 'package:flutter/material.dart';

import '../../lyrics/lyric_source.dart';

class LyricSourceOrderDialog extends StatefulWidget {
  // 当前顺序（歌词来源 id 列表）
  final List<String> order;

  const LyricSourceOrderDialog({super.key, required this.order});

  @override
  State<LyricSourceOrderDialog> createState() => _LyricSourceOrderDialogState();
}

class _LyricSourceOrderDialogState extends State<LyricSourceOrderDialog> {
  late List<String> _order = LyricSource.normalizeOrder(widget.order);

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      final moved = _order.removeAt(oldIndex);
      _order.insert(newIndex, moved);
    });
  }

  void _resetToDefault() {
    setState(() {
      _order = List<String>.from(LyricSource.defaultOrderIds);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      title: const Text('歌词来源优先级'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '拖动调整顺序，越靠上越优先\n',
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 14),
            ),
            const SizedBox(height: 12),
            // 用 Flexible 包住列表：窗口较矮时列表自身滚动，而不是撑破对话框
            Flexible(
              child: ReorderableListView.builder(
                shrinkWrap: true,
                buildDefaultDragHandles: false,
                itemCount: _order.length,
                onReorderItem: _onReorder,
                itemBuilder: (context, index) {
                  final source = LyricSource.fromId(_order[index]);
                  if (source == null) return const SizedBox.shrink();

                  return Padding(
                    key: ValueKey(source.id),
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Material(
                      color: colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.4,
                      ),
                      borderRadius: BorderRadius.circular(8),
                      clipBehavior: Clip.antiAlias,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 22,
                              child: Text(
                                '${index + 1}',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: colorScheme.primary,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    source.label,
                                    style: theme.textTheme.titleSmall,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    source.description,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            ReorderableDragStartListener(
                              index: index,
                              child: MouseRegion(
                                cursor: SystemMouseCursors.grab,
                                child: Icon(
                                  Icons.drag_indicator,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _resetToDefault, child: const Text('重置')),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_order),
          child: const Text('确定'),
        ),
      ],
    );
  }
}
