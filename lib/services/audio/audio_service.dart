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
//   Stream<PlayerError> get error => const Stream<PlayerError>.empty();

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
    try {
      await _player.stop();
    } on PlayerException {
      // 0.6 起 stop 在 mpv 拒绝时会抛异常，忽略即可
    }
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

  // 使用 [上一首占位, 当前, 下一首] 三段 playlist 播放
  // 如果是当前和下一首两段的话，播放列表中没有上一首
  // 会导致系统媒体控制中无法触发上一首的事件
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

    final tracks = [Media(currentPath), Media(currentPath)];
    if (nextPath != null) {
      tracks.add(Media(nextPath));
    }
    await _player.openAll(tracks, index: 1, play: true);
  }

  // 更新三段窗口中的下一首预取项（index 2）
  Future<void> replaceNext(String? nextPath) async {
    try {
      final playlist = _player.state.playlist;
      if (playlist.items.length > 2) {
        await _player.remove(2);
      }
      if (nextPath != null) {
        await _player.add(Media(nextPath));
      }
    } catch (e) {
      //
    }
  }

  // 在不打断当前播放的情况下，把playlist 重排成 [上一首, 当前, 下一首]
  // 用于播放中途开启无缝模式
  Future<void> rebuildGaplessWindow({
    required String currentPath,
    String? nextPath,
  }) async {
    try {
      final playlist = _player.state.playlist;
      if (playlist.index < 0 || playlist.items.isEmpty) return;

      await _removeOtherPlaylistItems();

      // 当前曲目此时位于 index 0：先追加占位副本和下一首
      // 再把副本移到最前面，当前曲目即落到 index 1
      await _player.add(Media(currentPath));
      if (nextPath != null) {
        await _player.add(Media(nextPath));
      }
      await _player.move(1, 0);
    } catch (e) {
      //
    }
  }

  // 关闭无缝模式时移除占位项和预取项，只留下当前曲目，
  // 避免 mpv 自动切换与应用的 completed 逻辑互相干扰
  Future<void> clearGaplessWindow() async {
    await _removeOtherPlaylistItems();
  }

  // 删除除当前曲目外的所有 playlist 项
  Future<void> _removeOtherPlaylistItems() async {
    try {
      final playlist = _player.state.playlist;
      final currentIndex = playlist.index;
      if (currentIndex < 0) return;

      for (var i = playlist.items.length - 1; i >= 0; i--) {
        if (i != currentIndex) {
          await _player.remove(i);
        }
      }
    } catch (e) {
      //
    }
  }

  Future<void> removeFirst() async {
    try {
      await _player.remove(0);
    } catch (e) {
      //
    }
  }

  Future<void> stop() async {
    try {
      await _player.stop();
    } on PlayerException {
      // 同上 忽略
    }
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

  bool _isEqualizerRaw(AudioEffect effect) {
    return effect is RawAudioEffect &&
        effect.entry.startsWith('lavfi=[') &&
        effect.entry.contains('equalizer=');
  }

  Future<void> applyEqualizer({
    required List<double> gains,
    required List<int> frequencies,
  }) async {
    if (_isEqualizerFlat(gains)) {
      await _player.updateAudioEffects(
        (effects) => [
          for (final effect in effects)
            if (!_isEqualizerRaw(effect)) effect,
        ],
      );
      return;
    }

    final filters = <String>[];
    for (var i = 0; i < frequencies.length; i++) {
      filters.add(
        'equalizer=f=${frequencies[i]}:t=q:w=1:g=${gains[i].toStringAsFixed(1)}',
      );
    }

    await _player.updateAudioEffects(
      (effects) => [
        RawAudioEffect('lavfi=[${filters.join(',')}]'),
        for (final effect in effects)
          if (!_isEqualizerRaw(effect)) effect,
      ],
    );
  }
}
