import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/theme_provider.dart';
import 'font_selector_dialog.dart';

class FontSelectorRow extends StatefulWidget {
  const FontSelectorRow({super.key});

  @override
  State<FontSelectorRow> createState() => _FontSelectorRowState();
}

class _FontSelectorRowState extends State<FontSelectorRow> {
  Future<void> _showFontSelectionDialog(BuildContext context) async {
    final themeProvider = context.read<ThemeProvider>();
    final currentFontFamily = themeProvider.currentFontFamily;

    final selectedFont = await showDialog<String>(
      context: context,
      builder: (context) => FontSelectorDialog(
        currentFontFamily: currentFontFamily,
      ),
    );

    if (selectedFont != null && mounted) {
      themeProvider.setFontFamily(selectedFont);
    }
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
