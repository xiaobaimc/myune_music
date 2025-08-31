import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../playlist/playlist_content_notifier.dart';
import './theme_selection_screen.dart';
import '../../theme/theme_provider.dart';
import './settings_provider.dart';
import '../../widgets/font_selector_row.dart';
import 'update_checker.dart';

// 定义应用版本号常量
const String appVersion = '0.6.2';

class SettingPage extends StatefulWidget {
  const SettingPage({super.key});

  @override
  State<SettingPage> createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  bool _fontSelectorEnabled = false;
  final bool _isCheckingUpdate = false; // 是否正在检查更新
  final String _updateStatus = ''; // 更新状态信息

  @override
  void initState() {
    super.initState();
  }

  // 检查更新
  Future<void> _checkForUpdates() async {
    final notifier = context.read<PlaylistContentNotifier>();

    try {
      notifier.postInfo('正在检查更新...');

      // 使用写好的版本号
      final result = await UpdateChecker.checkForUpdates(appVersion);

      switch (result.type) {
        case UpdateCheckResultType.successUpdateAvailable:
          notifier.postInfo('发现新版本 ${result.updateInfo!.latestVersion}');
          _showUpdateDialog(result.updateInfo!);
          break;
        case UpdateCheckResultType.successNoUpdate:
          notifier.postInfo('当前已是最新版本');
          break;
        case UpdateCheckResultType.error:
          notifier.postError('检查更新失败: ${result.errorMessage}');
          break;
      }
    } catch (e) {
      notifier.postError('检查更新失败: ${e.toString()}');
    }
  }

  // 显示更新对话框
  void _showUpdateDialog(UpdateInfo updateInfo) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('发现新版本 ${updateInfo.latestVersion}'),
          content: SingleChildScrollView(child: Text(updateInfo.releaseNotes)),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('稍后更新'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                if (await canLaunchUrl(Uri.parse(updateInfo.downloadUrl))) {
                  await launchUrl(Uri.parse(updateInfo.downloadUrl));
                }
              },
              child: const Text('前往下载'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // 使用 watch 来监听 SettingsProvider 的变化
    final settings = context.watch<SettingsProvider>();

    return ListView(
      children: [
        // 主题配色选择
        const ThemeSelectionScreen(),
        // 检查更新按钮
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '当前版本: $appVersion',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              ElevatedButton.icon(
                onPressed: _checkForUpdates,
                icon: _isCheckingUpdate
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.update, size: 20),
                label: const Text('检查更新'),
              ),
            ],
          ),
        ),
        if (_updateStatus.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _updateStatus,
              style: TextStyle(
                color: _updateStatus.contains('失败')
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        // 启用动态获取颜色
        SwitchListTile(
          title: Text(
            '提取当前播放的封面图颜色作为主题配色',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          value: settings.useDynamicColor, // 使用 settings
          onChanged: (value) {
            context.read<SettingsProvider>().setUseDynamicColor(value);
            // 当启用动态颜色时，立即提取当前播放歌曲的封面颜色
            if (value) {
              final playlistNotifier = context.read<PlaylistContentNotifier>();
              final currentSong = playlistNotifier.currentSong;
              if (currentSong != null) {
                playlistNotifier.extractAndApplyDynamicColor(
                  currentSong.albumArt,
                );
              }
            }
            // 当关闭动态颜色时，恢复默认颜色
            if (!value) {
              context.read<ThemeProvider>().setSeedColor(Colors.blue);
            }
          },
        ),
        // 深色模式
        SwitchListTile(
          title: Text('深色模式', style: Theme.of(context).textTheme.titleMedium),
          value: context.watch<ThemeProvider>().isDarkMode,
          onChanged: (value) => context.read<ThemeProvider>().toggleDarkMode(),
        ),
        // 启用系统字体选择器
        SwitchListTile(
          title: Text(
            '启用系统字体选择器',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          value: _fontSelectorEnabled,
          onChanged: (value) {
            setState(() {
              _fontSelectorEnabled = value;
            });
          },
        ),
        // 系统字体选择器
        if (_fontSelectorEnabled)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: FontSelectorRow(),
          ),
        // 启用模糊背景
        SwitchListTile(
          title: Text(
            '启用详情页模糊背景',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          value: settings.useBlurBackground, // 使用 settings
          onChanged: (value) {
            context.read<SettingsProvider>().setUseBlurBackground(value);
          },
        ),
        // 是否启用从网络获取歌词
        SwitchListTile(
          title: const Text('从网络获取歌词'),
          value: settings.enableOnlineLyrics,
          onChanged: (value) {
            context.read<SettingsProvider>().setEnableOnlineLyrics(value);
          },
        ),
        // 详情页同时间戳最大显示歌词行数
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('同时间戳歌词行数', style: Theme.of(context).textTheme.titleMedium),
              SegmentedButton<int>(
                segments: List.generate(5, (index) {
                  final value = index + 1;
                  return ButtonSegment(value: value, label: Text('$value'));
                }),
                selected: {settings.maxLinesPerLyric}, // 使用 settings
                onSelectionChanged: (newSelection) {
                  final value = newSelection.first;
                  context.read<SettingsProvider>().setMaxLinesPerLyric(value);
                },
                showSelectedIcon: false,
              ),
            ],
          ),
        ),
        // 详情页歌词字体大小
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('详情页歌词字体大小', style: Theme.of(context).textTheme.titleMedium),
              SizedBox(
                width: 320, // 固定宽度
                child: Slider(
                  value: settings.fontSize, // 使用 settings
                  min: 12.0,
                  max: 32.0,
                  divisions: 20,
                  label: settings.fontSize.toStringAsFixed(1), // 使用 settings
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
                selected: {settings.lyricAlignment}, // 使用 settings
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
