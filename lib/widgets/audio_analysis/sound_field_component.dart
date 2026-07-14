import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';
import 'package:provider/provider.dart';
import '../../page/playlist/playlist_content_notifier.dart';

class SoundFieldComponent extends StatefulWidget {
  const SoundFieldComponent({super.key});

  @override
  State<SoundFieldComponent> createState() => _SoundFieldComponentState();
}

class _SoundFieldComponentState extends State<SoundFieldComponent> {
  double _correlation = 0;
  List<Offset> _points = [];

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
              '声场 / 相位',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: colorScheme.onSurface),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<PcmFrame>(
                stream: player.stream.pcm,
                builder: (context, snapshot) {
                  if (snapshot.hasData) {
                    _processPcm(snapshot.data!);
                  }

                  return Column(
                    children: [
                      Expanded(
                        child: CustomPaint(
                          painter: LissajousPainter(
                            _points,
                            colorScheme.secondary,
                          ),
                          size: Size.infinite,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildCorrelationMeter(context),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _processPcm(PcmFrame frame) {
    try {
      final samples = frame.samples;
      if (samples.isEmpty) return;

      double sumLR = 0;
      double sumL2 = 0;
      double sumR2 = 0;

      final List<Offset> newPoints = [];
      // To save performance, we might skip some samples or just use a subset
      final int step = math.max(1, samples.length ~/ 1000);

      for (int i = 0; i < samples.length - 1; i += 2) {
        final double l = samples[i];
        final double r = samples[i + 1];

        sumLR += l * r;
        sumL2 += l * l;
        sumR2 += r * r;

        if ((i ~/ 2) % step == 0) {
          // 旋转45度以匹配标准李萨如图形音频显示
          newPoints.add(Offset(l, r));
        }
      }

      final double denom = math.sqrt(sumL2 * sumR2);
      if (denom > 0) {
        _correlation = sumLR / denom;
      } else {
        _correlation = 0;
      }

      _points = newPoints;
    } catch (e) {
      //
    }
  }

  Widget _buildCorrelationMeter(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '-1',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              '0',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              '+1',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          height: 12,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(6),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final double width = constraints.maxWidth;
              final double center = width / 2;
              final double barWidth = (_correlation.abs() * center);

              return Stack(
                children: [
                  Center(
                    child: Container(
                      width: 2,
                      color: colorScheme.outlineVariant,
                    ),
                  ),
                  Positioned(
                    left: _correlation < 0 ? center - barWidth : center,
                    child: Container(
                      width: barWidth,
                      height: 12,
                      decoration: BoxDecoration(
                        color: _correlation < 0
                            ? colorScheme.error.withValues(alpha: 0.8)
                            : colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '相关度: ',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            SizedBox(
              width: 40,
              child: Text(
                _correlation.toStringAsFixed(2),
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.left,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class LissajousPainter extends CustomPainter {
  final List<Offset> points;
  final Color traceColor;

  LissajousPainter(this.points, this.traceColor);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final paint = Paint()
      ..color = traceColor.withValues(alpha: 0.3)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final scaleX = size.width / 2;
    final scaleY = size.height / 2;

    // 预先变换 drawPoints
    final transformed = List<Offset>.generate(points.length, (i) {
      final l = points[i].dx;
      final r = points[i].dy;
      // 中间 (L+R) 向上旋转，侧面 (L-R) 向右旋转
      final m = (l + r) * 0.707;
      final s = (l - r) * 0.707;
      return Offset(centerX + s * scaleX, centerY - m * scaleY);
    });

    canvas.drawPoints(PointMode.points, transformed, paint);
  }

  @override
  bool shouldRepaint(covariant LissajousPainter oldDelegate) {
    return !identical(points, oldDelegate.points);
  }
}
