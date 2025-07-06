import 'dart:io';
import 'dart:typed_data';
import 'dart:math';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:path/path.dart' as p;
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'playlist_models.dart';
import 'playlist_manager.dart';
import '../../smtc_manager.dart';

enum PlayMode { sequence, shuffle, repeatOne }

class PlaylistContentNotifier extends ChangeNotifier {
  final PlaylistManager _playlistManager = PlaylistManager();
  List<Playlist> _playlists = [];
  int _selectedIndex = -1;
  List<Song> _currentPlaylistSongs = [];
  bool _isLoadingSongs = false;

  final AudioPlayer _audioPlayer = AudioPlayer();

  List<Playlist> get playlists => _playlists;
  int get selectedIndex => _selectedIndex;
  List<Song> get currentPlaylistSongs => _currentPlaylistSongs;
  bool get isLoadingSongs => _isLoadingSongs;

  PlayMode _playMode = PlayMode.sequence;
  PlayMode get playMode => _playMode;

  Song? _currentSong;
  Song? get currentSong => _currentSong;

  List<LyricLine> _currentLyrics = [];
  List<LyricLine> get currentLyrics => _currentLyrics;

  int _currentLyricLineIndex = -1;
  int get currentLyricLineIndex => _currentLyricLineIndex;

  PlayerState _playerState = PlayerState.stopped;
  PlayerState get playerState => _playerState;

  int _currentSongIndex = -1; // 手动维护当前播放歌曲的索引
  int get currentSongIndex => _currentSongIndex;

  List<int> _shuffledIndices = [];
  final Random _random = Random();

  AudioPlayer get audioPlayer => _audioPlayer;

  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;

  Duration get currentPosition => _currentPosition;
  Duration get totalDuration => _totalDuration;

  static const _playModeKey = 'play_mode';

  SmtcManager? _smtcManager;

  double _currentBalance = 0.0;
  double _currentPlaybackRate = 1.0;

  double get currentBalance => _currentBalance;
  double get currentPlaybackRate => _currentPlaybackRate;

  final StreamController<String> _errorStreamController =
      StreamController<String>.broadcast();
  Stream<String> get errorStream => _errorStreamController.stream;

  PlaylistContentNotifier() {
    _setupAudioPlayerListeners(); // 设置 audioplayers 的监听器
    _loadPlaylists();
    loadPlayMode();
    _audioPlayer.setBalance(_currentBalance);
    _audioPlayer.setPlaybackRate(_currentPlaybackRate);
    _smtcManager = SmtcManager(
      onPlay: play,
      onPause: pause,
      onNext: playNext,
      onPrevious: playPrevious,
    );
  }

  @override
  void dispose() {
    _errorStreamController.close();
    _audioPlayer.dispose(); // 释放播放器资源
    _cleanupSmtc();
    super.dispose();
  }

  void _setupAudioPlayerListeners() {
    _audioPlayer.onPlayerStateChanged.listen((state) {
      _playerState = state; // 更新内部状态
      notifyListeners();
    });

    _audioPlayer.onPlayerComplete.listen((event) async {
      _playerState = PlayerState.completed; // 更新内部状态
      notifyListeners();
      await _playNextLogic();
    });

    _audioPlayer.onPositionChanged.listen((position) {
      _currentPosition = position; // 更新当前位置
      updateLyricLine(position);
      _smtcManager?.updateTimeline(
        position: position.inMilliseconds,
        duration: _totalDuration.inMilliseconds,
      );
      // notifyListeners();
    });

    _audioPlayer.onDurationChanged.listen((duration) {
      _totalDuration = duration; // 更新总时长
      _smtcManager?.updateTimeline(
        position: _currentPosition.inMilliseconds,
        duration: duration.inMilliseconds,
      );
      // notifyListeners();
    });
  }

  Future<void> _cleanupSmtc() async {
    await _smtcManager?.close();
  }

  Future<void> _loadPlaylists() async {
    final List<Playlist> loadedPlaylists = await _playlistManager
        .loadPlaylists();
    _playlists = loadedPlaylists;
    _selectedIndex = _playlists.isNotEmpty ? 0 : -1;
    notifyListeners();

    if (_selectedIndex != -1) {
      _loadCurrentPlaylistSongs();
    }
  }

