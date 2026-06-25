import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../settings_provider.dart';
import 'info_icon.dart';

class PlaybackPageTab extends StatelessWidget {
  const PlaybackPageTab({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return ListView(
      key: const ValueKey('playback'),
      children: [
        // 启用模糊背景
        SwitchListTile(
          title: Text(
            '播放页模糊背景',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          value: settings.useBlurBackground,
          onChanged: (value) {
            context.read<SettingsProvider>().setUseBlurBackground(value);
          },
        ),
        // 启用动态背景
        SwitchListTile(
          title: const Row(
            children: [
              Text('播放页动态背景'),
              SizedBox(width: 4),
              InfoIcon('实验性功能。启用后会略微提升性能占用\n未启用模糊背景时不生效'),
            ],
          ),
          value: settings.enableDynamicBackground,
          onChanged: (value) {
            context.read<SettingsProvider>().setEnableDynamicBackground(value);
          },
        ),
        // 启用歌词模糊效果
        SwitchListTile(
          title: Text('歌词模糊效果', style: Theme.of(context).textTheme.titleMedium),
          value: settings.enableLyricBlur,
          onChanged: (value) {
            context.read<SettingsProvider>().setEnableLyricBlur(value);
          },
        ),
        // 歌词上下补位设置
        SwitchListTile(
          title: const Text('高亮歌词始终垂直居中显示'),
          value: settings.addLyricPadding,
          onChanged: (value) {
            context.read<SettingsProvider>().setAddLyricPadding(value);
          },
        ),
        // 启用歌词弹性滚动
        SwitchListTile(
          title: const Row(
            children: [
              Text('歌词弹性滚动'),
              SizedBox(width: 4),
              InfoIcon('实验性功能。启用后会显著提升性能占用'),
            ],
          ),
          value: settings.enableLyricElasticScroll,
          onChanged: (value) {
            context.read<SettingsProvider>().setEnableLyricElasticScroll(value);
          },
        ),
      ],
    );
  }
}
