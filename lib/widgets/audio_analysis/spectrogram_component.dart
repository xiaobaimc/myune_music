import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';
import 'package:provider/provider.dart';
import '../../page/playlist/playlist_content_notifier.dart';

class SpectrogramComponent extends StatefulWidget {
  const SpectrogramComponent({super.key});

  @override
  State<SpectrogramComponent> createState() => _SpectrogramComponentState();
}

class _SpectrogramComponentState extends State<SpectrogramComponent> {
  final Queue<List<double>> _history = Queue<List<double>>();
  final int _maxHistory = 100;

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlaylistContentNotifier>().mediaPlayer;

    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '声谱瀑布图',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: colorScheme.onSurface),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<FftFrame>(
                stream: player.stream.fft,
                builder: (context, snapshot) {
                  if (snapshot.hasData) {
                    final frame = snapshot.data!;
                    final bands = frame.bands
                        .map((b) => b.clamp(0.0, 1.0))
                        .toList();
                    _history.add(bands);
                    if (_history.length > _maxHistory) {
                      _history.removeFirst();
                    }
                  }

                  return CustomPaint(
                    painter: SpectrogramPainter(
                      _history.toList(),
                      _maxHistory,
                      colorScheme,
                    ),
                    size: Size.infinite,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SpectrogramPainter extends CustomPainter {
  final List<List<double>> history;
  final int maxHistory;
  final ColorScheme colorScheme;

  SpectrogramPainter(this.history, this.maxHistory, this.colorScheme);

  @override
  void paint(Canvas canvas, Size size) {
    if (history.isEmpty) return;

    final int numBands = history.first.length;
    if (numBands == 0) return;

    final double cellWidth = size.width / maxHistory;
    final double cellHeight = size.height / numBands;

    final paint = Paint()..style = PaintingStyle.fill;

    for (int t = 0; t < history.length; t++) {
      final bands = history[t];
      final double x = t * cellWidth;

      for (int f = 0; f < bands.length; f++) {
        final double val = bands[f].clamp(0.0, 1.0);
        paint.color = _getColorForValue(val);

        // 底部频率较低
        final double y = size.height - ((f + 1) * cellHeight);

        canvas.drawRect(
          Rect.fromLTWH(x, y, cellWidth + 0.5, cellHeight + 0.5),
          paint,
        );
      }
    }
  }

  Color _getColorForValue(double v) {
    if (v < 0.25) {
      return Color.lerp(
        colorScheme.surface,
        colorScheme.secondary.withValues(alpha: 0.5),
        v / 0.25,
      )!;
    } else if (v < 0.6) {
      return Color.lerp(
        colorScheme.secondary.withValues(alpha: 0.5),
        colorScheme.primary,
        (v - 0.25) / 0.35,
      )!;
    } else if (v < 0.85) {
      return Color.lerp(
        colorScheme.primary,
        colorScheme.tertiary,
        (v - 0.6) / 0.25,
      )!;
    } else {
      return Color.lerp(
        colorScheme.tertiary,
        colorScheme.error,
        (v - 0.85) / 0.15,
      )!;
    }
  }

  @override
  bool shouldRepaint(covariant SpectrogramPainter oldDelegate) {
    return !identical(history, oldDelegate.history);
  }
}
