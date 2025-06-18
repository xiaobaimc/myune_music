import 'package:flutter/material.dart';
import '../../theme/theme_selection_screen.dart';

class Setting extends StatelessWidget {
  const Setting({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("设置页面")),
      body: const Column(children: [Divider(), ThemeSelectionScreen()]),
      // TODO:添加允许用户自定义播放详情页显示歌词行数
    );
  }
}
