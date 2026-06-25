import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../settings_provider.dart';
import '../../playlist/playlist_content_notifier.dart';
import '../playlist_cleaner.dart';
import '../folder_playlist_refresher.dart';
import '../artist_separator.dart';
import 'info_icon.dart';

class AdvancedTab extends StatelessWidget {
  const AdvancedTab({super.key});

  // 显示艺术家分隔符设置对话框
  void _showArtistSeparator(BuildContext context, SettingsProvider settings) {
    final separators = List<String>.from(settings.artistSeparators);

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return ArtistSeparator(separators: separators);
      },
    ).then((newSeparators) {
      if (newSeparators != null) {
        settings.setArtistSeparators(newSeparators);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return ListView(
      key: const ValueKey('advanced'),
      children: [
        // 清理无效歌曲
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 6,
          ),
          child: Consumer<PlaylistContentNotifier>(
            builder: (context, notifier, child) {
              return PlaylistCleaner(notifier: notifier);
            },
          ),
        ),
        // 刷新文件夹歌单
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 6,
          ),
          child: Consumer<PlaylistContentNotifier>(
            builder: (context, notifier, child) {
              return FolderPlaylistRefresher(notifier: notifier);
            },
          ),
        ),
        // 自定义艺术家分隔符
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 6,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '更改艺术家分隔符',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              ElevatedButton.icon(
                onPressed: () => _showArtistSeparator(context, settings),
                icon: const Icon(Icons.person, size: 20),
                label: const Text('修改分隔符'),
              ),
            ],
          ),
        ),
        // 允许添加任何格式的文件
        SwitchListTile(
          title: const Row(
            children: [
              Text('允许添加任何格式的文件'),
              SizedBox(width: 4),
              InfoIcon(
                '启用后可以选择任何格式的文件添加到歌单中\n底层使用 MPV，依赖 FFmpeg 解码，理论上支持播放所有音频格式\n除非确认兼容性，否则请谨慎启用该选项',
              ),
            ],
          ),
          value: settings.allowAnyFormat,
          onChanged: (value) {
            context.read<SettingsProvider>().setAllowAnyFormat(value);
          },
        ),
        // 允许最小化到托盘
        SwitchListTile(
          title: const Row(
            children: [
              Text('允许最小化到托盘'),
              SizedBox(width: 4),
              InfoIcon('启用后点击最小化按钮将最小化到系统托盘'),
            ],
          ),
          value: settings.minimizeToTray,
          onChanged: (value) {
            context.read<SettingsProvider>().setMinimizeToTray(value);
          },
        ),
        // 忽略某些播放错误
        SwitchListTile(
          title: const Row(
            children: [
              Text('忽略某些播放错误'),
              SizedBox(width: 4),
              InfoIcon(
                '某些音频文件可能内部出现了损坏或者格式错误\n但可能不影响播放，可以通过启用该选项来忽略这些错误\n启用后仍然会记录到日志中\n通常情况下，请不要开启该选项',
              ),
            ],
          ),
          value: settings.ignorePlaybackErrors,
          onChanged: (value) {
            context.read<SettingsProvider>().setIgnorePlaybackErrors(value);
          },
        ),
      ],
    );
  }
}
