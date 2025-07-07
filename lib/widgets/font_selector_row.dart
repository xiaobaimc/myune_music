import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:system_fonts/system_fonts.dart';
import '../theme/theme_provider.dart';

class FontSelectorRow extends StatefulWidget {
  const FontSelectorRow({super.key});

  @override
  State<FontSelectorRow> createState() => _FontSelectorRowState();
}

class _FontSelectorRowState extends State<FontSelectorRow> {
  final systemFonts = SystemFonts();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('自定义字体', style: Theme.of(context).textTheme.titleMedium),
        Row(
          children: [
            TextButton.icon(
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('恢复默认字体'),
              onPressed: () {
                context.read<ThemeProvider>().resetFontFamily();
              },
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 180,
              child: SystemFontSelector(
                onFontSelected: (font) async {
                  final themeProvider = context.read<ThemeProvider>();
                  await systemFonts.loadFont(font);
                  themeProvider.setFontFamily(font);
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}
