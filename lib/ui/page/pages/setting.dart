import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/theme_selection_screen.dart';
import '../../theme/theme_provider.dart';

class Setting extends StatelessWidget {
  const Setting({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("设置页面")),
      body: Column(
        children: [
          const Divider(),
          const ThemeSelectionScreen(),
          SwitchListTile(
            title: const Text('深色模式'),
            value: context.watch<ThemeProvider>().isDarkMode,
            onChanged: (value) =>
                context.read<ThemeProvider>().toggleDarkMode(),
          ),
        ],
      ),
      // TODO:添加允许用户自定义播放详情页显示歌词行数
    );
  }
}
