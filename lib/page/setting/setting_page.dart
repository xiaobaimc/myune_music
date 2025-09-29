import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../playlist/playlist_content_notifier.dart';
import './theme_selection_screen.dart';
import '../../theme/theme_provider.dart';
import './settings_provider.dart';
import '../../widgets/font_selector_row.dart';
import 'update_checker.dart';
import 'audio_device_selector.dart';
import 'artist_separator.dart';

// 定义应用版本号常量
const String appVersion = '0.6.5';

bool get isLinux => Platform.isLinux;

class SettingPage extends StatefulWidget {
  const SettingPage({super.key});

  @override
  State<SettingPage> createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _fontSelectorEnabled = false;
  final bool _isCheckingUpdate = false; // 是否正在检查更新
  final String _updateStatus = ''; // 更新状态信息

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
    // 使用 watch 来监听 SettingsProvider 的变化
    final settings = context.watch<SettingsProvider>();

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: '常规'),
              Tab(text: '播放页'),
              Tab(text: '高级'),
            ],
            // dividerColor: Colors.transparent,
            dividerHeight: 3,
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              // 常规设置
              ListView(
                children: [
                  // 主题配色选择
                  const ThemeSelectionScreen(),
                  // 检查更新按钮
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
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
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
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
                  // 深色模式
                  SwitchListTile(
                    title: Text(
                      '深色模式',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    value: context.watch<ThemeProvider>().isDarkMode,
                    onChanged: (value) =>
                        context.read<ThemeProvider>().toggleDarkMode(),
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
                      padding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: FontSelectorRow(),
                    ),
                  // 启用动态获取颜色
                  SwitchListTile(
                    title: Text(
                      '提取当前播放的封面图颜色作为主题配色',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    value: settings.useDynamicColor, // 使用 settings
                    onChanged: (value) {
                      context.read<SettingsProvider>().setUseDynamicColor(
                        value,
                      );
                      // 当启用动态颜色时，立即提取当前播放歌曲的封面颜色
                      if (value) {
                        final playlistNotifier = context
                            .read<PlaylistContentNotifier>();
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
                  // 始终保持单行歌词显示
                  SwitchListTile(
                    title: Text(
                      '顶部歌词始终单行显示',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    value: settings.forceSingleLineLyric,
                    onChanged: (value) {
                      context.read<SettingsProvider>().setForceSingleLineLyric(
                        value,
                      );
                    },
                  ),
                  // 是否启用从网络获取歌词
                  SwitchListTile(
                    title: const Text('从网络获取歌词'),
                    value: settings.enableOnlineLyrics,
                    onChanged: (value) {
                      context.read<SettingsProvider>().setEnableOnlineLyrics(
                        value,
                      );
                    },
                  ),
                  // 歌词源选择
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
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
                            const IconButton(
                              icon: Icon(Icons.info_outline, size: 20),
                              padding: EdgeInsets.zero,
                              constraints: BoxConstraints(),
                              tooltip:
                                  '主选来源为某易云音乐，备选来源为某狗音乐\n其中备选只有原文没有翻译，但歌词匹配可能会更精确\n当未启用从网络获取歌词时，该选项不会生效',
                              onPressed: null,
                            ),
                          ],
                        ),
                        Consumer<SettingsProvider>(
                          builder: (context, settings, child) {
                            return SegmentedButton<String>(
                              style: ButtonStyle(
                                padding: WidgetStateProperty.all(
                                  EdgeInsets.zero,
                                ),
                                visualDensity: VisualDensity.compact,
                                minimumSize: WidgetStateProperty.all(
                                  const Size(0, 0),
                                ),
                              ),
                              segments: const [
                                ButtonSegment(
                                  value: 'primary',
                                  label: Text('主选'),
                                ),
                                ButtonSegment(
                                  value: 'secondary',
                                  label: Text('备选'),
                                ),
                              ],
                              selected: {settings.primaryLyricSource},
                              onSelectionChanged: (newSelection) {
                                if (newSelection.isNotEmpty) {
                                  final selected = newSelection.first;
                                  final secondary = selected == 'primary'
                                      ? 'secondary'
                                      : 'primary';
                                  final settingsProvider = context
                                      .read<SettingsProvider>();

                                  settingsProvider.setPrimaryLyricSource(
                                    selected,
                                  );
                                  settingsProvider.setSecondaryLyricSource(
                                    secondary,
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
                ],
              ),

              // 播放页设置
              ListView(
                children: [
                  // 启用模糊背景
                  SwitchListTile(
                    title: Text(
                      '启用播放页模糊背景',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    value: settings.useBlurBackground, // 使用 settings
                    onChanged: (value) {
                      context.read<SettingsProvider>().setUseBlurBackground(
                        value,
                      );
                    },
                  ),
                  // 歌词上下补位设置
                  SwitchListTile(
                    title: const Text('强制播放页高亮歌词垂直居中显示'),
                    value: settings.addLyricPadding,
                    onChanged: (value) {
                      context.read<SettingsProvider>().setAddLyricPadding(
                        value,
                      );
                    },
                  ),
                  // 播放页同时间戳最大显示歌词行数
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '同时间戳歌词行数',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Consumer<SettingsProvider>(
                          builder: (context, settings, child) {
                            return SegmentedButton<int>(
                              style: ButtonStyle(
                                padding: WidgetStateProperty.all(
                                  EdgeInsets.zero,
                                ),
                                visualDensity: VisualDensity.compact,
                                minimumSize: WidgetStateProperty.all(
                                  const Size(0, 0),
                                ),
                              ),
                              segments: List.generate(5, (index) {
                                final value = index + 1;
                                return ButtonSegment(
                                  value: value,
                                  label: Text('$value'),
                                );
                              }),
                              selected: {
                                settings.maxLinesPerLyric,
                              }, // 使用 settings
                              onSelectionChanged: (newSelection) {
                                final value = newSelection.first;
                                context
                                    .read<SettingsProvider>()
                                    .setMaxLinesPerLyric(value);
                              },
                              showSelectedIcon: false,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  // 播放页歌词字体大小
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 0,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '播放页歌词字体大小',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        SizedBox(
                          width: 320, // 固定宽度
                          child: Consumer<SettingsProvider>(
                            builder: (context, settings, child) {
                              return Slider(
                                value: settings.fontSize, // 使用 settings
                                min: 12.0,
                                max: 32.0,
                                divisions: 20,
                                label: settings.fontSize.toStringAsFixed(
                                  1,
                                ), // 使用 settings
                                onChanged: (value) {
                                  context.read<SettingsProvider>().setFontSize(
                                    value,
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 播放页歌词垂直间距
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 0,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '播放页歌词垂直间距',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        SizedBox(
                          width: 320, // 固定宽度
                          child: Consumer<SettingsProvider>(
                            builder: (context, settings, child) {
                              return Slider(
                                value: settings.lyricVerticalSpacing,
                                min: 0.0,
                                max: 20.0,
                                divisions: 20,
                                label: settings.lyricVerticalSpacing
                                    .toStringAsFixed(1),
                                onChanged: (value) {
                                  context
                                      .read<SettingsProvider>()
                                      .setLyricVerticalSpacing(value);
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 对齐方式选择
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '播放页歌词对齐方式',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Consumer<SettingsProvider>(
                          builder: (context, settings, child) {
                            return SegmentedButton<TextAlign>(
                              style: ButtonStyle(
                                padding: WidgetStateProperty.all(
                                  EdgeInsets.zero,
                                ),
                                visualDensity: VisualDensity.compact,
                                minimumSize: WidgetStateProperty.all(
                                  const Size(0, 0),
                                ),
                              ),
                              segments: const [
                                ButtonSegment(
                                  value: TextAlign.left,
                                  label: Text('居左'),
                                ),
                                ButtonSegment(
                                  value: TextAlign.center,
                                  label: Text('居中'),
                                ),
                                ButtonSegment(
                                  value: TextAlign.right,
                                  label: Text('居右'),
                                ),
                              ],
                              selected: {
                                settings.lyricAlignment,
                              }, // 使用 settings
                              onSelectionChanged:
                                  (Set<TextAlign> newSelection) {
                                    if (newSelection.isNotEmpty) {
                                      context
                                          .read<SettingsProvider>()
                                          .setLyricAlignment(
                                            newSelection.first,
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
                ],
              ),

              // 高级设置
              ListView(
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
                          '手动指定音频输出设备',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        ElevatedButton.icon(
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (BuildContext context) {
                                return const AudioDeviceSelector();
                              },
                            );
                          },
                          icon: const Icon(Icons.headphones, size: 20),
                          label: const Text('选择设备'),
                        ),
                      ],
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
                          '自定义艺术家分隔符',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        ElevatedButton.icon(
                          onPressed: () =>
                              _showArtistSeparator(context, settings),
                          icon: const Icon(Icons.person, size: 20),
                          label: const Text('修改分隔符'),
                        ),
                      ],
                    ),
                  ),
                  // 独占模式设置
                  if (!isLinux) // 仅在非Linux平台显示
                    Consumer<PlaylistContentNotifier>(
                      builder: (context, playlistNotifier, child) {
                        return SwitchListTile(
                          title: const Row(
                            children: [
                              Text('启用独占模式'),
                              SizedBox(width: 4),
                              IconButton(
                                padding: EdgeInsets.zero,
                                constraints: BoxConstraints(),
                                icon: Icon(Icons.info_outline, size: 20),
                                tooltip:
                                    '启用后将使用独占模式播放音频，提供更低的延迟以及更好的音质\n这可能会导致其他应用无法播放音频\n仅在播放器处于活跃状态时可用',
                                onPressed: null,
                              ),
                            ],
                          ),
                          value: playlistNotifier.isExclusiveModeEnabled,
                          onChanged: playlistNotifier.toggleExclusiveMode,
                        );
                      },
                    ),
                  // 允许添加任何格式的文件
                  SwitchListTile(
                    title: const Row(
                      children: [
                        Text('允许添加任何格式的文件'),
                        SizedBox(width: 4),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: BoxConstraints(),
                          icon: Icon(Icons.info_outline, size: 20),
                          tooltip:
                              '启用后可以选择任何格式的文件添加到歌单中\n底层使用 mpv，依赖 FFmpeg 解码，理论上支持播放所有音频格式\n除非确认兼容性，否则请谨慎启用该选项',
                          onPressed: null,
                        ),
                      ],
                    ),
                    value: settings.allowAnyFormat,
                    onChanged: (value) {
                      context.read<SettingsProvider>().setAllowAnyFormat(value);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
