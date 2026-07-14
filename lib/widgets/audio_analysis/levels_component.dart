import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';
import 'package:provider/provider.dart';
import '../../page/playlist/playlist_content_notifier.dart';

class LevelsComponent extends StatefulWidget {
  const LevelsComponent({super.key});

  @override
  State<LevelsComponent> createState() => _LevelsComponentState();
}

class _LevelsComponentState extends State<LevelsComponent> {
  double _lPeak = 0;
  double _rPeak = 0;
  double _lRms = 0;
  double _rRms = 0;

  double _lPeakHold = 0;
  double _rPeakHold = 0;

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
              '电平',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: colorScheme.onSurface),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<PcmFrame>(
                stream: player.stream.pcm,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final frame = snapshot.data!;

                  _processPcm(frame);

                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildLevelMeter(context, 'L', _lRms, _lPeak, _lPeakHold),
                      _buildLevelMeter(context, 'R', _rRms, _rPeak, _rPeakHold),
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

      double lMax = 0;
      double rMax = 0;
      double lSumSq = 0;
      double rSumSq = 0;
      final int count = samples.length ~/ 2;

      for (int i = 0; i < samples.length - 1; i += 2) {
        final double l = samples[i].abs();
        final double r = samples[i + 1].abs();

        if (l > lMax) lMax = l;
        if (r > rMax) rMax = r;

        lSumSq += l * l;
        rSumSq += r * r;
      }

      _lPeak = lMax;
      _rPeak = rMax;

      _lRms = math.sqrt(lSumSq / count);
      _rRms = math.sqrt(rSumSq / count);

      if (_lPeak > _lPeakHold) {
        _lPeakHold = _lPeak;
      } else {
        _lPeakHold -= 0.01;
        if (_lPeakHold < _lPeak) _lPeakHold = _lPeak;
      }

      if (_rPeak > _rPeakHold) {
        _rPeakHold = _rPeak;
      } else {
        _rPeakHold -= 0.01;
        if (_rPeakHold < _rPeak) _rPeakHold = _rPeak;
      }
    } catch (e) {
      //
    }
  }

  Widget _buildLevelMeter(
    BuildContext context,
    String label,
    double rms,
    double peak,
    double peakHold,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final double rmsClamped = rms.clamp(0.0, 1.0);
    final double peakClamped = peak.clamp(0.0, 1.0);

    Gradient rmsGradient;
    if (rmsClamped <= 0.707) {
      rmsGradient = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [colorScheme.primary, colorScheme.primary],
      );
    } else {
      final double stop = 0.707 / rmsClamped;
      rmsGradient = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [
          colorScheme.primary,
          colorScheme.primary,
          colorScheme.error.withValues(alpha: 0.8),
          colorScheme.error.withValues(alpha: 0.8),
        ],
        stops: [0.0, stop, stop, 1.0],
      );
    }

    Gradient peakGradient;
    if (peakClamped <= 0.707) {
      peakGradient = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [
          colorScheme.primary.withValues(alpha: 0.4),
          colorScheme.primary.withValues(alpha: 0.4),
        ],
      );
    } else {
      final double stop = 0.707 / peakClamped;
      peakGradient = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [
          colorScheme.primary.withValues(alpha: 0.4),
          colorScheme.primary.withValues(alpha: 0.4),
          colorScheme.error.withValues(alpha: 0.4),
          colorScheme.error.withValues(alpha: 0.4),
        ],
        stops: [0.0, stop, stop, 1.0],
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(label, style: TextStyle(color: colorScheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            width: 40,
            decoration: BoxDecoration(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                // Peak Bar (Lighter, background)
                FractionallySizedBox(
                  heightFactor: peakClamped,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: peakGradient,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                // RMS Bar (Solid, foreground)
                FractionallySizedBox(
                  heightFactor: rmsClamped,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: rmsGradient,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                // Peak Hold Line
                FractionallySizedBox(
                  heightFactor: peakHold.clamp(0.0, 1.0),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Container(
                      height: 2,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
