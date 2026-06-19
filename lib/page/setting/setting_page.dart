import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:markdown_widget/markdown_widget.dart';

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
import 'playlist_cleaner.dart';
import 'folder_playlist_refresher.dart';

// 定义应用版本号常量
const String appVersion = '0.9.1';

bool get isLinux => Platform.isLinux;

class SettingPage extends StatefulWidget {
  const SettingPage({super.key});

  @override
  State<SettingPage> createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  int _selectedIndex = 0;
  final bool _isCheckingUpdate = false; // 是否正在检查更新
  final String _updateStatus = ''; // 更新状态信息

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
          content: SizedBox(
            width: double.maxFinite,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.65,
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsetsGeometry.all(12),
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

    return Row(
      children: [
        // 左侧导航栏
        Container(
          width: 150,
          color: Colors.transparent,
          child: Column(
            children: [
              _SettingNavItem(
                index: 0,
                title: '常规',
                icon: Icons.settings_outlined,
                isSelected: _selectedIndex == 0,
                onTap: () => setState(() => _selectedIndex = 0),
              ),
              _SettingNavItem(
                index: 1,
                title: '个性化',
                icon: Icons.palette_outlined,
                isSelected: _selectedIndex == 1,
                onTap: () => setState(() => _selectedIndex = 1),
              ),
              _SettingNavItem(
                index: 2,
                title: '播放页',
                icon: Icons.play_circle_outline,
                isSelected: _selectedIndex == 2,
                onTap: () => setState(() => _selectedIndex = 2),
              ),
              _SettingNavItem(
                index: 3,
                title: '播放设置',
                icon: Icons.volume_up_outlined,
                isSelected: _selectedIndex == 3,
                onTap: () => setState(() => _selectedIndex = 3),
              ),
              _SettingNavItem(
                index: 4,
                title: '高级',
                icon: Icons.construction_outlined,
                isSelected: _selectedIndex == 4,
                onTap: () => setState(() => _selectedIndex = 4),
              ),
            ],
          ),
        ),
        // 垂直分割线
        VerticalDivider(
          width: 1,
          thickness: 1,
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        // 右侧实际设置项
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 80),
            transitionBuilder: (Widget child, Animation<double> animation) {
              return FadeTransition(opacity: animation, child: child);
            },
            child: () {
              switch (_selectedIndex) {
                case 0:
                  return ListView(
                    key: const ValueKey('general'),
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
                      // 主题模式
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '主题模式',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Consumer<ThemeProvider>(
                              builder: (context, themeProvider, child) {
                                return SegmentedButton<ThemeMode>(
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
                                      value: ThemeMode.light,
                                      label: Text('浅色'),
                                    ),
                                    ButtonSegment(
                                      value: ThemeMode.dark,
                                      label: Text('深色'),
                                    ),
                                    ButtonSegment(
                                      value: ThemeMode.system,
                                      label: Text('自动'),
                                    ),
                                  ],
                                  selected: {themeProvider.themeMode},
                                  onSelectionChanged:
                                      (Set<ThemeMode> newSelection) {
                                        if (newSelection.isNotEmpty) {
                                          final selectedMode =
                                              newSelection.first;
                                          context
                                              .read<ThemeProvider>()
                                              .setThemeMode(selectedMode);
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
                            Text(
                              '动态主题配色',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(width: 4),
                            const InfoIcon("启用后将使用当前播放歌曲的封面颜色作为主题配色"),
                          ],
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
                          // 当关闭动态颜色时，恢复用户手动选择的种子色
                          if (!value) {
                            context
                                .read<ThemeProvider>()
                                .restoreLastManualColor();
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
                          context
                              .read<SettingsProvider>()
                              .setEnableOnlineLyrics(value);
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
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
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
                                    ButtonSegment(
                                      value: 'qq',
                                      label: Text('企鹅'),
                                    ),
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
                  );
                case 1:
                  return ListView(
                    key: const ValueKey('personalization'),
                    children: [
                      // 系统字体选择器
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: FontSelectorRow(),
                      ),

                      // 页面可见性设置
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: PageVisibilitySettings(),
                      ),

                      if (Platform.isWindows)
                        SwitchListTile(
                          title: const Text('在任务栏显示播放进度'),
                          value: settings.showTaskbarProgress,
                          onChanged: (value) {
                            context
                                .read<SettingsProvider>()
                                .setShowTaskbarProgress(value);
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
                          context
                              .read<SettingsProvider>()
                              .setForceSingleLineLyric(value);
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
                          context
                              .read<SettingsProvider>()
                              .setPreferExternalLyrics(value);
                        },
                      ),
                      // 始终显示专辑名称
                      SwitchListTile(
                        title: const Text('始终显示专辑名称'),
                        value: settings.showAlbumName,
                        onChanged: (value) {
                          context.read<SettingsProvider>().setShowAlbumName(
                            value,
                          );
                        },
                      ),
                    ],
                  );
                case 2:
                  return ListView(
                    key: const ValueKey('playback'),
                    children: [
                      // 启用模糊背景
                      SwitchListTile(
                        title: Text(
                          '播放页模糊背景',
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
                            Text('播放页动态背景'),
                            SizedBox(width: 4),
                            InfoIcon('实验性功能。启用后会略微提升性能占用\n未启用模糊背景时不生效'),
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
                          '歌词模糊效果',
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
                        title: const Text('高亮歌词始终垂直居中显示'),
                        value: settings.addLyricPadding,
                        onChanged: (value) {
                          context.read<SettingsProvider>().setAddLyricPadding(
                            value,
                          );
                        },
                      ),
                      // 启用歌词弹性滚动
                      SwitchListTile(
                        title: const Row(
                          children: [
                            Text('歌词弹性滚动'),
                            SizedBox(width: 4),
                            InfoIcon('实验性功能。启用后会显著提升性能占用'),
                          ],
                        ),
                        value: settings.enableLyricElasticScroll,
                        onChanged: (value) {
                          context
                              .read<SettingsProvider>()
                              .setEnableLyricElasticScroll(value);
                        },
                      ),
                    ],
                  );
                case 3:
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
                          final playlistNotifier = context
                              .read<PlaylistContentNotifier>();
                          if (value && settings.enableReplayGain) {
                            playlistNotifier.postInfo('与 "重放增益" 冲突');
                            return;
                          }
                          context.read<SettingsProvider>().setEnableLoudness(
                            value,
                          );
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
                          final playlistNotifier = context
                              .read<PlaylistContentNotifier>();
                          if (value && settings.enableLoudness) {
                            playlistNotifier.postInfo('与 "平衡歌曲音量" 冲突');
                            return;
                          }
                          context.read<SettingsProvider>().setEnableReplayGain(
                            value,
                          );
                          playlistNotifier.updateReplayGainSettings();
                        },
                      ),
                    ],
                  );
                case 4:
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
                              onPressed: () =>
                                  _showArtistSeparator(context, settings),
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
                          context.read<SettingsProvider>().setAllowAnyFormat(
                            value,
                          );
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
                          context.read<SettingsProvider>().setMinimizeToTray(
                            value,
                          );
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
                          context
                              .read<SettingsProvider>()
                              .setIgnorePlaybackErrors(value);
                        },
                      ),
                    ],
                  );
                default:
                  return const SizedBox.shrink();
              }
            }(),
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

class _SettingNavItem extends StatefulWidget {
  final int index;
  final String title;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _SettingNavItem({
    required this.index,
    required this.title,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_SettingNavItem> createState() => _SettingNavItemState();
}

class _SettingNavItemState extends State<_SettingNavItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: Material(
        color: widget.isSelected
            ? colorScheme.primary.withValues(alpha: 0.1)
            : _isHovered
            ? Colors.grey.withValues(alpha: 0.1)
            : Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          child: ListTile(
            horizontalTitleGap: 8,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            leading: Icon(
              widget.icon,
              size: 20,
              color: widget.isSelected
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
            title: AnimatedScale(
              duration: const Duration(milliseconds: 200),
              scale: widget.isSelected ? 1.05 : 1.0,
              alignment: Alignment.centerLeft,
              child: Text(
                widget.title,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: widget.isSelected ? colorScheme.primary : null,
                ),
              ),
            ),
            selected: widget.isSelected,
          ),
        ),
      ),
    );
  }
}
