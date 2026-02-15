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
import 'about.dart';
import 'page_visibility_settings.dart';

// 定义应用版本号常量
const String appVersion = '0.8.5';

bool get isLinux => Platform.isLinux;

class SettingPage extends StatefulWidget {
  const SettingPage({super.key});

  @override
  State<SettingPage> createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final bool _isCheckingUpdate = false; // 是否正在检查更新
  final String _updateStatus = ''; // 更新状态信息

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
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
              Tab(text: '个性化'),
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
                            const InfoIcon(
                              '企鹅：匹配准、支持翻译（推荐）\n网抑：匹配一般，支持翻译\n库狗：匹配高，不支持翻译',
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
                                ButtonSegment(value: 'qq', label: Text('企鹅')),
                                ButtonSegment(
                                  value: 'netease',
                                  label: Text('网抑'),
                                ),
                                ButtonSegment(
                                  value: 'kugou',
                                  label: Text('库狗'),
                                ),
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
                  // 关于
                  const About(),
                ],
              ),

              // 个性化设置
              ListView(
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
                        context.read<SettingsProvider>().setShowTaskbarProgress(
                          value,
                        );
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
                      context.read<SettingsProvider>().setForceSingleLineLyric(
                        value,
                      );
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
                      context.read<SettingsProvider>().setPreferExternalLyrics(
                        value,
                      );
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
                  // 启用动态背景
                  SwitchListTile(
                    title: const Row(
                      children: [
                        Text('启用播放页动态背景'),
                        SizedBox(width: 4),
                        InfoIcon('未启用模糊背景时不生效'),
                      ],
                    ),
                    value: settings.enableDynamicBackground,
                    onChanged: (value) {
                      context
                          .read<SettingsProvider>()
                          .setEnableDynamicBackground(value);
                    },
                  ),
                  // 启用歌词模糊效果
                  SwitchListTile(
                    title: Text(
                      '启用歌词模糊效果',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    value: settings.enableLyricBlur,
                    onChanged: (value) {
                      context.read<SettingsProvider>().setEnableLyricBlur(
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
                              InfoIcon(
                                '启用后将使用独占模式播放音频，提供更低的延迟以及更好的音质\n这会导致其他应用无法播放音频\n仅在播放器处于活跃状态时可用',
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
                      context.read<SettingsProvider>().setIgnorePlaybackErrors(
                        value,
                      );
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

class InfoIcon extends StatelessWidget {
  const InfoIcon(
    this.message, {
    super.key,
    this.size = 20,
    this.icon = Icons.info_outline,
  });

  final String message;
  final double size;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final disabledColor = Theme.of(context).disabledColor;
    return Tooltip(
      message: message,
      child: Icon(icon, size: size, color: disabledColor),
    );
  }
}
