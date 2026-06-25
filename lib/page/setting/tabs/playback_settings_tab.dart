import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../settings_provider.dart';
import '../../playlist/playlist_content_notifier.dart';
import '../audio_device_selector.dart';
import 'info_icon.dart';

class PlaybackSettingsTab extends StatelessWidget {
  const PlaybackSettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return ListView(
      key: const ValueKey('playback_settings'),
      children: [
        // 音频设备选择
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 6,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '更改音频输出设备',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              ElevatedButton.icon(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (BuildContext context) {
                      return const DeviceSelector();
                    },
                  );
                },
                icon: const Icon(Icons.headphones, size: 20),
                label: const Text('选择设备'),
              ),
            ],
          ),
        ),
        // 独占模式设置
        Consumer<PlaylistContentNotifier>(
          builder: (context, playlistNotifier, child) {
            return SwitchListTile(
              title: const Row(
                children: [
                  Text('启用独占模式'),
                  SizedBox(width: 4),
                  InfoIcon(
                    '启用后将使用独占模式播放音频，提供更低的延迟以及更好的音质\n这会导致其他应用无法播放音频',
                  ),
                ],
              ),
              value: playlistNotifier.isExclusiveModeEnabled,
              onChanged: playlistNotifier.toggleExclusiveMode,
            );
          },
        ),
        // 平衡歌曲音量设置
        SwitchListTile(
          title: const Row(
            children: [
              Text('平衡歌曲音量'),
              SizedBox(width: 4),
              InfoIcon('启用后将平衡为-16 LUFS\n这可能会损失部分音质'),
            ],
          ),
          value: settings.enableLoudness,
          onChanged: (value) {
            final playlistNotifier = context.read<PlaylistContentNotifier>();
            if (value && settings.enableReplayGain) {
              playlistNotifier.postInfo('与 "重放增益" 冲突');
              return;
            }
            context.read<SettingsProvider>().setEnableLoudness(value);
            playlistNotifier.updateLoudnessSettings();
          },
        ),
        // 重放增益设置
        SwitchListTile(
          title: const Row(
            children: [
              Text('重放增益'),
              SizedBox(width: 4),
              InfoIcon('需要歌曲包含 ReplayGain 标签\n可在 歌单-多选 中批量扫描写入'),
            ],
          ),
          value: settings.enableReplayGain,
          onChanged: (value) {
            final playlistNotifier = context.read<PlaylistContentNotifier>();
            if (value && settings.enableLoudness) {
              playlistNotifier.postInfo('与 "平衡歌曲音量" 冲突');
              return;
            }
            context.read<SettingsProvider>().setEnableReplayGain(value);
            playlistNotifier.updateReplayGainSettings();
          },
        ),
      ],
    );
  }
}
