import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:markdown_widget/markdown_widget.dart';

import '../../playlist/playlist_content_notifier.dart';
import '../theme_selection_screen.dart';
import '../../../theme/theme_provider.dart';
import '../settings_provider.dart';
import '../update_checker.dart';
import '../about.dart';
import '../setting_page.dart';
import 'info_icon.dart';

class GeneralTab extends StatefulWidget {
  const GeneralTab({super.key});

  @override
  State<GeneralTab> createState() => _GeneralTabState();
}

class _GeneralTabState extends State<GeneralTab> {
  bool _isCheckingUpdate = false; // 是否正在检查更新
  String _updateStatus = ''; // 更新状态信息

  // 检查更新
  Future<void> _checkForUpdates() async {
    final notifier = context.read<PlaylistContentNotifier>();

    setState(() {
      _isCheckingUpdate = true;
      _updateStatus = '正在检查更新...';
    });

    try {
      notifier.postInfo('正在检查更新...');

      // 使用写好的版本号
      final result = await UpdateChecker.checkForUpdates(appVersion);

      if (!mounted) return;

      switch (result.type) {
        case UpdateCheckResultType.successUpdateAvailable:
          notifier.postInfo('发现新版本 ${result.updateInfo!.latestVersion}');
          setState(() {
            _isCheckingUpdate = false;
            _updateStatus = '发现新版本 ${result.updateInfo!.latestVersion}';
          });
          _showUpdateDialog(result.updateInfo!);
          break;
        case UpdateCheckResultType.successNoUpdate:
          notifier.postInfo('当前已是最新版本');
          setState(() {
            _isCheckingUpdate = false;
            _updateStatus = '当前已是最新版本';
          });
          break;
        case UpdateCheckResultType.error:
          notifier.postError('检查更新失败: ${result.errorMessage}');
          setState(() {
            _isCheckingUpdate = false;
            _updateStatus = '检查更新失败: ${result.errorMessage}';
          });
          break;
      }
    } catch (e) {
      if (!mounted) return;
      notifier.postError('检查更新失败: ${e.toString()}');
      setState(() {
        _isCheckingUpdate = false;
        _updateStatus = '检查更新失败: ${e.toString()}';
      });
    }
  }

  // 显示更新对话框
  void _showUpdateDialog(UpdateInfo updateInfo) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('发现新版本 ${updateInfo.latestVersion}'),
          content: SizedBox(
            width: double.maxFinite,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.65,
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: MarkdownWidget(
                    data: (updateInfo.releaseNotes),
                    shrinkWrap: true,
                  ),
                ),
              ),
            ),
          ),
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
    final settings = context.watch<SettingsProvider>();

    return ListView(
      key: const ValueKey('general'),
      children: [
        // 主题配色选择
        const ThemeSelectionScreen(),
        // 检查更新按钮
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
        // 主题模式
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('主题模式', style: Theme.of(context).textTheme.titleMedium),
              Consumer<ThemeProvider>(
                builder: (context, themeProvider, child) {
                  return SegmentedButton<ThemeMode>(
                    style: ButtonStyle(
                      padding: WidgetStateProperty.all(EdgeInsets.zero),
                      visualDensity: VisualDensity.compact,
                      minimumSize: WidgetStateProperty.all(const Size(0, 0)),
                    ),
                    segments: const [
                      ButtonSegment(value: ThemeMode.light, label: Text('浅色')),
                      ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
                      ButtonSegment(value: ThemeMode.system, label: Text('自动')),
                    ],
                    selected: {themeProvider.themeMode},
                    onSelectionChanged: (Set<ThemeMode> newSelection) {
                      if (newSelection.isNotEmpty) {
                        final selectedMode = newSelection.first;
                        context.read<ThemeProvider>().setThemeMode(
                          selectedMode,
                        );
                      }
                    },
                    showSelectedIcon: false,
                  );
                },
              ),
            ],
          ),
        ),
        // 启用动态获取颜色
        SwitchListTile(
          title: Row(
            children: [
              Text('动态主题配色', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(width: 4),
              const InfoIcon("启用后将使用当前播放歌曲的封面颜色作为主题配色"),
            ],
          ),
          value: settings.useDynamicColor,
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
            // 当关闭动态颜色时，恢复用户手动选择的种子色
            if (!value) {
              context.read<ThemeProvider>().restoreLastManualColor();
            }
          },
        ),
        // 是否启用从网络获取歌词
        SwitchListTile(
          title: const Row(
            children: [
              Text('从网络获取歌词'),
              SizedBox(width: 4),
              InfoIcon("启用后将在未读取到内嵌及本地lrc歌词时从网络获取歌词"),
            ],
          ),
          value: settings.enableOnlineLyrics,
          onChanged: (value) {
            context.read<SettingsProvider>().setEnableOnlineLyrics(value);
          },
        ),
        // 歌词源选择
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    '网络歌词源选择',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(width: 4),
                  const InfoIcon('企鹅：匹配准、支持翻译（推荐）\n网抑：匹配一般，支持翻译\n库狗：匹配高，不支持翻译'),
                ],
              ),
              Consumer<SettingsProvider>(
                builder: (context, settings, child) {
                  return SegmentedButton<String>(
                    style: ButtonStyle(
                      padding: WidgetStateProperty.all(EdgeInsets.zero),
                      visualDensity: VisualDensity.compact,
                      minimumSize: WidgetStateProperty.all(const Size(0, 0)),
                    ),
                    segments: const [
                      ButtonSegment(value: 'qq', label: Text('企鹅')),
                      ButtonSegment(value: 'netease', label: Text('网抑')),
                      ButtonSegment(value: 'kugou', label: Text('库狗')),
                    ],
                    selected: {settings.primaryLyricSource},
                    onSelectionChanged: (newSelection) {
                      if (newSelection.isNotEmpty) {
                        final selected = newSelection.first;
                        String secondary;
                        if (selected == 'qq') {
                          secondary = 'netease';
                        } else if (selected == 'netease') {
                          secondary = 'qq';
                        } else {
                          secondary = 'qq';
                        }

                        final settingsProvider = context
                            .read<SettingsProvider>();

                        settingsProvider.setPrimaryLyricSource(selected);
                        settingsProvider.setSecondaryLyricSource(secondary);
                      }
                    },
                    showSelectedIcon: false,
                  );
                },
              ),
            ],
          ),
        ),
        // 关于
        const About(),
      ],
    );
  }
}
