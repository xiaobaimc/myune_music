import 'package:flutter/material.dart';
// import 'dart:math';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';
import 'package:provider/provider.dart';
import '../../page/playlist/playlist_content_notifier.dart';

class SpectrumComponent extends StatefulWidget {
  const SpectrumComponent({super.key});

  @override
  State<SpectrumComponent> createState() => _SpectrumComponentState();
}

class _SpectrumComponentState extends State<SpectrumComponent> {
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
              '频谱可视化 (2D FFT)',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: colorScheme.onSurface),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<FftFrame>(
                stream: player.stream.fft,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final frame = snapshot.data!;
                  final bands = frame.bands
                      .map((b) => b.clamp(0.0, 1.0))
                      .toList();

                  // print("take: ${frame.bands.take(10)}");
                  // print("reduce: ${frame.bands.reduce(max)}");

                  return CustomPaint(
                    painter: SpectrumPainter(bands, colorScheme.primary),
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

class SpectrumPainter extends CustomPainter {
  final List<double> bands;
  final Color primaryColor;

  SpectrumPainter(this.bands, this.primaryColor);

  @override
  void paint(Canvas canvas, Size size) {
    if (bands.isEmpty) return;

    final path = Path();
    final fillPath = Path();

    final double dx = size.width / (bands.length - 1);

    final double startY =
        size.height - (bands[0].clamp(0.0, 1.0) * size.height);
    path.moveTo(0, startY);
    fillPath.moveTo(0, size.height);
    fillPath.lineTo(0, startY);

    for (int i = 1; i < bands.length; i++) {
      final double x = i * dx;
      final double y = size.height - (bands[i].clamp(0.0, 1.0) * size.height);

      final double prevX = (i - 1) * dx;
      final double prevY =
          size.height - (bands[i - 1].clamp(0.0, 1.0) * size.height);
      final double controlX = (prevX + x) / 2;

      path.quadraticBezierTo(controlX, prevY, (prevX + x) / 2, (prevY + y) / 2);
      fillPath.quadraticBezierTo(
        controlX,
        prevY,
        (prevX + x) / 2,
        (prevY + y) / 2,
      );
    }

    final double endY =
        size.height - (bands.last.clamp(0.0, 1.0) * size.height);
    path.lineTo(size.width, endY);
    fillPath.lineTo(size.width, endY);

    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [primaryColor.withValues(alpha: 0.35), Colors.transparent],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    final strokePaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(covariant SpectrumPainter oldDelegate) {
    return !identical(bands, oldDelegate.bands);
  }
}
