import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';
import 'package:provider/provider.dart';

import '../page/playlist/playlist_content_notifier.dart';

class BalanceRateControl extends StatelessWidget {
  final Player player;
  final Color iconColor;
  final double size;

  const BalanceRateControl({
    required this.player,
    required this.iconColor,
    this.size = 24.0,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: '音效设置',
      iconSize: size,
      icon: Icon(Icons.tune, color: iconColor.withAlpha(179), size: size),
      onPressed: () => _showAudioControlDialog(context),
    );
  }

  void _showAudioControlDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
            child: Consumer<PlaylistContentNotifier>(
              builder: (context, notifier, child) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.graphic_eq, size: 24),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '音效设置',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: ExcludeSemantics(
                          child: SingleChildScrollView(
                            primary: false,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildSliderRow(
                                  icon: Icons.music_note,
                                  label: '音高',
                                  valueText: notifier.currentPitch
                                      .toStringAsFixed(2),
                                  value: notifier.currentPitch,
                                  min: 0.5,
                                  max: 1.5,
                                  divisions: 20,
                                  onChanged: (value) {
                                    notifier.setPitch(value);
                                  },
                                ),
                                const SizedBox(height: 10),
                                _buildSliderRow(
                                  icon: Icons.speed,
                                  label: '倍速',
                                  valueText:
                                      '${notifier.currentPlaybackRate.toStringAsFixed(2)}x',
                                  value: notifier.currentPlaybackRate,
                                  min: 0.5,
                                  max: 2.0,
                                  divisions: 30,
                                  onChanged: (value) {
                                    notifier.setPlaybackRate(value);
                                  },
                                ),
                                if (Platform.isWindows) ...[
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      _buildPrefix(Icons.headphones, '独占模式'),
                                      const Spacer(),
                                      SizedBox(
                                        width: 64,
                                        child: Align(
                                          alignment: Alignment.centerRight,
                                          child: Transform.translate(
                                            offset: const Offset(9, 0),
                                            child: Transform.scale(
                                              scale: 0.8,
                                              child: Switch(
                                                materialTapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                                value: notifier
                                                    .isExclusiveModeEnabled,
                                                onChanged: notifier
                                                    .toggleExclusiveMode,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                const Divider(height: 28),
                                Text(
                                  '均衡器预设',
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: PlaylistContentNotifier
                                      .equalizerPresets
                                      .skip(1)
                                      .map(
                                        (preset) => ChoiceChip(
                                          mouseCursor: SystemMouseCursors.click,
                                          label: Text(preset.name),
                                          selected:
                                              preset.name ==
                                              notifier.equalizerPresetName,
                                          onSelected: (_) {
                                            notifier.applyEqualizerPreset(
                                              preset,
                                            );
                                          },
                                        ),
                                      )
                                      .toList(),
                                ),
                                if (notifier.equalizerPresetName == '自定义') ...[
                                  const SizedBox(height: 8),
                                  const Align(
                                    alignment: Alignment.centerLeft,
                                    child: Chip(
                                      avatar: Icon(Icons.edit, size: 16),
                                      label: Text('自定义'),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 18),
                                SizedBox(
                                  height: 250,
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: List.generate(
                                      PlaylistContentNotifier
                                          .equalizerFrequencies
                                          .length,
                                      (index) {
                                        final frequency =
                                            PlaylistContentNotifier
                                                .equalizerFrequencies[index];
                                        final gain =
                                            notifier.equalizerGains[index];
                                        return _buildEqualizerBand(
                                          label: _formatFrequency(frequency),
                                          valueText: gain.toStringAsFixed(1),
                                          value: gain,
                                          onChanged: (value) {
                                            notifier.setEqualizerBand(
                                              index,
                                              value,
                                            );
                                          },
                                          onChangeEnd: (value) {
                                            notifier.commitEqualizerBand(
                                              index,
                                              value,
                                            );
                                          },
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Spacer(),
                          TextButton(
                            onPressed: () {
                              notifier.resetAudioControls();
                            },
                            child: const Text('重置'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('关闭'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildSliderRow({
    required IconData icon,
    required String label,
    required String valueText,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
    ValueChanged<double>? onChangeEnd,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 88,
          child: Row(
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ),
        SizedBox(
          width: 64,
          child: Text(
            valueText,
            textAlign: TextAlign.end,
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildEqualizerBand({
    required String label,
    required String valueText,
    required double value,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onChangeEnd,
  }) {
    return SizedBox(
      width: 48,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 24,
            child: Text(
              '$valueText dB',
              maxLines: 1,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11),
            ),
          ),
          Expanded(
            child: RotatedBox(
              quarterTurns: -1,
              child: Slider(
                value: value,
                min: -12.0,
                max: 12.0,
                divisions: 48,
                onChanged: onChanged,
                onChangeEnd: onChangeEnd,
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 32,
            child: Text(
              label,
              maxLines: 2,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrefix(IconData icon, String label) {
    return SizedBox(
      width: 122,
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 16),
          ),
        ],
      ),
    );
  }

  String _formatFrequency(int frequency) {
    if (frequency >= 1000) {
      final value = frequency / 1000;
      return '${value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1)} kHz';
    }
    return '$frequency Hz';
  }
}
