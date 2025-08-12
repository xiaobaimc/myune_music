import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../playlist/playlist_content_notifier.dart';
import './theme_selection_screen.dart';
import '../../theme/theme_provider.dart';
import './settings_provider.dart';
import '../../widgets/font_selector_row.dart';

class SettingPage extends StatefulWidget {
  const SettingPage({super.key});

  @override
  State<SettingPage> createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  bool _fontSelectorEnabled = false;

  // 直接初始化 TextEditingController
  late final TextEditingController _onlineLyricsApiController;
  late final FocusNode _onlineLyricsApiFocusNode;

  // 先存下 SettingsProvider
  late final SettingsProvider _settingsProvider;

  @override
  void initState() {
    super.initState();
    // 先存下来，后面不再使用 context.read
    _settingsProvider = context.read<SettingsProvider>();

    // 直接在 initState 中初始化控制器
    // 确保 SettingsProvider 在此之前已通过 MultiProvider 提供
    _onlineLyricsApiController = TextEditingController(
      text: _settingsProvider.onlineLyricsApi,
    );

    // 初始化FocusNode并添加监听器
    _onlineLyricsApiFocusNode = FocusNode();
    _onlineLyricsApiFocusNode.addListener(_onLyricsApiFocusChange);

    // 监听 settingsProvider 的变化，同步更新 TextEditingController
    // 确保在 dispose 中移除监听
    _settingsProvider.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    // 小部件已销毁，需要移除监听器避免内存泄漏
    _settingsProvider.removeListener(_onSettingsChanged);
    _onlineLyricsApiFocusNode.removeListener(_onLyricsApiFocusChange); // 移除监听器
    _onlineLyricsApiFocusNode.dispose(); // 释放FocusNode
    _onlineLyricsApiController.dispose();
    super.dispose();
  }

  // 处理焦点变化
  // 用于屏蔽快捷键的（屏蔽快捷键通过检测isSearching屏蔽的）
  void _onLyricsApiFocusChange() {
    final notifier = context.read<PlaylistContentNotifier>();
    if (_onlineLyricsApiFocusNode.hasFocus) {
      // 当输入框获得焦点时，触发搜索状态以屏蔽快捷键
      if (!notifier.isSearching) {
        notifier.startSearch();
      }
    } else {
      // 当输入框失去焦点时，取消搜索状态以恢复快捷键
      if (notifier.isSearching) {
        notifier.stopSearch();
      }
    }
  }

  // 监听器方法，当 SettingsProvider 变化时更新 _onlineLyricsApiController 的文本
  void _onSettingsChanged() {
    // 仅当文本内容实际不同时才更新，避免不必要的重建和光标跳动
    if (_onlineLyricsApiController.text != _settingsProvider.onlineLyricsApi) {
      _onlineLyricsApiController.text = _settingsProvider.onlineLyricsApi;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 使用 watch 来监听 SettingsProvider 的变化
    final settings = context.watch<SettingsProvider>();

    return ListView(
      children: [
        // 主题配色选择
        const ThemeSelectionScreen(),
        // 启用动态获取颜色
        SwitchListTile(
          title: Text(
            '提取当前播放的封面图颜色作为主题配色',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          value: settings.useDynamicColor, // 使用 settings
          onChanged: (value) {
            _settingsProvider.setUseDynamicColor(value);
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
            '启用系统字体选择器 (可能会卡顿)',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          value: _fontSelectorEnabled,
          onChanged: (value) {
            setState(() {
              _fontSelectorEnabled = value;
            });
            if (value) {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('提示'),
                  content: const Text('选择完字体，建议关闭该选项。因为字体已经生效了。保持开启可能会导致页面卡顿'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('好的'),
                    ),
                  ],
                ),
              );
            }
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
            _settingsProvider.setUseBlurBackground(value);
          },
        ),
        // 是否启用从网络获取歌词
        SwitchListTile(
          title: Text(
            '从网络获取歌词',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          value: settings.enableOnlineLyrics,
          onChanged: (value) {
            context.read<SettingsProvider>().setEnableOnlineLyrics(value);
            if (value) {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('提示'),
                  content: const Text(
                    '启用后会在未找到内联歌词和本地lrc文件时从网络获取歌词\n软件默认提供了api,但建议按照项目介绍关于网络获取歌词的描述部署一个',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('好的'),
                    ),
                  ],
                ),
              );
            }
          },
        ),
        // 如果启用从网络获取歌词，则显示API输入框
        if (settings.enableOnlineLyrics)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: TextField(
              controller: _onlineLyricsApiController,
              focusNode: _onlineLyricsApiFocusNode,
              decoration: InputDecoration(
                labelText: '歌词API地址',
                hintText: '请输入歌词获取API地址 (例如: https://lrcapi.showby.top)',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.restore),
                  onPressed: () {
                    _onlineLyricsApiController.clear();
                    _settingsProvider.setOnlineLyricsApi(
                      'https://lrcapi.showby.top',
                    );
                  },
                ),
              ),
              onChanged: (value) {
                _settingsProvider.setOnlineLyricsApi(value);
              },
            ),
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
                  _settingsProvider.setMaxLinesPerLyric(value);
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
                    _settingsProvider.setFontSize(value);
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
                    _settingsProvider.setLyricAlignment(newSelection.first);
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
