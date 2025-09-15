import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:media_kit/media_kit.dart';
import '../playlist/playlist_content_notifier.dart';

class AudioDeviceSelector extends StatelessWidget {
  const AudioDeviceSelector({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<PlaylistContentNotifier>(
      builder: (context, playlistNotifier, child) {
        final devices = playlistNotifier.availableAudioDevices;
        final selectedDevice = playlistNotifier.selectedAudioDevice;

        return AlertDialog(
          title: const Text('选择音频设备'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                if (devices.isEmpty)
                  const Text('未检测到音频设备')
                else ...[
                  // 自动选择选项
                  ListTile(
                    title: const Text('自动选择'),
                    leading: Radio<AudioDevice?>(
                      value: AudioDevice.auto(),
                      groupValue: selectedDevice,
                      onChanged: (device) {
                        playlistNotifier.useAutoAudioDevice();
                      },
                    ),
                    onTap: () {
                      playlistNotifier.useAutoAudioDevice();
                    },
                  ),
                  const Divider(),
                  // 可用设备列表
                  ...devices.map((device) {
                    // 主标题显示设备描述（如果有的话），副标题显示设备名称
                    Widget? titleWidget;
                    Widget? subtitleWidget;

                    if (device.description.isNotEmpty) {
                      // 如果有描述，则描述作为主标题
                      titleWidget = Text(device.description);
                      subtitleWidget = Text(
                        device.name,
                        style: Theme.of(context).textTheme.bodySmall,
                      );
                    } else {
                      // 如果没有描述，则设备名称作为主标题
                      titleWidget = Text(device.name);
                    }

                    return ListTile(
                      title: titleWidget,
                      subtitle: subtitleWidget,
                      leading: Radio<AudioDevice?>(
                        value: device,
                        groupValue: selectedDevice,
                        onChanged: (selected) {
                          if (selected != null) {
                            playlistNotifier.selectAudioDevice(selected);
                          }
                        },
                      ),
                      onTap: () {
                        playlistNotifier.selectAudioDevice(device);
                      },
                    );
                  }),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }
}
