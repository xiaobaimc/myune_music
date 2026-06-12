import 'dart:async';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

class AudioService {
  final Player _player;

  Player get player => _player;

  AudioService()
    : _player = Player(
        // configuration: const PlayerConfiguration(autoPlay: false),
        // Wait, default autoPlay is false anyway.
        configuration: const PlayerConfiguration(),
      ) {
    init();
  }

  Future<void> init() async {
    try {
      await _player.setAudioClientName('MyuneMusic');
      // Disable auto subtitles if possible
      await _player.setRawProperty('sub-auto', 'no');
    } catch (e) {
      //
    }
  }

  Future<void> dispose() async {
    await _player.stop();
    await _player.dispose();
  }

  Future<void> playSong(
    String filePath, {
    required double pitch,
    required double rate,
    required List<double> eqGains,
    required List<int> eqFrequencies,
    bool exclusiveMode = false,
  }) async {
    try {
      await _player.setAudioExclusive(exclusiveMode);
    } catch (e) {
      //
    }

    await setPitch(pitch);
    await setRate(rate);
    await applyEqualizer(gains: eqGains, frequencies: eqFrequencies);

    await _player.open(Media(filePath), play: true);
  }

  Future<void> stop() async {
    await _player.stop();
  }

  Future<void> pause() async {
    await _player.pause();
  }

  Future<void> play() async {
    await _player.play();
  }

  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  Future<void> setVolume(double volume) async {
    await _player.setVolume(volume);
  }

  Future<void> setPitch(double pitch) async {
    await _player.setPitch(pitch);
  }

  Future<void> setRate(double rate) async {
    await _player.setRate(rate);
  }

  bool _isEqualizerFlat(List<double> gains) {
    return gains.every((gain) => gain.abs() < 0.05);
  }

  Future<void> applyEqualizer({
    required List<double> gains,
    required List<int> frequencies,
  }) async {
    if (_isEqualizerFlat(gains)) {
      await _player.setAudioEffects(const AudioEffects());
      return;
    }

    final filters = <String>[];
    for (var i = 0; i < frequencies.length; i++) {
      filters.add(
        'equalizer=f=${frequencies[i]}:t=q:w=1:g=${gains[i].toStringAsFixed(1)}',
      );
    }

    await _player.updateAudioEffects(
      (e) => e.copyWith(custom: ['lavfi=[${filters.join(',')}]']),
    );
  }
}
