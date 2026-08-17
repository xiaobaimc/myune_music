import 'dart:io';

import 'package:file_picker/file_picker.dart';
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
                                  context,
                                  icon: Icons.music_note,
                                  label: '音高',
                                  valueText: notifier.currentPitch
                                      .toStringAsFixed(2),
                                  value: notifier.currentPitch,
                                  min: 0.5,
                                  max: 1.5,
                                  divisions: 20,
                                  defaultValue:
                                      PlaylistContentNotifier.defaultPitch,
                                  onChanged: (value) {
                                    notifier.setPitch(value);
                                  },
                                  onReset: () {
                                    notifier.setPitch(
                                      PlaylistContentNotifier.defaultPitch,
                                    );
                                  },
                                  resetTooltip: '恢复默认音高',
                                ),
                                const SizedBox(height: 10),
                                _buildSliderRow(
                                  context,
                                  icon: Icons.speed,
                                  label: '倍速',
                                  valueText:
                                      '${notifier.currentPlaybackRate.toStringAsFixed(2)}x',
                                  value: notifier.currentPlaybackRate,
                                  min: 0.5,
                                  max: 2.0,
                                  divisions: 30,
                                  defaultValue: PlaylistContentNotifier
                                      .defaultPlaybackRate,
                                  onChanged: (value) {
                                    notifier.setPlaybackRate(value);
                                  },
                                  onReset: () {
                                    notifier.setPlaybackRate(
                                      PlaylistContentNotifier
                                          .defaultPlaybackRate,
                                    );
                                  },
                                  resetTooltip: '恢复默认倍速',
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
                                ..._buildEffectSections(context, notifier),
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

  Widget _buildSliderRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String valueText,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
    required double defaultValue,
    required VoidCallback onReset,
    required String resetTooltip,
    ValueChanged<double>? onChangeEnd,
  }) {
    // 判断当前值是否偏离默认值，以决定是否启用"重置"按钮
    // 使用浮点数差值绝对值与 (1e-9) 比较，而非直接使用 !=
    final canReset = (value - defaultValue).abs() > 1e-9;

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
          width: 88,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: IconButton(
                  tooltip: canReset ? resetTooltip : null,
                  icon: Icon(
                    Icons.restart_alt,
                    size: 18,
                    color: canReset ? null : Theme.of(context).disabledColor,
                  ),
                  iconSize: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 18,
                  ),
                  onPressed: canReset ? onReset : null,
                ),
              ),
              SizedBox(
                width: 62,
                child: Text(
                  valueText,
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
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

  List<Widget> _buildEffectSections(
    BuildContext context,
    PlaylistContentNotifier notifier,
  ) {
    const sections = <(String, IconData, List<(String, String, String)>)>[
      (
        '空间与立体声扩张',
        Icons.headphones,
        [
          ('crossfeed', '交叉混音', '将少量左、右声道信号互相混入，减轻耳机左右声道过度分离的感觉，使听感更接近自然的聆听方式'),
          ('earwax', 'Bauer 空间模拟', '基于 Bauer 立体声扩展算法调整声道间的关系，改变耳机播放时的空间感与声场表现'),
          ('widerStereo', '立体声扩展', '调整左右声道之间的相关性，增强立体声的宽度感，但可能使声音变得不自然'),
          ('haas', 'Haas 空间效果', '利用左右声道之间的微小时间差制造更宽的空间感，模拟类似 Haas 效应的立体声效果'),
          ('vocalBoost', '人声增强', '增强左右声道中的中央信号，使位于声场中央的人声等声音更加突出'),
          ('vocalRemover', '人声削弱', '削弱左右声道中的中央信号，可降低居中的人声等内容，同时可能影响其他位于中央的乐器'),
        ],
      ),
      (
        '动态与夜间平稳',
        Icons.dark_mode,
        [
          ('acompressor', '动态范围压缩', '缩小音频的动态范围，降低较大的音量变化，让较安静和较响亮的部分更加接近'),
          ('softClip', '柔和削波', '在信号接近或超过峰值范围时进行平滑处理，减少硬削波产生的刺耳失真'),
          ('deNoise', '背景降噪', '降低低电平的持续性背景噪声，适合处理录音中的底噪，但也可能影响较弱的声音细节'),
        ],
      ),
      (
        '音调与频响修饰',
        Icons.equalizer,
        [
          ('virtualbass', '低音增强', '增强低频及相关谐波成分，使低频听起来更加明显和厚实'),
          ('subboost', '极重低音', '提升低频范围的增益，增强低频能量\n可能造成失真或占用较多动态余量'),
          ('crystalizer', '高频增强', '通过增强高频细节与谐波成分，使声音听起来更加明亮和清晰'),
          ('tilt', '倾斜均衡', '按照倾斜的方式整体调整频响，使高频与低频之间形成不同的能量平衡，从而改变整体音色'),
        ],
      ),
      (
        '复古与创意音效',
        Icons.auto_awesome,
        [
          ('vinyl', '黑胶/收音机', '模拟黑胶唱片/FM广播曲线'),
          ('exciter', '谐波激励', '在高频段引入微量的二次谐波失真，使声音更具空气感'),
          ('echo', '回声与空间延迟', '添加延迟与回声'),
        ],
      ),
      (
        '修复与人声优化',
        Icons.auto_fix_high,
        [
          ('deesser', '人声齿音消除', '针对人声中的高频齿音进行动态衰减，降低 S、Sh 等音节可能产生的刺耳感'),
          ('declip', '数字破音修复', '尝试根据削波信号的特征重建被截断的波形，减轻数字削波造成的失真'),
          ('arnndn', '人声降噪', '使用 RNN 神经网络模型降低背景噪声\n需导入 .rnnn 文件'),
        ],
      ),
    ];

    return [
      for (final (title, icon, effects) in sections) ...[
        const SizedBox(height: 4),
        Row(
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 6),
            Text(title, style: Theme.of(context).textTheme.titleSmall),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (id, label, tooltip) in effects)
              Tooltip(
                message: tooltip,
                child: FilterChip(
                  label: Text(label),
                  selected: notifier.isEffectEnabled(id),
                  onSelected: (enabled) async {
                    if (id == 'arnndn' && enabled) {
                      bool needsPicker = false;
                      if (notifier.arnndnModelPath == null) {
                        needsPicker = true;
                      } else if (!File(
                        notifier.arnndnModelPath!,
                      ).existsSync()) {
                        notifier.showNotification('RNN降噪模型文件已失效或被移动，请重新选择');
                        await notifier.setArnndnModelPath(null);
                        needsPicker = true;
                      }

                      if (needsPicker) {
                        final result = await FilePicker.platform.pickFiles(
                          type: FileType.custom,
                          allowedExtensions: ['rnnn'],
                          dialogTitle: '选择 RNN 降噪模型文件',
                        );
                        if (result == null ||
                            result.files.single.path == null) {
                          return;
                        }
                        await notifier.setArnndnModelPath(
                          result.files.single.path!,
                        );
                      }
                    }
                    await notifier.toggleEffect(id, enabled);
                  },
                ),
              ),
          ],
        ),
      ],
    ];
  }

  String _formatFrequency(int frequency) {
    if (frequency >= 1000) {
      final value = frequency / 1000;
      return '${value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1)} kHz';
    }
    return '$frequency Hz';
  }
}
