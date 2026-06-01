import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
                onPressed: () =>
                    _showModernColorPickerDialog(context, themeProvider),
                icon: const Icon(Icons.palette_outlined, size: 20),
                label: const Text('选择颜色'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showModernColorPickerDialog(
    BuildContext context,
    ThemeProvider themeProvider,
  ) {
    final initialHSV = HSVColor.fromColor(themeProvider.lastManualSeedColor);

    final ValueNotifier<double> hueNotifier = ValueNotifier(initialHSV.hue);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('自定义主题颜色'),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ValueListenableBuilder<double>(
                  valueListenable: hueNotifier,
                  builder: (context, currentHue, child) {
                    final previewColor = HSVColor.fromAHSV(
                      1.0,
                      currentHue,
                      0.7,
                      0.9,
                    ).toColor();
                    final previewScheme = ColorScheme.fromSeed(
                      seedColor: previewColor,
                      brightness: Theme.of(context).brightness,
                    );

                    return Card(
                      elevation: 2,
                      color: previewScheme.surfaceContainerLow,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 4,
                                      height: 16,
                                      decoration: BoxDecoration(
                                        color: previewScheme.primary,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '效果预览',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w500,
                                        color: previewScheme.onSurface,
                                      ),
                                    ),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: previewScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${currentHue.toInt()}°',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: previewScheme.onPrimaryContainer,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              '这代表了当前颜色下文本与按钮的搭配效果',
                              style: TextStyle(
                                fontSize: 13,
                                color: previewScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: () {},
                                  style: TextButton.styleFrom(
                                    foregroundColor: previewScheme.primary,
                                  ),
                                  child: const Text('次要按钮'),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  onPressed: () {},
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: previewScheme.primary,
                                    foregroundColor: previewScheme.onPrimary,
                                    elevation: 0,
                                  ),
                                  child: const Text('主要动作'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),

                ValueListenableBuilder<double>(
                  valueListenable: hueNotifier,
                  builder: (context, currentHue, child) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(left: 8.0, bottom: 8.0),
                          child: Text(
                            '调整色相',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              height: 12,
                              margin: const EdgeInsets.symmetric(
                                horizontal: 20,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(6),
                                gradient: LinearGradient(
                                  colors: List.generate(7, (index) {
                                    final double hue = index * 60.0;

                                    final bool isDark =
                                        Theme.of(context).brightness ==
                                        Brightness.dark;

                                    return HSVColor.fromAHSV(
                                      1.0,
                                      hue,
                                      isDark ? 0.6 : 0.45,
                                      isDark ? 0.75 : 0.85,
                                    ).toColor();
                                  }),
                                ),
                              ),
                            ),
                            Theme(
                              data: Theme.of(context).copyWith(
                                sliderTheme: SliderThemeData(
                                  trackHeight: 12,
                                  activeTrackColor: Colors.transparent,
                                  inactiveTrackColor: Colors.transparent,
                                  thumbColor: HSVColor.fromAHSV(
                                    1.0,
                                    currentHue,
                                    0.8,
                                    0.9,
                                  ).toColor(),
                                  overlayColor: HSVColor.fromAHSV(
                                    0.2,
                                    currentHue,
                                    0.8,
                                    0.9,
                                  ).toColor(),
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 10,
                                    elevation: 3,
                                  ),
                                ),
                              ),
                              child: Slider(
                                value: currentHue,
                                min: 0.0,
                                max: 360.0,
                                onChanged: (newValue) {
                                  hueNotifier.value = newValue;
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ],
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

                // 还原为完整的 Color 对象
                final finalColor = HSVColor.fromAHSV(
                  1.0,
                  hueNotifier.value,
                  0.7,
                  0.85,
                ).toColor();
                themeProvider.setSeedColor(finalColor, isManual: true);

                Navigator.of(context).pop();
              },
              child: const Text('应用主题'),
            ),
          ],
        );
      },
    );
  }
}
