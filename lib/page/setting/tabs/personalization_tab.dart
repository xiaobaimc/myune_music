import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:silky_scroll/silky_scroll.dart';

import '../../../theme/scroll_config.dart';
import '../settings_provider.dart';
import '../../../widgets/font_selector_row.dart';
import '../page_visibility_settings.dart';
import 'custom_background_settings.dart';
import 'info_icon.dart';

class PersonalizationTab extends StatefulWidget {
  const PersonalizationTab({super.key});

  @override
  State<PersonalizationTab> createState() => _PersonalizationTabState();
}

class _PersonalizationTabState extends State<PersonalizationTab> {
  late final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return SilkyListView(
      key: const ValueKey('personalization'),
      controller: _scrollController,
      silkyScrollDuration: ScrollConfig.duration,
      scrollSpeed: ScrollConfig.speed,
      animationCurve: ScrollConfig.curve,
      children: [
        // 系统字体选择器
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: FontSelectorRow(),
        ),

        // 页面可见性设置
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
              InfoIcon('启用后会优先读取同名.lrc作为歌词，其次内嵌歌词，否则相反\n该选项适用于同时拥有内嵌以及外置歌词的情况'),
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
        const Divider(height: 24),
        // 自定义背景图
        const CustomBackgroundSettings(),
      ],
    );
  }
}
