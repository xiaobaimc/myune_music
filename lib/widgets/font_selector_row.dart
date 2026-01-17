import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:system_fonts/system_fonts.dart';
import 'package:flutter_web_scroll/flutter_web_scroll.dart';
import '../theme/theme_provider.dart';

class FontSelectorRow extends StatefulWidget {
  const FontSelectorRow({super.key});

  @override
  State<FontSelectorRow> createState() => _FontSelectorRowState();
}

class _FontSelectorRowState extends State<FontSelectorRow> {
  final systemFonts = SystemFonts();

  Future<void> _showFontSelectionDialog(BuildContext context) async {
    final themeProvider = context.read<ThemeProvider>();
    final currentFontFamily = themeProvider.currentFontFamily;

    // 获取系统所有字体
    final fontList = systemFonts.getFontList();
    // 在列表开头插入"Misans"作为默认选项
    final fonts = ['Misans', ...fontList];

    // 去重并保持顺序
    final uniqueFonts = <String>[];
    for (final font in fonts) {
      if (!uniqueFonts.contains(font)) {
        uniqueFonts.add(font);
      }
    }

    String? selectedFont = currentFontFamily;

    final scrollController = ScrollController();

    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(
                '预览字体：${selectedFont ?? "默认"}',
                style: TextStyle(fontFamily: selectedFont),
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: RadioGroup<String>(
                  groupValue: selectedFont,
                  onChanged: (value) async {
                    setState(() {
                      selectedFont = value;
                    });

                    if (value != null && value != 'Misans') {
                      try {
                        await systemFonts.loadFont(value);
                        setState(() {}); // 加载完刷新ui，让标题字体立即变化
                      } catch (e) {
                        //
                      }
                    }
                  },

                  child: SmoothScrollWeb(
                    controller: scrollController,
                    config: SmoothScrollConfig.lenis(),
                    child: ListView.builder(
                      controller: scrollController,
                      shrinkWrap: true,
                      itemCount: uniqueFonts.length,
                      itemBuilder: (context, index) {
                        final fontFamily = uniqueFonts[index];
                        return RadioListTile<String>.adaptive(
                          title: Text(index == 0 ? '默认字体' : fontFamily),
                          value: fontFamily,
                        );
                      },
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () async {
                    final themeProvider = context.read<ThemeProvider>();
                    final navigator = Navigator.of(context); // 提前保存 navigator

                    if (selectedFont != null) {
                      themeProvider.setFontFamily(selectedFont!);
                    }
                    if (!mounted) return;
                    navigator.pop();
                  },
                  child: const Text('确定'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('自定义字体', style: Theme.of(context).textTheme.titleMedium),
        ElevatedButton.icon(
          onPressed: () => _showFontSelectionDialog(context),
          icon: const Icon(Icons.text_fields_rounded, size: 20),
          label: const Text('选择字体'),
        ),
      ],
    );
  }
}
