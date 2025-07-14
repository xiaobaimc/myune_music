import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import './theme_selection_screen.dart';
import '../../theme/theme_provider.dart';
import './settings_provider.dart'; // 确保路径正确
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

  @override
  void initState() {
    super.initState();
    // 直接在 initState 中初始化控制器
    // 确保 SettingsProvider 在此之前已通过 MultiProvider 提供
    _onlineLyricsApiController = TextEditingController(
      text: context.read<SettingsProvider>().onlineLyricsApi,
    );

    // 监听 settingsProvider 的变化，同步更新 TextEditingController
    // 确保在 dispose 中移除监听
    context.read<SettingsProvider>().addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    // 移除监听器并释放控制器
    context.read<SettingsProvider>().removeListener(_onSettingsChanged);
    _onlineLyricsApiController.dispose();
    super.dispose();
  }

  // 监听器方法，当 SettingsProvider 变化时更新 _onlineLyricsApiController 的文本
  void _onSettingsChanged() {
    // 仅当文本内容实际不同时才更新，避免不必要的重建和光标跳动
    if (_onlineLyricsApiController.text !=
        context.read<SettingsProvider>().onlineLyricsApi) {
      _onlineLyricsApiController.text = context
          .read<SettingsProvider>()
          .onlineLyricsApi;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 使用 watch 来监听 SettingsProvider 的变化
    final settings = context.watch<SettingsProvider>();

    return Column(
      children: [
        const Divider(height: 1, thickness: 1),
        const ThemeSelectionScreen(),
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
                    '启用后可能会导致播放不流畅,软件默认提供了api,但建议按照项目介绍关于网络获取歌词的描述部署一个',
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
              decoration: InputDecoration(
                labelText: '歌词API地址',
                hintText: '请输入歌词获取API地址 (例如: https://lrcapi.showby.top)',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.restore),
                  onPressed: () {
                    _onlineLyricsApiController.clear();
                    context.read<SettingsProvider>().setOnlineLyricsApi(
                      'https://lrcapi.showby.top',
                    );
                  },
                ),
              ),
              onChanged: (value) {
                context.read<SettingsProvider>().setOnlineLyricsApi(value);
              },
            ),
          ),
        // 详情页同时间戳最大显示歌词行数
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '详情页同时间戳最大显示歌词行数',
                style: Theme.of(context).textTheme.titleMedium,
              ),
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
        // 启用动态获取颜色
        SwitchListTile(
          title: Text(
            '在详情页时,提取封面图颜色作为主题配色',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          value: settings.useDynamicColor, // 使用 settings
          onChanged: (value) {
            context.read<SettingsProvider>().setUseDynamicColor(value);
            // 当关闭动态颜色时，恢复默认颜色
            if (!value) {
              context.read<ThemeProvider>().setSeedColor(Colors.blue);
            }
          },
        ),
      ],
    );
  }
}
