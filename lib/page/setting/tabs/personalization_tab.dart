import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:silky_scroll/silky_scroll.dart';

import '../../../theme/scroll_config.dart';
import '../settings_provider.dart';
import '../../../widgets/font_selector_row.dart';
import '../lyric_source_order.dart';
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

  // 显示歌词来源优先级排序对话框
  void _showLyricSourceOrder(BuildContext context, SettingsProvider settings) {
    showDialog<List<String>>(
      context: context,
      builder: (BuildContext context) {
        return LyricSourceOrderDialog(order: settings.lyricSourceOrder);
      },
    ).then((newOrder) {
      if (newOrder != null) {
        settings.setLyricSourceOrder(newOrder);
      }
    });
  }

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

        // 歌词来源优先级
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Text(
                          '歌词来源优先级',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(width: 4),
                        const InfoIcon('当一首歌同时存在多种歌词时，按选择的顺序依次尝试获取，获取到就停止'),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => _showLyricSourceOrder(context, settings),
                    icon: const Icon(Icons.swap_vert_circle_outlined, size: 20),
                    label: const Text('调整顺序'),
                  ),
                ],
              ),
            ],
          ),
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
