import 'package:flutter/material.dart';
import '../page/playlist/sort_options.dart';

class SortDialog extends StatefulWidget {
  const SortDialog({super.key});

  @override
  State<SortDialog> createState() => _SortDialogState();
}

class _SortDialogState extends State<SortDialog> {
  SortCriterion _selectedCriterion = SortCriterion.title;
  bool _isDescending = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('排序歌曲'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 排序标准单选按钮
          RadioListTile<SortCriterion>(
            title: const Text('按歌曲名'),
            value: SortCriterion.title,
            groupValue: _selectedCriterion,
            onChanged: (value) => setState(() => _selectedCriterion = value!),
          ),
          RadioListTile<SortCriterion>(
            title: const Text('按歌手名'),
            value: SortCriterion.artist,
            groupValue: _selectedCriterion,
            onChanged: (value) => setState(() => _selectedCriterion = value!),
          ),
          RadioListTile<SortCriterion>(
            title: const Text('按修改日期'),
            value: SortCriterion.dateModified,
            groupValue: _selectedCriterion,
            onChanged: (value) => setState(() => _selectedCriterion = value!),
          ),
          RadioListTile<SortCriterion>(
            title: const Text('随机排序'),
            value: SortCriterion.random,
            groupValue: _selectedCriterion,
            onChanged: (value) => setState(() => _selectedCriterion = value!),
          ),
          const Divider(),
          // 倒序复选框
          CheckboxListTile(
            title: const Text('倒序排列'),
            value: _isDescending,
            onChanged: _selectedCriterion == SortCriterion.random
                ? null // 当选择随机排序时禁用倒序选项
                : (value) => setState(() => _isDescending = value!),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () {
            // 当用户点击“应用”时，关闭对话框并返回选择结果
            Navigator.of(context).pop({
              'criterion': _selectedCriterion,
              'descending': _isDescending,
            });
          },
          child: const Text('应用排序'),
        ),
      ],
    );
  }
}
