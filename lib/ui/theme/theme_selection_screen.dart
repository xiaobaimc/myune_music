import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme_provider.dart';

class ThemeSelectionScreen extends StatelessWidget {
  const ThemeSelectionScreen({super.key});

  final List<Color> presetColors = const [
    Colors.blue,
    Colors.green,
    Colors.purple,
    Colors.orange,
    Colors.red,
    Colors.teal,
    Colors.pink,
    Colors.indigo,
    Colors.brown,
  ];

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final Color currentSeedColor = themeProvider.currentSeedColor;
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SizedBox(
            width: constraints.maxWidth,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text('选择主题配色：', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth * 0.6, // 最多占60%
                  ),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: presetColors.map((color) {
                          return Padding(
                            padding: const EdgeInsets.only(left: 8.0),
                            child: _buildColorOption(
                              context,
                              color,
                              currentSeedColor,
                              () => themeProvider.setSeedColor(color),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // 辅助方法，用于构建单个颜色选择按钮
  Widget _buildColorOption(
    BuildContext context,
    Color color,
    Color selectedColor,
    VoidCallback onTap,
  ) {
    final bool isSelected = color == selectedColor;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: isSelected
              ? Border.all(
                  color: Theme.of(context).colorScheme.onSurface,
                  width: 1.0,
                )
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              spreadRadius: 1,
              blurRadius: 3,
              offset: const Offset(0, 2),
            ),
          ],
        ),
      ),
    );
  }
}
