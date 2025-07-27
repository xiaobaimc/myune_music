import 'dart:io';
import 'dart:typed_data';
import 'dart:math';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:path/path.dart' as p;
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import 'playlist_models.dart';
import 'playlist_manager.dart';
import 'sort_options.dart';
import '../../smtc_manager.dart';
import '../setting/settings_provider.dart';

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

  SmtcManager? get smtcManager => _smtcManager;

  final SettingsProvider _settingsProvider;

  Playlist? _playingPlaylist; // 真正正在播放的歌单
  int _playingSongIndex = -1; // 真正正在播放的歌曲在其歌单文件路径列表中的索引
  Playlist? get playingPlaylist => _playingPlaylist;
  int get playingSongIndex => _playingSongIndex;

  // 用于存储所有不重复歌曲的列表
  List<Song> _allSongs = [];
  List<Song> get allSongs => _allSongs;

  // 使用这个的注释通常会叫做虚拟歌单,但后续已经改为实际存储的,忽略虚拟歌单的注释
  final Playlist _allSongsVirtualPlaylist = Playlist(
    id: 'all-songs-virtual-id',
    name: '全部歌曲',
  );
  Playlist get allSongsVirtualPlaylist => _allSongsVirtualPlaylist;

  String _searchKeyword = '';
  String get searchKeyword => _searchKeyword;

  List<Song> _filteredSongs = [];
  List<Song> get filteredSongs => _filteredSongs;

  bool _isSearching = false; // 用于控制UI显示搜索框还是标题
  bool get isSearching => _isSearching;

  final StreamController<int> _lyricLineIndexController =
      StreamController<int>.broadcast();
  Stream<int> get lyricLineIndexStream => _lyricLineIndexController.stream;

  final StreamController<String> _errorStreamController =
      StreamController<String>.broadcast();
  Stream<String> get errorStream => _errorStreamController.stream;

  PlaylistContentNotifier(this._settingsProvider) {
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
    _lyricLineIndexController.close();
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
    await _updateAllSongsList();
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
      notifyListeners();
      return;
    }

    _isLoadingSongs = true;
    _currentPlaylistSongs = [];
    notifyListeners();

    final currentPlaylist = _playlists[_selectedIndex];
    final List<Song> songsWithMetadata = [];

    for (final filePath in currentPlaylist.songFilePaths) {
      final song = await _parseSongMetadata(filePath);
      songsWithMetadata.add(song);
    }

    _currentPlaylistSongs = songsWithMetadata;
    _isLoadingSongs = false;
    // if (_isSearching) {
    //   _updateFilteredSongs(searchInAllSongs: false); // 如果正在搜索，同步更新结果
    // }
    notifyListeners();
  }

  // 解析单个歌曲文件的元数据
  Future<Song> _parseSongMetadata(String filePath) async {
    String title = p.basenameWithoutExtension(filePath);
    String artist = '未知歌手';
    Uint8List? albumArt;

    final normalizedPath = Uri.file(
      filePath,
    ).toFilePath(windows: Platform.isWindows);
    final file = File(normalizedPath);

    if (!await file.exists()) {
      return Song(
        title: title,
        artist: '文件不存在 (解析失败)',
        filePath: filePath,
        albumArt: null,
      );
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
      artist = '未知歌手 (解析失败)';
      albumArt = null;
    }

    return Song(
      title: title,
      artist: artist,
      filePath: filePath,
      albumArt: albumArt,
    );
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
      await _updateAllSongsList();
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

  Future<bool> deletePlaylist(int index) async {
    // 边界条件检查
    if (index < 0 || index >= _playlists.length) {
      return false;
    }

    final playlistToDelete = _playlists[index];
    if (playlistToDelete.isDefault) {
      // 默认歌单不可删除，直接返回 false
      return false;
    }

    // 如果正在播放的歌单被删除，则停止播放
    if (_playingPlaylist?.id == playlistToDelete.id) {
      await stop();
    }

    // 基于旧列表创建一个全新的列表实例
    final newPlaylists = List<Playlist>.from(_playlists);
    newPlaylists.removeAt(index); // 在新列表上执行删除操作

    // 计算删除后，UI上应该选中的新索引
    int newSelectedIndex = _selectedIndex;
    if (_selectedIndex == index) {
      newSelectedIndex = -1; // 如果删除的是当前选中的，则取消选中
    } else if (_selectedIndex > index) {
      newSelectedIndex--; // 否则，如果索引在被删除项之后，则减一
    }

    // 将新的列表和新的索引赋值给状态变量
    _playlists = newPlaylists;
    _selectedIndex = newSelectedIndex;

    // 根据新的选中状态，更新右侧的歌曲列表显示
    if (_selectedIndex == -1) {
      _currentPlaylistSongs = [];
    }

    await _savePlaylists();
    await _updateAllSongsList();

    // 如果有新的选中项，则加载其歌曲；否则，手动通知UI刷新
    if (_selectedIndex != -1) {
      await _loadCurrentPlaylistSongs();
    } else {
      notifyListeners();
    }

    return true; // 表示删除成功
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
    if (_selectedIndex < 0 ||
        index < 0 ||
        index >= _currentPlaylistSongs.length) {
      return;
    }

    // 更新播放上下文
    _playingPlaylist = _playlists[_selectedIndex];
    _playingSongIndex = index;

    await _startPlaybackNow();
  }

  Future<void> _startPlaybackNow() async {
    if (_playingPlaylist == null ||
        _playingSongIndex < 0 ||
        _playingSongIndex >= _playingPlaylist!.songFilePaths.length) {
      return;
    }

    final songFilePath = _playingPlaylist!.songFilePaths[_playingSongIndex];
    final songToPlay = await _parseSongMetadata(songFilePath);

    // 检查文件是否存在
    if (songToPlay.artist.contains('文件不存在')) {
      _errorStreamController.add('文件不存在${p.basename(songFilePath)}');
      await playNext();
      return;
    }

    _currentSong = songToPlay;

    try {
      // 尝试执行播放操作
      await _audioPlayer.stop();
      _currentLyrics = [];
      _currentLyricLineIndex = -1;
      await _audioPlayer.setSource(DeviceFileSource(songFilePath));
      _loadLyricsForSong(songFilePath);

      // 在 resume 之前更新SMTC元数据
      await _smtcManager?.updateMetadata(
        title: songToPlay.title,
        artist: songToPlay.artist,
        albumArt: songToPlay.albumArt,
      );
      // await dumpCover(songToPlay.albumArt!);
      await _smtcManager?.updateState(true); // 播放状态

      await _audioPlayer.resume(); // 最后执行播放

      notifyListeners();
    } catch (e) {
      // 捕获所有播放相关的异常
      _errorStreamController.add('无法播放歌曲: ${songToPlay.title}, 错误: $e');

      await playNext();
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
  void _generateShuffledIndices({int? count}) {
    // 如果调用时没有传入 count (值为 null)，则使用旧的逻辑，以 _currentPlaylistSongs 的长度为准。
    // 如果传入了 count，则使用传入的 count。
    final int listSize = count ?? _currentPlaylistSongs.length;

    _shuffledIndices = List.generate(listSize, (i) => i);
    _shuffledIndices.shuffle(_random);
  }

  // 根据播放模式播放下一首
  Future<void> _playNextLogic() async {
    // 只依赖 _playingPlaylist
    if (_playingPlaylist == null || _playingPlaylist!.songFilePaths.isEmpty) {
      await stop();
      return;
    }

    int nextIndex;
    final songCount = _playingPlaylist!.songFilePaths.length;
    final currentIndex = _playingSongIndex;

    if (_playMode == PlayMode.shuffle) {
      _generateShuffledIndices(count: songCount);
      int currentShuffledPos = _shuffledIndices.indexOf(currentIndex);
      if (currentShuffledPos == -1 ||
          currentShuffledPos == _shuffledIndices.length - 1) {
        _generateShuffledIndices(count: songCount); // 重新生成随机列表或从头开始
        currentShuffledPos = -1; // 从新的随机列表的第一个开始
      }
      nextIndex =
          _shuffledIndices[(currentShuffledPos + 1) % _shuffledIndices.length];
    } else if (_playMode == PlayMode.repeatOne) {
      nextIndex = currentIndex;
    } else {
      // 顺序播放
      nextIndex = (currentIndex + 1) % songCount;
    }

    _playingSongIndex = nextIndex; // 更新播放索引
    await _startPlaybackNow();
  }

  Future<void> playNext() async {
    await _playNextLogic();
  }

  // 播放上一首
  Future<void> playPrevious() async {
    if (_playingPlaylist == null || _playingPlaylist!.songFilePaths.isEmpty) {
      return;
    }

    int prevIndex;
    final songCount = _playingPlaylist!.songFilePaths.length;
    final currentIndex = _playingSongIndex;

    // 根据不同的播放模式计算上一首的索引
    if (_playMode == PlayMode.shuffle) {
      // 随机模式下，在随机索引列表中找到上一个位置
      if (_shuffledIndices.length != songCount) {
        _generateShuffledIndices(count: songCount);
      }

      int currentShuffledPos = _shuffledIndices.indexOf(currentIndex);
      if (currentShuffledPos == -1 || currentShuffledPos == 0) {
        // 如果当前歌曲不在随机列表中，或已经是第一首，则跳到随机列表的最后一首
        currentShuffledPos = _shuffledIndices.length;
      }
      prevIndex =
          _shuffledIndices[(currentShuffledPos - 1) % _shuffledIndices.length];
    } else if (_playMode == PlayMode.repeatOne) {
      // 单曲循环模式下，上一首还是当前这首歌
      prevIndex = currentIndex;
    } else {
      // 顺序播放
      // `+ songCount` 是为了防止 `currentIndex` 为 0 时出现负数
      prevIndex = (currentIndex - 1 + songCount) % songCount;
    }

    // 更新播放索引
    _playingSongIndex = prevIndex;
    await _startPlaybackNow();
  }

  // 将歌曲移动到顶部
  Future<void> moveSongToTop(int index) async {
    if (_selectedIndex == -1 ||
        index < 0 ||
        index >= _currentPlaylistSongs.length ||
        _playlists[_selectedIndex].songFilePaths.isEmpty) {
      return;
    }

    final newSongList = List<Song>.from(_currentPlaylistSongs);
    final songToMove = newSongList.removeAt(index);
    newSongList.insert(0, songToMove);
    _currentPlaylistSongs = newSongList; // 指向新列表

    final songPath = _playlists[_selectedIndex].songFilePaths.removeAt(index);
    _playlists[_selectedIndex].songFilePaths.insert(0, songPath);

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
  Future<void> reorderSong(int oldIndex, int newIndex) async {
    if (_selectedIndex < 0) return;

    // 边界检查
    if (oldIndex < 0 || oldIndex >= _currentPlaylistSongs.length) return;

    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    // 确保 newIndex 也在有效范围内
    if (newIndex < 0 || newIndex >= _currentPlaylistSongs.length) return;

    final song = _currentPlaylistSongs.removeAt(oldIndex);
    _currentPlaylistSongs.insert(newIndex, song);

    // 确保数据同步
    final currentPlaylist = _playlists[_selectedIndex];
    final movedPath = currentPlaylist.songFilePaths.removeAt(oldIndex);
    currentPlaylist.songFilePaths.insert(newIndex, movedPath);

    await _savePlaylists();

    notifyListeners();
  }

  Future<void> _loadLyricsForSong(String songFilePath) async {
    _currentLyrics = []; // 清空之前的歌词
    _currentLyricLineIndex = -1; // 重置歌词行索引
    _lyricLineIndexController.add(-1);
    notifyListeners();

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

    // 如果没有内嵌歌词，继续查找同目录.lrc
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
        notifyListeners();
        return;
      } catch (e) {
        // debugPrint('读取.lrc文件失败：$e');
      }
    }

    // 如果需要从网络获取歌词，改为后台加载，先返回
    if (_settingsProvider.enableOnlineLyrics && currentSong != null) {
      _currentLyrics = []; // 清空歌词
      notifyListeners();

      // 后台异步加载网络歌词
      _loadOnlineLyrics(currentSong!.title);
    } else {
      _currentLyrics = []; // 确保在不执行网络请求时清空歌词
      notifyListeners();
    }
  }

  // 后台异步加载网络歌词
  Future<void> _loadOnlineLyrics(String songTitle) async {
    try {
      final cleanTitle = songTitle.trim().replaceAll(
        RegExp(
          r'[!"#$%&'
          '()*+,./:;<=>?@[\\]^_`{|}~-]',
        ),
        '',
      );

      // 检查 artist 是否为默认值，如果是则设置为空字符串
      final rawArtist = _currentSong?.artist ?? '';
      final artist = (rawArtist == '未知歌手' || rawArtist == '未知歌手 (解析失败)')
          ? ''
          : rawArtist.replaceAll(
              RegExp(
                r'[!"#$%&'
                '()*+,./:;<=>?@[\\]^_`{|}~-]',
              ),
              '',
            );

      // 对清理后的标题和歌手名称进行 URL 编码
      final encodedTitle = Uri.encodeComponent(cleanTitle);
      final encodedArtist = Uri.encodeComponent(artist);

      // 获取用户自定义的 API 基础地址
      final String apiBaseUrl = _settingsProvider.onlineLyricsApi.trim();

      // 如果用户没有设置API地址，或者API地址为空，则不进行网络请求
      if (apiBaseUrl.isEmpty) {
        return;
      }

      // 拼接完整的 API URL
      final finalApiUrl =
          '$apiBaseUrl/api/v1/lyrics/single?album=$encodedTitle&artist=$encodedArtist';
      final apiUri = Uri.parse(finalApiUrl);

      // debugPrint('请求歌词API: $apiUri');

      final response = await http.get(apiUri); // 使用 http.get 发送 GET 请求

      if (response.statusCode == 200) {
        final apiLyrics = utf8.decode(response.bodyBytes).trim(); // 直接获取响应体并解码

        if (!apiLyrics.contains('Lyrics not found.') && apiLyrics.isNotEmpty) {
          _currentLyrics = _parseLrcContent(apiLyrics.split('\n'));
        } else {
          _currentLyrics = [];
        }
      } else {
        // 处理非200状态码，例如 404, 500 等
        _currentLyrics = [];
      }
    } catch (e) {
      _currentLyrics = [];
      // debugPrint('网络歌词加载失败：$e');
    }
    notifyListeners();
  }

  Future<void> removeSongFromCurrentPlaylist(int index) async {
    if (_selectedIndex < 0 || _selectedIndex >= _playlists.length) {
      return;
    }
    if (index < 0 || index >= _currentPlaylistSongs.length) {
      return;
    }

    final currentPlaylist = _playlists[_selectedIndex];
    final songToRemove = _currentPlaylistSongs[index];

    // 从UI列表和数据模型列表中都移除
    currentPlaylist.songFilePaths.remove(songToRemove.filePath);

    // 如果删除的是正在播放的歌曲
    if (_currentSong?.filePath == songToRemove.filePath &&
        _playingPlaylist?.id == currentPlaylist.id) {
      await stop(); // 直接停止
    }
    await _loadCurrentPlaylistSongs();

    await _updateAllSongsList();
  }

  Future<void> removeSongFromAllPlaylists(String filePath) async {
    final bool wasPlaying = _currentSong?.filePath == filePath;

    // 遍历所有歌单，移除包含该路径的项
    for (final playlist in _playlists) {
      playlist.songFilePaths.remove(filePath);
    }

    // 如果删除的是正在播放的歌曲，停止播放
    if (wasPlaying) {
      await stop();
    }

    await _savePlaylists();

    await _updateAllSongsList();
    await _loadCurrentPlaylistSongs();

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
        _lyricLineIndexController.add(-1); // 广播空歌词状态
      }
      return;
    }

    // 使用二分查找查找当前歌词行
    int newIndex = -1;
    int left = 0;
    int right = _currentLyrics.length - 1;

    while (left <= right) {
      final int mid = (left + right) ~/ 2;
      if (currentPosition >= _currentLyrics[mid].timestamp) {
        if (mid + 1 >= _currentLyrics.length ||
            currentPosition < _currentLyrics[mid + 1].timestamp) {
          newIndex = mid;
          break;
        }
        left = mid + 1;
      } else {
        right = mid - 1;
      }
    }

    if (newIndex != _currentLyricLineIndex) {
      _currentLyricLineIndex = newIndex;
      _lyricLineIndexController.add(newIndex); // 广播新索引
    }
  }

  Future<SongDetails?> getCurrentSongDetails() async {
    if (_currentSong == null) {
      // _errorStreamController.add('没有当前播放的歌曲');
      return null;
    }

    final filePath = _currentSong!.filePath;
    final normalizedPath = Uri.file(
      filePath,
    ).toFilePath(windows: Platform.isWindows);
    final file = File(normalizedPath);

    if (!await file.exists()) {
      // _errorStreamController.add('歌曲文件不存在：${p.basename(filePath)}');
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

  Future<void> _updateAllSongsList() async {
    // （已完成） 新的去重逻辑
    // （目前通过歌曲路径进行去重）
    // 先通过歌曲路径进行第1次去重 在去重的结果通过歌手名及歌曲名进行第2次去重
    // 虽然可以通过歌曲路径来标识唯一的歌曲 但是不排除两个不同的路径存放同一首歌，此时就不会被去重
    // （直觉告诉我同时去重可能会发生意料之外的事情）

    // 从所有歌单中获取当前所有可用的、不重复的歌曲路径集合
    final allAvailablePaths = <String>{};
    for (final playlist in _playlists) {
      allAvailablePaths.addAll(playlist.songFilePaths);
    }

    // 加载之前保存的“全部歌曲”顺序
    final List<String> savedOrder = await _playlistManager.loadAllSongsOrder();

    // 从已保存的顺序中，删除那些在任何歌单中都已不存在的歌曲
    savedOrder.removeWhere((path) => !allAvailablePaths.contains(path));

    // 找出所有歌单中新增的、但尚未出现在排序列表中的歌曲
    final existingPathsInOrder = savedOrder.toSet();
    final newPaths = allAvailablePaths.where(
      (path) => !existingPathsInOrder.contains(path),
    );

    // 将所有新发现的歌曲追加到排序列表的末尾
    savedOrder.addAll(newPaths);

    // 将这个经过合并后的、最新的顺序列表存回磁盘
    await _playlistManager.saveAllSongsOrder(savedOrder);

    // 解析元数据
    final List<Song> songsWithMetadata = [];
    for (final path in savedOrder) {
      final song = await _parseSongMetadata(path);
      songsWithMetadata.add(song);
    }
    _allSongs = songsWithMetadata;

    // 二次去重：通过歌手+歌曲名
    final seen = <String>{};
    final dedupedSongs = <Song>[];

    for (final song in _allSongs) {
      final artist = song.artist.trim().toLowerCase();
      final title = song.title.trim().toLowerCase();
      final key = '$artist|$title';

      if (!seen.contains(key)) {
        seen.add(key);
        dedupedSongs.add(song);
      }
    }

    _allSongs = dedupedSongs;

    // 同步更新虚拟播放列表的路径，以便播放逻辑正常工作
    _allSongsVirtualPlaylist.songFilePaths = _allSongs
        .map((s) => s.filePath)
        .toList();
    // if (_isSearching) {
    //   _updateFilteredSongs(searchInAllSongs: true); // 如果正在搜索，同步更新结果
    // }
  }

  Future<void> reorderAllSongs(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }

    // 在内存中对歌曲列表进行排序
    final song = _allSongs.removeAt(oldIndex);
    _allSongs.insert(newIndex, song);

    // 提取出新的文件路径顺序
    final newPathOrder = _allSongs.map((s) => s.filePath).toList();

    // 将新的顺序保存到磁盘
    await _playlistManager.saveAllSongsOrder(newPathOrder);

    // 更新虚拟播放列表以匹配新顺序
    _allSongsVirtualPlaylist.songFilePaths = newPathOrder;

    // 如果正在播放的歌曲被移动，同步更新其索引以防播放错乱
    if (_playingPlaylist?.id == _allSongsVirtualPlaylist.id) {
      if (_playingSongIndex == oldIndex) {
        _playingSongIndex = newIndex;
      } else if (_playingSongIndex > oldIndex &&
          _playingSongIndex <= newIndex) {
        _playingSongIndex--;
      } else if (_playingSongIndex < oldIndex &&
          _playingSongIndex >= newIndex) {
        _playingSongIndex++;
      }
    }

    notifyListeners();
  }

  // 从全部歌曲列表播放歌曲
  Future<void> playSongFromAllSongs(int index) async {
    if (index < 0 || index >= _allSongs.length) {
      return;
    }

    // 设置播放上下文为虚拟歌单
    _playingPlaylist = _allSongsVirtualPlaylist;
    _playingSongIndex = index;

    await _startPlaybackNow();
  }

  Future<List<String>> _sortFilePaths({
    required List<String> paths,
    required SortCriterion criterion,
    required bool descending,
  }) async {
    // 如果是按标题或歌手，需要歌曲的元数据
    if (criterion == SortCriterion.title || criterion == SortCriterion.artist) {
      // 创建一个包含路径和元数据的临时列表
      final sortableList = <Map<String, dynamic>>[];
      for (final path in paths) {
        final metadata = await _parseSongMetadata(path);
        sortableList.add({'path': path, 'metadata': metadata});
      }

      // 对这个临时列表进行排序
      sortableList.sort((a, b) {
        final songA = a['metadata'] as Song;
        final songB = b['metadata'] as Song;
        final valueA = criterion == SortCriterion.title
            ? songA.title.toLowerCase()
            : songA.artist.toLowerCase();
        final valueB = criterion == SortCriterion.title
            ? songB.title.toLowerCase()
            : songB.artist.toLowerCase();
        return descending ? valueB.compareTo(valueA) : valueA.compareTo(valueB);
      });

      // 提取出排好序的路径并返回
      return sortableList.map((item) => item['path'] as String).toList();
    }

    // 如果是按修改日期
    if (criterion == SortCriterion.dateModified) {
      // 创建一个包含路径和修改日期的临时列表
      final sortableList = <Map<String, dynamic>>[];
      for (final path in paths) {
        try {
          final file = File(path);
          final lastModified = await file.lastModified();
          sortableList.add({'path': path, 'date': lastModified});
        } catch (e) {
          // 如果文件不存在或无法访问，给一个很早的日期，让它排在后面
          sortableList.add({'path': path, 'date': DateTime(1970)});
        }
      }

      // 对列表进行排序
      sortableList.sort((a, b) {
        final dateA = a['date'] as DateTime;
        final dateB = b['date'] as DateTime;
        return descending ? dateB.compareTo(dateA) : dateA.compareTo(dateB);
      });

      // 提取路径并返回
      return sortableList.map((item) => item['path'] as String).toList();
    }

    return paths; // 如果出现意外情况，返回原列表
  }

  // 排序当前选中的歌单
  Future<void> sortCurrentPlaylist({
    required SortCriterion criterion,
    required bool descending,
  }) async {
    if (_selectedIndex < 0) return;

    final currentPlaylist = _playlists[_selectedIndex];
    final originalPaths = List<String>.from(currentPlaylist.songFilePaths);

    // 调用排序方法
    final sortedPaths = await _sortFilePaths(
      paths: originalPaths,
      criterion: criterion,
      descending: descending,
    );

    // 更新数据模型
    currentPlaylist.songFilePaths = sortedPaths;

    await _savePlaylists();

    await _loadCurrentPlaylistSongs();

    notifyListeners();
  }

  // 用于排序全部歌曲列表
  Future<void> sortAllSongs({
    required SortCriterion criterion,
    required bool descending,
  }) async {
    final originalPaths = _allSongs.map((s) => s.filePath).toList();

    // 调用核心排序方法
    final sortedPaths = await _sortFilePaths(
      paths: originalPaths,
      criterion: criterion,
      descending: descending,
    );

    // 持久化保存
    await _playlistManager.saveAllSongsOrder(sortedPaths);

    // 重新加载全部歌曲列表以匹配新顺序
    final sortedSongList = <Song>[];
    for (final path in sortedPaths) {
      sortedSongList.add(await _parseSongMetadata(path));
    }
    _allSongs = sortedSongList;
    _allSongsVirtualPlaylist.songFilePaths = sortedPaths;

    notifyListeners();
  }

  void startSearch() {
    if (_isSearching) return;
    _isSearching = true;
    _searchKeyword = ''; // 每次开始搜索时清空关键词
    _updateFilteredSongs(); // 更新一次，显示原始列表
    notifyListeners();
  }

  void stopSearch() {
    if (!_isSearching) return;
    _isSearching = false;
    _searchKeyword = '';
    _filteredSongs = []; // 清空过滤结果
    notifyListeners();
  }

  void search(String keyword, {required bool searchInAllSongs}) {
    _searchKeyword = keyword.toLowerCase();
    _updateFilteredSongs(searchInAllSongs: searchInAllSongs);
    notifyListeners();
  }

  void _updateFilteredSongs({bool searchInAllSongs = false}) {
    List<Song> sourceList;

    // 决定数据源是全部歌曲还是当前歌单
    if (searchInAllSongs) {
      sourceList = _allSongs;
    } else {
      sourceList = _currentPlaylistSongs;
    }

    if (_searchKeyword.isEmpty) {
      // 如果关键词为空，则显示完整的源列表
      _filteredSongs = List.from(sourceList);
    } else {
      // 否则进行过滤
      _filteredSongs = sourceList.where((song) {
        final titleMatch = song.title.toLowerCase().contains(_searchKeyword);
        final artistMatch = song.artist.toLowerCase().contains(_searchKeyword);
        return titleMatch || artistMatch;
      }).toList();
    }
  }
}
