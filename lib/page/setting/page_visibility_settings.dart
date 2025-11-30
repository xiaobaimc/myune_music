import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'settings_provider.dart';

class PageVisibilitySettings extends StatefulWidget {
  const PageVisibilitySettings({super.key});

  @override
  State<PageVisibilitySettings> createState() => PageVisibilitySettingsState();
}

class PageVisibilitySettingsState extends State<PageVisibilitySettings> {
  // 页面列表
  final List<String> _pages = ['全部歌曲', '歌手', '专辑', '统计', '歌曲详情信息'];

  Future<void> _showPageVisibilityDialog(BuildContext context) async {
    final settings = context.read<SettingsProvider>();
    final currentHiddenPages = settings.hiddenPages.toSet();
    final Set<String> selectedHiddenPages = Set<String>.from(
      currentHiddenPages,
    );

    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('页面可见性设置'),
              content: SizedBox(
                width: 300,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListView.builder(
                      shrinkWrap: true,
                      itemCount: _pages.length,
                      itemBuilder: (context, index) {
                        final page = _pages[index];
                        final isHidden = selectedHiddenPages.contains(page);

                        return CheckboxListTile(
                          title: Text(page),
                          value: !isHidden,
                          onChanged: (value) {
                            setState(() {
                              if (value == false) {
                                selectedHiddenPages.add(page);
                              } else {
                                selectedHiddenPages.remove(page);
                              }
                            });
                          },
                        );
                      },
                    ),
                  ],
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
                  onPressed: () {
                    settings.setHiddenPages(selectedHiddenPages.toList());
                    Navigator.of(context).pop();
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
        Text('页面可见性设置', style: Theme.of(context).textTheme.titleMedium),
        ElevatedButton.icon(
          onPressed: () => _showPageVisibilityDialog(context),
          icon: const Icon(Icons.cancel_outlined, size: 20),
          label: const Text('配置页面'),
        ),
      ],
    );
  }
}
