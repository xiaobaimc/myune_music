import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../page/setting/settings_provider.dart';

class LyricsSettingsDrawer extends StatelessWidget {
  const LyricsSettingsDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return Drawer(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('歌词显示设置', style: Theme.of(context).textTheme.titleLarge),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    tooltip: '关闭',
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 10),

              // 同时间戳歌词行数设置
              Text('同时间戳歌词行数', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              SegmentedButton<int>(
                segments: List.generate(5, (index) {
                  final value = index + 1;
                  return ButtonSegment(value: value, label: Text('$value'));
                }),
                selected: {settings.maxLinesPerLyric},
                onSelectionChanged: (newSelection) {
                  final value = newSelection.first;
                  context.read<SettingsProvider>().setMaxLinesPerLyric(value);
                },
                showSelectedIcon: false,
              ),
              const Divider(),

              // 歌词字体大小设置
              Text('歌词字体大小', style: Theme.of(context).textTheme.titleMedium),
              Slider(
                value: settings.fontSize,
                min: 12.0,
                max: 32.0,
                divisions: 20,
                label: settings.fontSize.toStringAsFixed(1),
                onChanged: (value) {
                  context.read<SettingsProvider>().setFontSize(value);
                },
              ),
              Text(
                '当前大小: ${settings.fontSize.toStringAsFixed(1)}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const Divider(),

              // 歌词对齐方式设置
              Text('歌词对齐方式', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              SegmentedButton<TextAlign>(
                segments: const [
                  ButtonSegment(value: TextAlign.left, label: Text('居左')),
                  ButtonSegment(value: TextAlign.center, label: Text('居中')),
                  ButtonSegment(value: TextAlign.right, label: Text('居右')),
                ],
                selected: {settings.lyricAlignment},
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
      ),
    );
  }
}
