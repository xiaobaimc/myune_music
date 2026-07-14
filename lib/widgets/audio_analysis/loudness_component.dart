import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../page/playlist/playlist_content_notifier.dart';

class LoudnessComponent extends StatefulWidget {
  const LoudnessComponent({super.key});

  @override
  State<LoudnessComponent> createState() => _LoudnessComponentState();
}

class _LoudnessComponentState extends State<LoudnessComponent> {
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
              '响度 (EBU R128)',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: colorScheme.onSurface),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<dynamic>(
                stream: player.stream.loudnessMeter,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final data = snapshot.data!;

                  double? momentary;
                  double? shortTerm;
                  double? integrated;
                  double? range;

                  try {
                    momentary = data.momentary as double?;
                    shortTerm = data.shortTerm as double?;
                    integrated = data.integrated as double?;
                    range = data.range as double?;
                  } catch (e) {
                    //
                  }

                  return Column(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildValueRow(context, '瞬时响度', momentary, 'LUFS'),
                      _buildValueRow(context, '短期响度', shortTerm, 'LUFS'),
                      _buildValueRow(context, '总体响度', integrated, 'LUFS'),
                      _buildValueRow(context, '响度范围', range, 'LU'),
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

  Widget _buildValueRow(
    BuildContext context,
    String label,
    double? value,
    String unit,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant),
        ),
        RichText(
          text: TextSpan(
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: colorScheme.onSurface,
            ),
            children: [
              TextSpan(text: value != null ? value.toStringAsFixed(1) : '--'),
              TextSpan(
                text: ' $unit',
                style: TextStyle(
                  fontWeight: FontWeight.normal,
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
