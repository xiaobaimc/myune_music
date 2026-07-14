import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';
import 'package:provider/provider.dart';
import '../../page/playlist/playlist_content_notifier.dart';
import '../../widgets/audio_analysis/loudness_component.dart';
import '../../widgets/audio_analysis/levels_component.dart';
import '../../widgets/audio_analysis/sound_field_component.dart';
import '../../widgets/audio_analysis/spectrum_component.dart';
import '../../widgets/audio_analysis/spectrogram_component.dart';
import '../../widgets/single_line_lyrics.dart';

class AudioAnalysisPage extends StatefulWidget {
  const AudioAnalysisPage({super.key});

  @override
  State<AudioAnalysisPage> createState() => _AudioAnalysisPageState();
}

class _AudioAnalysisPageState extends State<AudioAnalysisPage> {
  late final Player _player;
  StreamSubscription<dynamic>? _playlistSub;

  @override
  void initState() {
    super.initState();
    _player = context.read<PlaylistContentNotifier>().mediaPlayer;
    // 延迟一帧执行，确保 widget 已完全挂载
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initAudioAnalysis();
    });
  }

  void _initAudioAnalysis() async {
    try {
      // 开启 ebur128 过滤器以获取 LoudnessMeter 数据
      await _enableEbur128();

      // 配置频谱生成器
      await _player.setSpectrum(
        const SpectrumSettings(
          fftSize: 2048,
          bandCount: 64,
          emitInterval: Duration(milliseconds: 33), // ~30 fps
          minDb: -90,
          maxDb: -20,
        ),
      );

      // 监听曲目变化，重置 ebur128 累积数据
      _playlistSub = _player.stream.playlist.listen((_) {
        _resetEbur128();
      });
    } catch (e) {
      //
    }
  }

  Future<void> _enableEbur128() async {
    await _player.updateAudioEffects(
      (e) => e.updateEbur128((m) => m.copyWith(enabled: true, metadata: true)),
    );
  }

  // 先关闭再重新开启，清空累积的 integrated/range 数据
  Future<void> _resetEbur128() async {
    try {
      await _player.updateAudioEffects(
        (e) => e.updateEbur128((m) => m.copyWith(enabled: false)),
      );
      await _enableEbur128();
    } catch (e) {
      //
    }
  }

  @override
  void dispose() {
    _playlistSub?.cancel();
    // 退出页面时关闭 ebur128 过滤器以节省性能
    _player.updateAudioEffects(
      (e) => e.updateEbur128((m) => m.copyWith(enabled: false)),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const SingleLineLyricView(
          maxLinesPerLyric: 2,
          textAlign: TextAlign.left,
          alignment: Alignment.topLeft,
        ),
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: Column(
        children: [
          const Divider(height: 1, thickness: 1),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth > 800) {
                  return const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        Expanded(
                          flex: 1,
                          child: Row(
                            children: [
                              Expanded(child: LoudnessComponent()),
                              SizedBox(width: 16),
                              Expanded(child: LevelsComponent()),
                              SizedBox(width: 16),
                              Expanded(child: SoundFieldComponent()),
                            ],
                          ),
                        ),
                        SizedBox(height: 16),
                        Expanded(
                          flex: 1,
                          child: Row(
                            children: [
                              Expanded(child: SpectrumComponent()),
                              SizedBox(width: 16),
                              Expanded(child: SpectrogramComponent()),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                } else {
                  return ListView(
                    padding: const EdgeInsets.all(16.0),
                    children: const [
                      SizedBox(height: 250, child: LoudnessComponent()),
                      SizedBox(height: 16),
                      SizedBox(height: 250, child: LevelsComponent()),
                      SizedBox(height: 16),
                      SizedBox(height: 300, child: SoundFieldComponent()),
                      SizedBox(height: 16),
                      SizedBox(height: 250, child: SpectrumComponent()),
                      SizedBox(height: 16),
                      SizedBox(height: 250, child: SpectrogramComponent()),
                    ],
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
