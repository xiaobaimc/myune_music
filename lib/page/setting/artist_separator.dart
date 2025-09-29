import 'package:flutter/material.dart';

class ArtistSeparator extends StatefulWidget {
  final List<String> separators;

  const ArtistSeparator({super.key, required this.separators});

  @override
  ArtistSeparatorState createState() => ArtistSeparatorState();
}

class ArtistSeparatorState extends State<ArtistSeparator> {
  late List<String> _separators;
  final _textController = TextEditingController();

  // 默认分隔符
  final List<String> _defaultSeparators = [';', '、', '；', '，', ','];

  @override
  void initState() {
    super.initState();
    // 初始化时过滤掉无效分隔符
    _separators = widget.separators
        .where(
          (separator) =>
              separator.isNotEmpty &&
              separator.trim().isNotEmpty &&
              !_containsInvalidCharacters(separator),
        )
        .toList();
  }

  void _addSeparator() {
    final text = _textController.text;
    // 更严格的验证规则
    if (text.isNotEmpty &&
        text.trim().isNotEmpty &&
        !_separators.contains(text) &&
        !_containsInvalidCharacters(text)) {
      setState(() {
        _separators.add(text);
      });
      _textController.clear();
    }
  }

  // 检查是否包含无效字符
  bool _containsInvalidCharacters(String text) {
    // 检查是否包含控制字符或其他可能导致问题的字符
    for (var i = 0; i < text.length; i++) {
      final charCode = text.codeUnitAt(i);
      // 控制字符通常在0-31和127范围内
      if (charCode < 32 || charCode == 127) {
        return true;
      }
    }
    return false;
  }

  void _removeSeparator(String separator) {
    setState(() {
      _separators.remove(separator);
    });
  }

  void _resetToDefault() {
    setState(() {
      _separators = List<String>.from(_defaultSeparators);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('自定义艺术家分隔符'),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('当前分隔符：', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                ..._separators.map(
                  (separator) => InputChip(
                    label: Text(separator),
                    onDeleted: () => _removeSeparator(separator),
                  ),
                ),
                SizedBox(
                  width: 80,
                  child: TextField(
                    controller: _textController,
                    decoration: const InputDecoration(
                      hintText: '添加',
                      contentPadding: EdgeInsets.symmetric(horizontal: 8),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _addSeparator(),
                  ),
                ),
                IconButton(
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.add, size: 20),
                  onPressed: _addSeparator,
                  tooltip: '添加',
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('用于识别多艺术家的分隔符；\n例如歌曲艺术家为 "歌手1,歌手2" 时，添加 "," 来区分他们'),
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
          onPressed: () => Navigator.of(context).pop(_separators),
          child: const Text('确定'),
        ),
      ],
    );
  }
}
