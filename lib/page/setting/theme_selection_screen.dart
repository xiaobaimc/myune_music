import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/theme_provider.dart';
import 'settings_provider.dart';

class ThemeSelectionScreen extends StatelessWidget {
  const ThemeSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '主题配色',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              ElevatedButton.icon(
                onPressed: () => _showColorPickerDialog(context),
                icon: const Icon(Icons.palette_outlined, size: 20),
                label: const Text('选择颜色'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showColorPickerDialog(BuildContext context) async {
    final themeProvider = context.read<ThemeProvider>();
    final settings = context.read<SettingsProvider>();

    final wasDynamicColorEnabled = settings.useDynamicColor;
    final savedSeedColor = themeProvider.currentSeedColor;
    final lastManualColor = themeProvider.lastManualSeedColor;
    final brightness =
        themeProvider.isDarkMode ? Brightness.dark : Brightness.light;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => _ColorPickerDialog(
        initialSeedColor: lastManualColor,
        brightness: brightness,
      ),
    );

    if (result != true && context.mounted) {
      if (wasDynamicColorEnabled) {
        settings.setUseDynamicColor(true);
      }
      themeProvider.setSeedColor(savedSeedColor, isManual: false);
    }
  }
}

class _ColorPickerDialog extends StatefulWidget {
  final Color initialSeedColor;
  final Brightness brightness;

  const _ColorPickerDialog({
    required this.initialSeedColor,
    required this.brightness,
  });

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  static const int _barSteps = 120;
  static const List<Color> _presetSeeds = [
    Colors.red,
    Colors.deepOrange,
    Colors.orange,
    Colors.amber,
    Colors.green,
    Colors.teal,
    Colors.blue,
    Colors.indigo,
    Colors.purple,
    Colors.pink,
  ];

  late List<Color> _barColors;
  late List<Color> _presetM3Colors;
  late double _selectedHue;
  late Color _currentSeedColor;
  late Brightness _currentBrightness;

  @override
  void initState() {
    super.initState();
    _selectedHue = HSLColor.fromColor(widget.initialSeedColor).hue;
    _currentSeedColor = widget.initialSeedColor;
    _currentBrightness = widget.brightness;
    _precomputeColors();
  }

  void _precomputeColors() {
    _barColors = List<Color>.generate(_barSteps, (i) {
      final hue = (i / (_barSteps - 1)) * 360;
      final seed = HSLColor.fromAHSL(1.0, hue, 1.0, 0.5).toColor();
      return ColorScheme.fromSeed(
        seedColor: seed,
        brightness: _currentBrightness,
      ).primary;
    });
    _presetM3Colors = _presetSeeds.map((seed) {
      return ColorScheme.fromSeed(
        seedColor: seed,
        brightness: _currentBrightness,
      ).primary;
    }).toList();
  }

