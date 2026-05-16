import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

import '../../theme/theme_provider.dart';
import 'settings_provider.dart';

class ThemeSelectionScreen extends StatelessWidget {
  const ThemeSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    '更改主题配色',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
              ElevatedButton.icon(
                onPressed: () => _showColorPickerDialog(context, themeProvider),
                icon: const Icon(Icons.palette_outlined, size: 20),
                label: const Text('选择颜色'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showColorPickerDialog(
    BuildContext context,
    ThemeProvider themeProvider,
  ) {
    // 使用最后一次手动选择的颜色作为初始值，避免动态颜色覆盖手动颜色
    Color pickerColor = themeProvider.lastManualSeedColor;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('选择主题颜色'),
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: pickerColor,
              onColorChanged: (color) {
                pickerColor = color;
              },
              enableAlpha: false, // 禁用 Alpha 通道
              labelTypes: const [],
              paletteType: PaletteType.hsv,
              hexInputBar: true,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () {
                // 如果当前启用了动态颜色，先关闭它
                final settings = context.read<SettingsProvider>();
                if (settings.useDynamicColor) {
                  settings.setUseDynamicColor(false);
                }
                // 设置用户手动选择的颜色
                themeProvider.setSeedColor(pickerColor, isManual: true);
                Navigator.of(context).pop();
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }
}
