import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../settings_provider.dart';
import '../../../widgets/font_selector_row.dart';
import '../page_visibility_settings.dart';
import 'info_icon.dart';

class PersonalizationTab extends StatelessWidget {
  const PersonalizationTab({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return ListView(
      key: const ValueKey('personalization'),
      children: [
        // 系统字体选择器
        const Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          child: FontSelectorRow(),
        ),

        // 页面可见性设置
        const Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          child: PageVisibilitySettings(),
        ),

        if (Platform.isWindows)
          SwitchListTile(
            title: const Text('在任务栏显示播放进度'),
            value: settings.showTaskbarProgress,
            onChanged: (value) {
              context.read<SettingsProvider>().setShowTaskbarProgress(value);
            },
          ),
        // 始终保持单行歌词显示
        SwitchListTile(
          title: Text(
            '始终单行显示顶部歌词',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          value: settings.forceSingleLineLyric,
          onChanged: (value) {
            context.read<SettingsProvider>().setForceSingleLineLyric(value);
          },
        ),
        // 优先读取外置LRC歌词
        SwitchListTile(
          title: const Row(
            children: [
              Text('优先读取外置LRC歌词'),
              SizedBox(width: 4),
              InfoIcon(
                '启用后会优先读取同名.lrc作为歌词，其次内嵌歌词，否则相反\n该选项适用于同时拥有内嵌以及外置歌词的情况',
              ),
            ],
          ),
          value: settings.preferExternalLyrics,
          onChanged: (value) {
            context.read<SettingsProvider>().setPreferExternalLyrics(value);
          },
        ),
        // 始终显示专辑名称
        SwitchListTile(
          title: const Text('始终显示专辑名称'),
          value: settings.showAlbumName,
          onChanged: (value) {
            context.read<SettingsProvider>().setShowAlbumName(value);
          },
        ),
      ],
    );
  }
}
