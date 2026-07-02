import 'dart:async';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

// class FakePlayerStream implements PlayerStream {
//   @override
//   Stream<Duration> get position => const Stream<Duration>.empty();

//   @override
//   Stream<bool> get playing => const Stream<bool>.empty();

//   @override
//   Stream<Duration> get duration => const Stream<Duration>.empty();

//   @override
//   Stream<bool> get completed => const Stream<bool>.empty();

//   @override
//   Stream<MediaSessionCommand> get mediaSessionCommands =>
//       const Stream<MediaSessionCommand>.empty();

//   @override
//   Stream<MpvPlayerError> get error => const Stream<MpvPlayerError>.empty();

//   @override
//   Stream<List<Device>> get audioDevices => Stream<List<Device>>.value(const []);

//   @override
//   Stream<Device> get audioDevice =>
//       Stream<Device>.value(const Device(name: 'auto', description: 'Auto'));

//   @override
//   dynamic noSuchMethod(Invocation invocation) {
//     return const Stream<dynamic>.empty();
//   }
// }

// class FakePlayer implements Player {
//   final _stream = FakePlayerStream();
//   final _state = const PlayerState();

//   @override
//   PlayerStream get stream => _stream;

//   @override
//   PlayerState get state => _state;

//   @override
//   dynamic noSuchMethod(Invocation invocation) {
//     if (invocation.isMethod) {
//       return Future<void>.value();
//     }
//     return null;
//   }
// }

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

  // 启用无缝播放模式：设置 Gapless.yes + 开启 prefetch
  Future<void> enableGapless() async {
    try {
      await _player.setGapless(Gapless.yes);
      await _player.setPrefetchPlaylist(true);
    } catch (e) {
      //
    }
  }

  // 关闭无缝播放模式：恢复默认 Gapless.weak + 关闭 prefetch
  Future<void> disableGapless() async {
    try {
      await _player.setGapless(Gapless.weak);
      await _player.setPrefetchPlaylist(false);
    } catch (e) {
      //
    }
  }

  // 使用 2-track playlist 播放，启用 mpv 无缝过渡
  Future<void> playSongGapless(
    String currentPath, {
    String? nextPath,
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

    final tracks = [Media(currentPath)];
    if (nextPath != null) {
      tracks.add(Media(nextPath));
    }
    await _player.openAll(tracks, play: true);
  }

  // 替换 mpv playlist 中的预备项（index 1）
  Future<void> replaceNext(String? nextPath) async {
    try {
      // 先移除旧的预备项（如果有）
      final playlist = _player.state.playlist;
      if (playlist.items.length > 1) {
        await _player.remove(1);
      }
      // 追加新的预备项
      if (nextPath != null) {
        await _player.add(Media(nextPath));
      }
    } catch (e) {
      //
    }
  }

  // 移除 mpv playlist 中已播完的首项，使当前播放回到 index 0
  Future<void> removeFirst() async {
    try {
      await _player.remove(0);
    } catch (e) {
      //
    }
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