  void _selectHue(double hue) {
    hue = hue.clamp(0.0, 360.0);
    final seed = HSLColor.fromAHSL(1.0, hue, 1.0, 0.5).toColor();
    setState(() {
      _selectedHue = hue;
      _currentSeedColor = seed;
    });
    context.read<ThemeProvider>().setSeedColor(seed, isManual: false);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final themeProvider = context.watch<ThemeProvider>();
    final brightness =
        themeProvider.isDarkMode ? Brightness.dark : Brightness.light;
    if (brightness != _currentBrightness) {
      _currentBrightness = brightness;
      _precomputeColors();
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final isDark = themeProvider.isDarkMode;

    return AlertDialog(
      title: Row(
        children: [
          const Text('主题配色'),
          const Spacer(),
          Text(
            'H: ${_selectedHue.round()}°',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ColorBar(
              barColors: _barColors,
              selectedHue: _selectedHue,
              onHueChanged: _selectHue,
            ),
            const SizedBox(height: 24),
            Text(
              '预设颜色',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            _PresetColors(
              presetColors: _presetM3Colors,
              selectedHue: _selectedHue,
              isDark: isDark,
              onColorSelected: (seedColor) {
                final hue = HSLColor.fromColor(seedColor).hue;
                _selectHue(hue);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final settings = context.read<SettingsProvider>();
            if (settings.useDynamicColor) {
              settings.setUseDynamicColor(false);
            }
            context.read<ThemeProvider>().setSeedColor(
              _currentSeedColor,
              isManual: true,
            );
            Navigator.of(context).pop(true);
          },
          child: const Text('应用'),
        ),
      ],
    );
  }
}

class _ColorBar extends StatelessWidget {
  final List<Color> barColors;
  final double selectedHue;
  final ValueChanged<double> onHueChanged;

  const _ColorBar({
    required this.barColors,
    required this.selectedHue,
    required this.onHueChanged,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const padding = _ColorBarPainter.horizontalPadding;
        final barWidth = constraints.maxWidth - 2 * padding;
        return GestureDetector(
          onTapDown: (details) {
            final hue =
                ((details.localPosition.dx - padding) / barWidth).clamp(0.0, 1.0) * 360;
            onHueChanged(hue);
          },
          onHorizontalDragUpdate: (details) {
            final hue =
                ((details.localPosition.dx - padding) / barWidth).clamp(0.0, 1.0) * 360;
            onHueChanged(hue);
          },
          child: SizedBox(
            height: 44,
            width: constraints.maxWidth,
            child: CustomPaint(
              painter: _ColorBarPainter(
                barColors: barColors,
                selectedHue: selectedHue,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ColorBarPainter extends CustomPainter {
  final List<Color> barColors;
  final double selectedHue;

  _ColorBarPainter({
    required this.barColors,
    required this.selectedHue,
  });

  static const double horizontalPadding = 10.0;

  @override
  void paint(Canvas canvas, Size size) {
    final barHeight = size.height - 8;
    final barWidth = size.width - 2 * horizontalPadding;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(horizontalPadding, 0, barWidth, barHeight),
      const Radius.circular(8),
    );
    canvas.save();

    canvas.clipRRect(rrect);

    final paint = Paint()
      ..shader = LinearGradient(colors: barColors).createShader(rrect.outerRect);
    canvas.drawRRect(rrect, paint);

    canvas.restore();

    final indicatorX = horizontalPadding + (selectedHue / 360) * barWidth;
    final indicatorCenterY = barHeight / 2;
    const indicatorColor = Colors.white;
    const thumbRadius = 9.0;

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.15)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(
      Offset(indicatorX, indicatorCenterY + 1),
      thumbRadius,
      shadowPaint,
    );

    final outlinePaint = Paint()
      ..color = indicatorColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawCircle(
      Offset(indicatorX, indicatorCenterY),
      thumbRadius,
      outlinePaint,
    );

    final fillColor = barColors[
        (selectedHue / 360 * (barColors.length - 1)).round().clamp(0, barColors.length - 1)];
    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(indicatorX, indicatorCenterY),
      thumbRadius - 3,
      fillPaint,
    );
  }

  @override
  bool shouldRepaint(_ColorBarPainter oldDelegate) =>
      oldDelegate.selectedHue != selectedHue ||
      oldDelegate.barColors != barColors;
}

class _PresetColors extends StatelessWidget {
  final List<Color> presetColors;
  final double selectedHue;
  final bool isDark;
  final ValueChanged<Color> onColorSelected;

  const _PresetColors({
    required this.presetColors,
    required this.selectedHue,
    required this.isDark,
    required this.onColorSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: List.generate(_ColorPickerDialogState._presetSeeds.length, (index) {
        final seedColor = _ColorPickerDialogState._presetSeeds[index];
        final m3Primary = presetColors[index];
        final seedHue = HSLColor.fromColor(seedColor).hue;
        final diff = (seedHue - selectedHue) % 360;
        final isSelected = diff < 2 || diff > 358;

        return GestureDetector(
          onTap: () => onColorSelected(seedColor),
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: m3Primary,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected
                    ? (isDark ? Colors.white : Colors.black)
                    : Colors.transparent,
                width: 2.5,
              ),
              boxShadow: [
                if (isSelected)
                  BoxShadow(
                    color: m3Primary.withValues(alpha: 0.5),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
              ],
            ),
            child: isSelected
                ? Icon(
                    Icons.check,
                    size: 16,
                    color: isDark ? Colors.white : Colors.black,
                  )
                : null,
          ),
        );
      }),
    );
  }
}