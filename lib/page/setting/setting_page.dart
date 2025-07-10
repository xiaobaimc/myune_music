import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import './theme_selection_screen.dart';
import '../../theme/theme_provider.dart';
import './settings_provider.dart';
import '../../widgets/font_selector_row.dart';

class SettingPage extends StatefulWidget {
  const SettingPage({super.key});

  @override
  State<SettingPage> createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  bool _fontSelectorEnabled = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Divider(height: 1, thickness: 1),
        const ThemeSelectionScreen(),
        SwitchListTile(
          title: Text('深色模式', style: Theme.of(context).textTheme.titleMedium),
          value: context.watch<ThemeProvider>().isDarkMode,
          onChanged: (value) => context.read<ThemeProvider>().toggleDarkMode(),
        ),
        SwitchListTile(
          title: Text(
            '启用系统字体选择器 (可能会卡顿)',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          value: _fontSelectorEnabled,
          onChanged: (value) {
            setState(() {
              _fontSelectorEnabled = value;
            });
            if (value) {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('提示'),
                  content: const Text('选择完字体，建议关闭该选项。因为字体已经生效了。保持开启可能会导致页面卡顿'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('好的'),
                    ),
                  ],
                ),
              );
            }
          },
        ),
        if (_fontSelectorEnabled)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: FontSelectorRow(),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '详情页同时间戳最大显示歌词行数',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              SegmentedButton<int>(
                segments: List.generate(5, (index) {
                  final value = index + 1;
                  return ButtonSegment(value: value, label: Text('$value'));
                }),
                selected: {context.watch<SettingsProvider>().maxLinesPerLyric},
                onSelectionChanged: (newSelection) {
                  final value = newSelection.first;
                  context.read<SettingsProvider>().setMaxLinesPerLyric(value);
                },
                showSelectedIcon: false,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('详情页歌词字体大小', style: Theme.of(context).textTheme.titleMedium),
              Expanded(
                child: Slider(
                  value: context.watch<SettingsProvider>().fontSize,
                  min: 12.0,
                  max: 32.0,
                  divisions: 20,
                  label: context
                      .watch<SettingsProvider>()
                      .fontSize
                      .toStringAsFixed(1),
                  onChanged: (value) {
                    context.read<SettingsProvider>().setFontSize(value);
                  },
                ),
              ),
            ],
          ),
        ),
        // 对齐方式选择
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('详情页歌词对齐方式', style: Theme.of(context).textTheme.titleMedium),
              SegmentedButton<TextAlign>(
                segments: const [
                  ButtonSegment(value: TextAlign.left, label: Text('居左')),
                  ButtonSegment(value: TextAlign.center, label: Text('居中')),
                  ButtonSegment(value: TextAlign.right, label: Text('居右')),
                ],
                selected: {context.watch<SettingsProvider>().lyricAlignment},
                onSelectionChanged: (Set<TextAlign> newSelection) {
                  if (newSelection.isNotEmpty) {
                    context.read<SettingsProvider>().setLyricAlignment(
                      newSelection.first,
                    );
                  }
                },
                showSelectedIcon: false,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