  Future<void> _savePlaylists() async {
    await _playlistManager.savePlaylists(_playlists);
  }

  void setSelectedIndex(int index) {
    if (_selectedIndex == index) return;
    _selectedIndex = index;
    notifyListeners();
    _loadCurrentPlaylistSongs(); // 选中索引变化时加载歌曲到 UI 和播放器
  }

  Future<void> _loadCurrentPlaylistSongs() async {
    if (_selectedIndex == -1 || _playlists.isEmpty) {
      _currentPlaylistSongs = [];
      _isLoadingSongs = false;
      await _audioPlayer.stop();
      _currentSong = null;
      _currentSongIndex = -1;
      _currentLyrics = [];
      _currentLyricLineIndex = -1;
      _currentPosition = Duration.zero;
      _totalDuration = Duration.zero;
      await _smtcManager?.updateState(false);
      notifyListeners();
      return;
    }

    _isLoadingSongs = true;
    _currentPlaylistSongs = []; // 每次加载前清空，防止旧数据残留
    notifyListeners();

    final currentPlaylist = _playlists[_selectedIndex];
    final List<Song> songsWithMetadata = [];

    for (final filePath in currentPlaylist.songFilePaths) {
      await Future.delayed(Duration.zero);
      String title = p.basenameWithoutExtension(filePath);
      String artist = '未知歌手';
      Uint8List? albumArt;

      final normalizedPath = Uri.file(
        filePath,
      ).toFilePath(windows: Platform.isWindows);
      final file = File(normalizedPath);

      if (!await file.exists()) {
        songsWithMetadata.add(
          Song(
            title: title,
            artist: '文件不存在 (解析失败)',
            filePath: filePath,
            albumArt: null,
          ),
        );
        continue;
      }

      try {
        final metadata = readMetadata(file, getImage: true);

        if (metadata.title != null && metadata.title!.isNotEmpty) {
          title = metadata.title!;
        }

        if (metadata.artist != null && metadata.artist!.isNotEmpty) {
          artist = metadata.artist!;
        }

        albumArt = metadata.pictures.isNotEmpty
            ? metadata.pictures.first.bytes
            : null;
      } catch (e) {
        title = p.basenameWithoutExtension(filePath);
        artist = '未知歌手 (解析失败)';
        albumArt = null;
      }

      final song = Song(
        title: title,
        artist: artist,
        filePath: filePath,
        albumArt: albumArt,
      );
      songsWithMetadata.add(song);
    }

    _currentPlaylistSongs = songsWithMetadata;
    _isLoadingSongs = false;
    notifyListeners();
  }

