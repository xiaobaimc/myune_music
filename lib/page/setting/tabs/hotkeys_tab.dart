import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_scroll/flutter_web_scroll.dart';

import '../settings_provider.dart';
import '../../playlist/playlist_content_notifier.dart';
import '../../../services/global_hotkey_manager.dart';

class HotkeysTab extends StatefulWidget {
  const HotkeysTab({super.key});

  @override
  State<HotkeysTab> createState() => _HotkeysTabState();
}

class _HotkeysTabState extends State<HotkeysTab> {
  late final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return SmoothScrollWeb(
      controller: _scrollController,
      config: SmoothScrollConfig.lenis(),
      child: ListView(
        controller: _scrollController,
        key: const ValueKey('hotkeys'),
        children: [
          // Master switch
          SwitchListTile(
            title: const Row(children: [Text('启用全局快捷键')]),
            value: settings.enableGlobalHotkeys,
            onChanged: (value) async {
              final notifier = context.read<PlaylistContentNotifier>();
              await settings.setEnableGlobalHotkeys(value);
              if (value) {
                await GlobalHotkeyManager().registerAll(notifier, settings);
              } else {
                await GlobalHotkeyManager().unregisterAll();
              }
            },
          ),
          const Divider(),
          // Reset to defaults
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '全局快捷键',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '全局快捷键与系统其他程序可能有冲突',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    final notifier = context.read<PlaylistContentNotifier>();
                    // First unregister all
                    await GlobalHotkeyManager().unregisterAll();
                    // Reset settings
                    await settings.resetToDefaultHotKeys();
                    // Register all defaults
                    if (settings.enableGlobalHotkeys) {
                      await GlobalHotkeyManager().registerAll(
                        notifier,
                        settings,
                      );
                    }
                    notifier.postInfo('已恢复默认快捷键');
                  },
                  icon: const Icon(Icons.restore, size: 18),
                  label: const Text('恢复默认'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // List of hotkeys
          _buildHotkeyRow(
            context,
            '播放 / 暂停',
            'play_pause',
            settings.playPauseHotKey,
            settings,
          ),
          _buildHotkeyRow(
            context,
            '下一首',
            'next_track',
            settings.nextTrackHotKey,
            settings,
          ),
          _buildHotkeyRow(
            context,
            '上一首',
            'prev_track',
            settings.prevTrackHotKey,
            settings,
          ),
          _buildHotkeyRow(
            context,
            '音量加',
            'volume_up',
            settings.volumeUpHotKey,
            settings,
          ),
          _buildHotkeyRow(
            context,
            '音量减',
            'volume_down',
            settings.volumeDownHotKey,
            settings,
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('局内快捷键', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  '仅在软件位于前台时生效',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
          _buildReadonlyHotkeyRow(context, '播放 / 暂停', 'Space'),
          _buildReadonlyHotkeyRow(context, '下一首', 'Ctrl + →'),
          _buildReadonlyHotkeyRow(context, '上一首', 'Ctrl + ←'),
          _buildReadonlyHotkeyRow(context, '音量加', '↑ '),
          _buildReadonlyHotkeyRow(context, '音量减', '↓'),
          _buildReadonlyHotkeyRow(context, '快进 5 秒', '→ '),
          _buildReadonlyHotkeyRow(context, '快退 5 秒', '←'),
        ],
      ),
    );
  }

  Widget _buildHotkeyRow(
    BuildContext context,
    String title,
    String type,
    HotKey? hotKey,
    SettingsProvider settings,
  ) {
    final notifier = context.read<PlaylistContentNotifier>();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          Row(
            children: [
              // Keycap UI representation
              Container(
                constraints: const BoxConstraints(minWidth: 100),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: Text(
                  _formatHotKey(hotKey),
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Record button
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: '录制快捷键',
                onPressed: () =>
                    _showRecordDialog(context, type, hotKey, title),
              ),
              // Clear button
              IconButton(
                icon: const Icon(Icons.clear_outlined),
                tooltip: '清除快捷键',
                onPressed: hotKey == null
                    ? null
                    : () async {
                        await GlobalHotkeyManager().updateHotKey(
                          type,
                          hotKey,
                          null,
                          notifier,
                          settings,
                        );
                        await settings.setHotKey(type, null);
                      },
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatHotKey(HotKey? hotKey) {
    if (hotKey == null) return '无';
    final List<String> parts = [];
    if (hotKey.modifiers != null) {
      for (final modifier in hotKey.modifiers!) {
        switch (modifier) {
          case HotKeyModifier.control:
            parts.add('Ctrl');
            break;
          case HotKeyModifier.alt:
            parts.add('Alt');
            break;
          case HotKeyModifier.shift:
            parts.add('Shift');
            break;
          case HotKeyModifier.meta:
            parts.add('Meta');
            break;
          default:
            break;
        }
      }
    }

    final key = hotKey.key;
    String keyLabel = '';
    if (key is PhysicalKeyboardKey) {
      keyLabel = _getPhysicalKeyLabel(key);
    } else if (key is LogicalKeyboardKey) {
      keyLabel = key.keyLabel;
    } else {
      keyLabel = key.toString();
    }

    if (keyLabel.startsWith('Key ')) {
      keyLabel = keyLabel.substring(4);
    }

    switch (keyLabel.toLowerCase()) {
      case 'space':
        keyLabel = 'Space';
        break;
      case 'arrow right':
      case 'arrowright':
        keyLabel = '→';
        break;
      case 'arrow left':
      case 'arrowleft':
        keyLabel = '←';
        break;
      case 'arrow up':
      case 'arrowup':
        keyLabel = '↑';
        break;
      case 'arrow down':
      case 'arrowdown':
        keyLabel = '↓';
        break;
      default:
        if (keyLabel.isNotEmpty) {
          keyLabel = keyLabel[0].toUpperCase() + keyLabel.substring(1);
        }
    }
    parts.add(keyLabel);
    return parts.join(' + ');
  }

  String _getPhysicalKeyLabel(PhysicalKeyboardKey key) {
    final String label = key.keyLabel;

    const specialLabels = {
      'arrow up': '↑',
      'arrow down': '↓',
      'arrow left': '←',
      'arrow right': '→',
      'space': 'Space',
    };

    return specialLabels[label.toLowerCase()] ?? label;
  }

  void _showRecordDialog(
    BuildContext context,
    String type,
    HotKey? oldHotKey,
    String title,
  ) {
    // 录制期间临时注销所有全局快捷键，以避免热键拦截和冲突/崩溃
    GlobalHotkeyManager().unregisterAll();

    HotKey? recordedHotKey = oldHotKey;

    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('录制快捷键 - $title'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('可按住 Ctrl/Alt/Shift 等修饰键并敲击主键'),
                  const SizedBox(height: 20),
                  Center(
                    child: Container(
                      width: 240,
                      height: 60,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: HotKeyRecorder(
                        initalHotKey: oldHotKey,
                        onHotKeyRecorded: (newHotKey) {
                          setState(() {
                            recordedHotKey = newHotKey;
                          });
                        },
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: recordedHotKey == null
                      ? null
                      : () => Navigator.of(context).pop(true),
                  child: const Text('确认'),
                ),
              ],
            );
          },
        );
      },
    ).then((confirmed) async {
      if (!context.mounted) return;
      final notifier = context.read<PlaylistContentNotifier>();
      final settings = context.read<SettingsProvider>();

      if (confirmed == true && recordedHotKey != null) {
        // 保存设置
        await settings.setHotKey(type, recordedHotKey);
      }

      // 无论确认还是取消，都重新注册所有已启用的全局快捷键
      if (settings.enableGlobalHotkeys) {
        await GlobalHotkeyManager().registerAll(notifier, settings);
      }
    });
  }

  Widget _buildReadonlyHotkeyRow(
    BuildContext context,
    String title,
    String keysDisplay,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Text(
              keysDisplay,
              style: TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Theme.of(
                  context,
                ).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
