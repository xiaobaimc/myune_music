import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../setting/theme_selection_screen.dart';
import '../../theme/theme_provider.dart';
import '../../widgets/single_line_lyrics.dart';

class SettingsProvider with ChangeNotifier {
  int _maxLinesPerLyric = 2;

  int get maxLinesPerLyric => _maxLinesPerLyric;

  void setMaxLinesPerLyric(int value) {
    _maxLinesPerLyric = value;
    notifyListeners();
  }
}

class Setting extends StatelessWidget {
  const Setting({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const SingleLineLyricView(
          maxLinesPerLyric: 2,
          textAlign: TextAlign.left,
          alignment: Alignment.topLeft,
        ),
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: Column(
        children: [
          const Divider(height: 1),
          const ThemeSelectionScreen(),
          SwitchListTile(
            title: Text('深色模式', style: Theme.of(context).textTheme.titleMedium),
            value: context.watch<ThemeProvider>().isDarkMode,
            onChanged: (value) =>
                context.read<ThemeProvider>().toggleDarkMode(),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '详情页歌词最大歌词行数',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                SegmentedButton<int>(
                  segments: List.generate(5, (index) {
                    final value = index + 1;
                    return ButtonSegment(value: value, label: Text('$value'));
                  }),
                  selected: {
                    context.watch<SettingsProvider>().maxLinesPerLyric,
                  },
                  onSelectionChanged: (newSelection) {
                    final value = newSelection.first;
                    context.read<SettingsProvider>().setMaxLinesPerLyric(value);
                  },
                  showSelectedIcon: false,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