  Future<bool> pickAndAddSongs() async {
    if (_selectedIndex == -1) {
      throw Exception('请先选择一个歌单');
    }

    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'wav', 'aac', 'flac', 'ogg', 'm4a'],
      allowMultiple: true,
    );

    if (result == null) {
      return false; // 用户取消
    }

    final currentPlaylist = _playlists[_selectedIndex];
    final List<String> newSongPaths = [];

    for (final platformFile in result.files) {
      if (platformFile.path != null) {
        final pathToAdd = p.normalize(platformFile.path!);
        if (!currentPlaylist.songFilePaths.contains(pathToAdd)) {
          newSongPaths.add(pathToAdd);
        }
      }
    }

    if (newSongPaths.isNotEmpty) {
      currentPlaylist.songFilePaths.addAll(newSongPaths);
      await _savePlaylists();
      await _loadCurrentPlaylistSongs();
      return true; // 真的有添加
    }

    return false; // 虽然打开了文件选择器，但没有添加任何新歌曲
  }

  bool addPlaylist(String name) {
    if (_playlists.any((playlist) => playlist.name == name)) {
      return false;
    }

    _playlists.add(Playlist(name: name));
    _selectedIndex = _playlists.length - 1;
    _savePlaylists();
    notifyListeners();
    _loadCurrentPlaylistSongs();
    return true;
  }

  bool deletePlaylist(int index) {
    if (_playlists[index].isDefault) {
      return false;
    }

    // 如果删除的是当前选中的歌单，则重置选中索引并停止播放
    if (_selectedIndex == index) {
      _selectedIndex = -1;
      _audioPlayer.stop();
      _currentSong = null;
      _currentSongIndex = -1;
      _currentLyrics = [];
      _currentLyricLineIndex = -1;
    } else if (_selectedIndex > index) {
      _selectedIndex--;
    }
    _playlists.removeAt(index);
    _savePlaylists();
    notifyListeners();
    _loadCurrentPlaylistSongs(); // 删除歌单后重新加载当前选中歌单的歌曲
    return true;
  }

  bool editPlaylistName(int index, String newName) {
    if (newName.isEmpty) return false;
    if (_playlists.any((p) => p.name == newName && p != _playlists[index])) {
      return false;
    }

    _playlists[index].name = newName;
    _savePlaylists();
    notifyListeners();
    return true;
  }

  Future<void> play() async {
    if (_playerState == PlayerState.stopped ||
        _playerState == PlayerState.completed) {
      await _audioPlayer.setSource(DeviceFileSource(_currentSong!.filePath));
      await _audioPlayer.resume(); // 从头播放或从上次停止的位置开始
    } else if (_playerState == PlayerState.paused) {
      await _audioPlayer.resume(); // 从暂停处恢复
    } else {}
    await _smtcManager?.updateState(true);
    notifyListeners();
  }

  Future<void> pause() async {
    await _audioPlayer.pause();
    await _smtcManager?.updateState(false);
    notifyListeners();
  }

  Future<void> stop() async {
    await _audioPlayer.stop();
    _currentSong = null;
    _currentSongIndex = -1;
    _currentLyrics = [];
    _currentLyricLineIndex = -1;
    _currentPosition = Duration.zero;
    _totalDuration = Duration.zero;
    await _smtcManager?.updateState(false);
    await _smtcManager?.updateTimeline(position: 0, duration: 0);
  }

  Future<void> setBalance(double balance) async {
    if (balance < -1.0 || balance > 1.0) return;
    _currentBalance = balance;
    await _audioPlayer.setBalance(balance);
    notifyListeners(); // 通知 UI 更新
  }

  Future<void> setPlaybackRate(double rate) async {
    if (rate < 0.5 || rate > 2.0) return;
    _currentPlaybackRate = rate;
    await _audioPlayer.setPlaybackRate(rate);
    notifyListeners(); // 通知 UI 更新
  }

  // 播放指定索引的歌曲
  Future<void> playSongAtIndex(int index) async {
    if (index < 0 || index >= _currentPlaylistSongs.length) {
      return;
    }

    final songToPlay = _currentPlaylistSongs[index];

    try {
      await _audioPlayer.stop(); // 停止当前播放（如果有）
      _currentLyrics = [];
      _currentLyricLineIndex = -1;
      _currentPosition = Duration.zero;
      _totalDuration = Duration.zero;
      await _loadLyricsForSong(songToPlay.filePath);
      await _audioPlayer.setSource(
        DeviceFileSource(songToPlay.filePath),
      ); // 设置新音源
      await _audioPlayer.resume(); // 播放新音源
      _currentSongIndex = index;
      _currentSong = songToPlay;
      await _audioPlayer.setBalance(_currentBalance);
      await _audioPlayer.setPlaybackRate(_currentPlaybackRate);
      await _smtcManager?.updateMetadata(
        title: songToPlay.title,
        artist: songToPlay.artist,
        albumArt: songToPlay.albumArt,
      );
      // await dumpCover(songToPlay.albumArt!);
      await _smtcManager?.updateState(true); // 播放状态
      await _smtcManager?.updateTimeline(
        position: 0, // 新歌曲从0开始
        duration: _totalDuration.inMilliseconds,
      );
      notifyListeners();
    } catch (e) {
      _errorStreamController.add('无法播放歌曲: ${songToPlay.title}, 错误: $e');
    }
  }

  Future<void> _savePlayMode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_playModeKey, _playMode.index);
  }

  Future<void> loadPlayMode() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getInt(_playModeKey);
    if (index != null && index >= 0 && index < PlayMode.values.length) {
      _playMode = PlayMode.values[index];
      notifyListeners(); // 确保 UI 更新
    }
  }

  // 切换播放模式
  void togglePlayMode() {
    switch (_playMode) {
      case PlayMode.sequence:
        _playMode = PlayMode.shuffle;
        _generateShuffledIndices();
        break;
      case PlayMode.shuffle:
        _playMode = PlayMode.repeatOne;
        break;
      case PlayMode.repeatOne:
        _playMode = PlayMode.sequence;
        break;
    }
    _savePlayMode(); // 保存当前模式
    notifyListeners();
  }

  // 生成随机播放索引列表
  void _generateShuffledIndices() {
    _shuffledIndices = List.generate(_currentPlaylistSongs.length, (i) => i);
    _shuffledIndices.shuffle(_random);
  }

  // 根据播放模式播放下一首
  Future<void> _playNextLogic() async {
    if (_currentPlaylistSongs.isEmpty) {
      await _audioPlayer.stop();
      _currentLyrics = [];
      _currentLyricLineIndex = -1;
      _currentPosition = Duration.zero;
      _totalDuration = Duration.zero;
      notifyListeners();
      return;
    }

    int nextIndex;
    if (_playMode == PlayMode.shuffle) {
      int currentShuffledPos = _shuffledIndices.indexOf(_currentSongIndex);
      if (currentShuffledPos == -1 ||
          currentShuffledPos == _shuffledIndices.length - 1) {
        _generateShuffledIndices(); // 重新生成随机列表或从头开始
        currentShuffledPos = -1; // 从新的随机列表的第一个开始
      }
      nextIndex =
          _shuffledIndices[(currentShuffledPos + 1) % _shuffledIndices.length];
    } else if (_playMode == PlayMode.repeatOne) {
      nextIndex = _currentSongIndex;
    } else {
      nextIndex = (_currentSongIndex + 1) % _currentPlaylistSongs.length;
    }

    await playSongAtIndex(nextIndex);
  }

  Future<void> playNext() async {
    await _playNextLogic();
  }

  // 播放上一首
  Future<void> playPrevious() async {
    if (_currentPlaylistSongs.isEmpty) {
      return;
    }

    int prevIndex;
    if (_playMode == PlayMode.shuffle) {
      int currentShuffledPos = _shuffledIndices.indexOf(_currentSongIndex);
      if (currentShuffledPos == -1 || currentShuffledPos == 0) {
        _generateShuffledIndices();
        currentShuffledPos = _shuffledIndices.length;
      }
      prevIndex =
          _shuffledIndices[(currentShuffledPos - 1 + _shuffledIndices.length) %
              _shuffledIndices.length];
    } else if (_playMode == PlayMode.repeatOne) {
      prevIndex = _currentSongIndex;
    } else {
      prevIndex =
          (_currentSongIndex - 1 + _currentPlaylistSongs.length) %
          _currentPlaylistSongs.length;
    }
    await playSongAtIndex(prevIndex);
  }

  // 将歌曲移动到顶部
  Future<void> moveSongToTop(int index) async {
    if (_selectedIndex == -1 ||
        index < 0 ||
        index >= _currentPlaylistSongs.length ||
        _playlists[_selectedIndex].songFilePaths.isEmpty) {
      return;
    }

    final songPath = _playlists[_selectedIndex].songFilePaths.removeAt(index);
    _playlists[_selectedIndex].songFilePaths.insert(0, songPath);

    final song = _currentPlaylistSongs.removeAt(index);
    _currentPlaylistSongs.insert(0, song);

    // 如果当前播放的歌曲被移动，更新 currentSongIndex
    if (_currentSongIndex == index) {
      _currentSongIndex = 0;
    } else if (_currentSongIndex > index) {
      _currentSongIndex--;
    }

    await _playlistManager.savePlaylists(_playlists);
    await _smtcManager?.updateState(false);
    notifyListeners();
  }

  // 排序歌曲
  void reorderSong(int oldIndex, int newIndex) {
    if (_selectedIndex == -1 || _currentPlaylistSongs.isEmpty) {
      _errorStreamController.add('无法重新排序：没有选中歌单或歌单为空');
      return;
    }

    if (newIndex > oldIndex) {
      newIndex -= 1;
    }

    try {
      final song = _currentPlaylistSongs.removeAt(oldIndex);
      _currentPlaylistSongs.insert(newIndex, song);

      final currentPlaylist = _playlists[_selectedIndex];
      final filePath = currentPlaylist.songFilePaths.removeAt(oldIndex);
      currentPlaylist.songFilePaths.insert(newIndex, filePath);

      // 调整当前播放歌曲的索引
      if (_currentSongIndex == oldIndex) {
        _currentSongIndex = newIndex;
      } else if (_currentSongIndex > oldIndex &&
          _currentSongIndex <= newIndex) {
        _currentSongIndex--;
      } else if (_currentSongIndex < oldIndex &&
          _currentSongIndex >= newIndex) {
        _currentSongIndex++;
      }

      // 重新生成随机索引
      if (_playMode == PlayMode.shuffle) {
        _generateShuffledIndices();
      }

      _savePlaylists();
      notifyListeners();
    } catch (e) {
      _errorStreamController.add('重新排序失败：$e');
      notifyListeners();
    }
  }

  Future<void> _loadLyricsForSong(String songFilePath) async {
    _currentLyrics = []; // 清空之前的歌词
    _currentLyricLineIndex = -1; // 重置歌词行索引

    try {
      final normalizedPath = Uri.file(
        songFilePath,
      ).toFilePath(windows: Platform.isWindows);
      final file = File(normalizedPath);

      if (!await file.exists()) {
        _errorStreamController.add('歌曲文件不存在：${p.basename(songFilePath)}');
        notifyListeners();
        return;
      }

      final metadata = readMetadata(file, getImage: false);

      if (metadata.lyrics != null && metadata.lyrics!.isNotEmpty) {
        _currentLyrics = _parseLrcContent([metadata.lyrics!]);

        notifyListeners();
        return;
      }
    } catch (e) {
      // _errorStreamController.add('加载歌词失败：${p.basename(songFilePath)}');
      // 未能读取到歌词时不提示错误
    }

    final songDirectory = p.dirname(songFilePath);
    final songFileNameWithoutExtension = p.basenameWithoutExtension(
      songFilePath,
    );
    final lrcFilePath = p.join(
      songDirectory,
      '$songFileNameWithoutExtension.lrc',
    );

    final lrcFile = File(lrcFilePath);

    if (await lrcFile.exists()) {
      try {
        final lines = await lrcFile.readAsLines();
        _currentLyrics = _parseLrcContent(lines);
      } catch (e) {
        _currentLyrics = [];
      }
    } else {
      _currentLyrics = []; // 没有找到歌词文件则清空歌词
    }
    notifyListeners();
  }

  Future<void> removeSongAtIndex(int index) async {
    if (_selectedIndex == -1 || _selectedIndex >= _playlists.length) {
      return;
    }

    if (index < 0 || index >= _currentPlaylistSongs.length) {
      return;
    }

    // 获取当前选中的歌单
    final currentPlaylist = _playlists[_selectedIndex];
    final songToRemove = _currentPlaylistSongs[index];

    currentPlaylist.songFilePaths.remove(songToRemove.filePath);
    _currentPlaylistSongs.removeAt(index);

    if (_currentSongIndex != -1) {
      if (_currentSongIndex == index) {
        // 如果删除的是当前正在播放的歌曲
        await _audioPlayer.stop();
        _currentSong = null;
        _currentSongIndex = -1;
        _currentLyrics = [];
        _currentLyricLineIndex = -1;
        _currentPosition = Duration.zero;
        _totalDuration = Duration.zero;
      } else if (_currentSongIndex > index) {
        // 如果删除的歌曲在当前播放歌曲之前，需要调整当前播放索引
        _currentSongIndex--;
      }
    }

    // 如果播放模式是随机播放
    if (_playMode == PlayMode.shuffle) {
      _generateShuffledIndices();
    }

    await _savePlaylists();

    notifyListeners();
  }

  // 解析歌词
  List<LyricLine> _parseLrcContent(List<String> lines) {
    final Map<Duration, List<String>> groupedLyrics = {};
    final RegExp timeStampRegExp = RegExp(
      r'\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)',
    );

    for (final line in lines) {
      final matches = timeStampRegExp.allMatches(line);

      // 跳过无时间戳的行
      if (matches.isEmpty) continue;

      for (final match in matches) {
        try {
          final int minutes = int.parse(match.group(1)!);
          final int seconds = int.parse(match.group(2)!);
          final int milliseconds = int.parse(match.group(3)!.padRight(3, '0'));
          final Duration timestamp = Duration(
            minutes: minutes,
            seconds: seconds,
            milliseconds: milliseconds,
          );

          // 获取歌词内容：时间戳之后的内容
          final String text = match.group(4)!.trim();

          // 兼容逐字歌词
          final String cleanedText = text.replaceAll(
            RegExp(r'<\d{2}:\d{2}\.\d{2,3}>'),
            '',
          );

          if (cleanedText.isEmpty) continue;
          groupedLyrics.putIfAbsent(timestamp, () => []).add(cleanedText);
          if (text.isEmpty) continue;
        } catch (e) {
          _errorStreamController.add('歌词解析错误: $line - $e');
        }
      }
    }

    final List<LyricLine> parsedLyrics =
        groupedLyrics.entries
            .map((entry) => LyricLine(timestamp: entry.key, texts: entry.value))
            .toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return parsedLyrics;
  }

  void updateLyricLine(Duration currentPosition) {
    if (_currentLyrics.isEmpty) {
      if (_currentLyricLineIndex != -1) {
        _currentLyricLineIndex = -1;
        notifyListeners();
      }
      return;
    }

    int newIndex = -1;
    for (int i = 0; i < _currentLyrics.length; i++) {
      if (currentPosition >= _currentLyrics[i].timestamp) {
        if (i + 1 < _currentLyrics.length &&
            currentPosition < _currentLyrics[i + 1].timestamp) {
          newIndex = i;
          break;
        } else if (i + 1 == _currentLyrics.length) {
          newIndex = i;
          break;
        }
      }
    }

    if (newIndex != _currentLyricLineIndex) {
      _currentLyricLineIndex = newIndex;
      notifyListeners();
    }
  }

  Future<SongDetails?> getCurrentSongDetails() async {
    if (_currentSong == null) {
      _errorStreamController.add('没有当前播放的歌曲');
      return null;
    }

    final filePath = _currentSong!.filePath;
    final normalizedPath = Uri.file(
      filePath,
    ).toFilePath(windows: Platform.isWindows);
    final file = File(normalizedPath);

    if (!await file.exists()) {
      _errorStreamController.add('歌曲文件不存在：${p.basename(filePath)}');
      return SongDetails(
        title: '文件不存在',
        artist: '未知',
        album: '未知',
        duration: Duration.zero,
        albumArt: null,
        filePath: filePath,
      );
    }

    try {
      final metadata = readMetadata(file, getImage: true);

      Uint8List? albumArtBytes;
      if (metadata.pictures.isNotEmpty) {
        albumArtBytes = metadata.pictures.first.bytes;
      }

      return SongDetails(
        title: metadata.title ?? p.basenameWithoutExtension(filePath),
        artist: metadata.artist ?? '未知歌手',
        album: metadata.album ?? '未知专辑',
        duration: metadata.duration ?? Duration.zero,
        albumArt: albumArtBytes,
        bitrate: metadata.bitrate,
        sampleRate: metadata.sampleRate,
        filePath: filePath,
      );
    } catch (e) {
      _errorStreamController.add('读取歌曲详情失败：${p.basename(filePath)} - $e');
      return SongDetails(
        title: (filePath), // 至少提供文件名作为标题
        artist: '未知歌手 (解析失败)',
        album: '未知专辑',
        duration: Duration.zero,
        albumArt: null,
        filePath: filePath,
      );
    }
  }
}
