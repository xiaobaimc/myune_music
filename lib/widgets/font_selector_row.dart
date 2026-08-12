import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/theme_provider.dart';
import 'font_selector_dialog.dart';

/// 字体选择器组件，提供字体选择按钮和对话框入口
/// 
/// 点击按钮会弹出字体选择对话框，用户选择后通过ThemeProvider保存选择。
class FontSelectorRow extends StatelessWidget {
  const FontSelectorRow({super.key});

  /// 显示字体选择对话框
  /// 
  /// 从ThemeProvider获取当前字体，然后弹出FontSelectorDialog对话框。
  /// 用户确认选择后，调用setFontFamily保存新字体。
  Future<void> _showFontSelectionDialog(BuildContext context) async {
    final themeProvider = context.read<ThemeProvider>();
    final currentFontFamily = themeProvider.currentFontFamily;

    final selectedFont = await showDialog<String>(
      context: context,
      builder: (context) => FontSelectorDialog(
        currentFontFamily: currentFontFamily,
      ),
    );

    if (selectedFont != null && context.mounted) {
      themeProvider.setFontFamily(selectedFont);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // 显示标签
        Text('自定义字体', style: Theme.of(context).textTheme.titleMedium),
        // 字体选择按钮，点击弹出对话框
        ElevatedButton.icon(
          onPressed: () => _showFontSelectionDialog(context),
          icon: const Icon(Icons.text_fields_rounded, size: 20),
          label: const Text('选择字体'),
        ),
      ],
    );
  }
}
