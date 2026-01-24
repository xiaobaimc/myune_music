import 'dart:io';
import 'dart:typed_data';
import 'dart:math';
import 'dart:async';
import 'dart:convert';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:media_kit/media_kit.dart' hide Playlist;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:colorgram/colorgram.dart';
import 'package:pinyin/pinyin.dart';

import 'playlist_models.dart';
import 'playlist_manager.dart';
import '../../media_service/smtc_manager.dart';
import '../setting/settings_provider.dart';
import '../../theme/theme_provider.dart';
import '../statistics_page/playback_tracker.dart';
import '../../src/rust/api/audio_info.dart';

enum SortCriterion { title, artist, dateModified, random }

enum PlayMode { sequence, shuffle, repeatOne }

enum DetailViewContext { playlist, allSongs, artist, album }

class PlaylistContentNotifier extends ChangeNotifier {
  // --- 播放列表相关 ---
  final PlaylistManager _playlistManager = PlaylistManager();
  final SettingsProvider _settingsProvider;
  final ThemeProvider _themeProvider;

  bool _allSongsLoaded = false; // 表示全部歌曲是否已加载完成
  bool get allSongsLoaded => _allSongsLoaded;

  List<Playlist> _playlists = []; // 所有歌单列表
  List<Playlist> get playlists => _playlists;
  int _selectedIndex = -1; // 当前选中的歌单索引
  int get selectedIndex => _selectedIndex;
  Playlist? _playingPlaylist; // 当前正在播放的歌单
  Playlist? get playingPlaylist => _playingPlaylist;
  int _playingSongIndex = -1; // 当前播放的歌曲在歌单路径列表中的索引

  final Playlist _allSongsVirtualPlaylist = Playlist(
    // 实际存储的“全部歌曲”歌单
    id: 'all-songs-virtual-id',
    name: '全部歌曲',
  );
  Playlist get allSongsVirtualPlaylist => _allSongsVirtualPlaylist;

  List<Song> _allSongs = []; // 所有不重复歌曲的集合
  List<Song> get allSongs => _allSongs;

  // --- 元数据缓存 ---
  final Map<String, SongMetadataCacheEntry> _songMetadataCache = {};
  Timer? _metadataCacheSaveTimer;

  // --- 封面加载队列 ---
  final Set<String> _visibleCoverPaths = {};
  final Set<String> _pendingCoverRequests = {};
  final ListQueue<String> _coverQueue = ListQueue<String>();
  bool _coverWorkerRunning = false;

  // --- 播放器相关 ---
  final Player _mediaPlayer = Player(
    configuration: const PlayerConfiguration(
      pitch: true, // 启用音调控制功能
    ),
  ); // Media-Kit 播放器实例
  Player get mediaPlayer => _mediaPlayer;

  StreamSubscription<bool>? _exclusiveModeSubscription; // 用于管理独占模式的流订阅

  bool _isPlaying = false; // 播放器状态
  bool get isPlaying => _isPlaying;

  int _currentSongIndex = -1; // 当前播放歌曲的索引（在当前歌单中）
  Song? _currentSong; // 当前播放的歌曲
  Song? get currentSong => _currentSong;

  bool _isAutoPlaying = false; // 是否为自动播放（播放完成后的自动切换）
  PlayMode _playMode = PlayMode.sequence; // 播放模式：顺序、随机、单曲循环
  static const _playModeKey = 'play_mode'; // 存储播放模式的 key
  PlayMode get playMode => _playMode;

  List<int> _shuffledIndices = []; // 用于随机播放时的索引列表
  final Random _random = Random(); // 用于打乱索引

  // --- 播放进度相关 ---
  Duration _currentPosition = Duration.zero; // 当前播放进度
  Duration _totalDuration = Duration.zero; // 当前歌曲总时长

  Duration get currentPosition => _currentPosition;
  Duration get totalDuration => _totalDuration;

  // --- 音调与倍速 ---
  double _currentPitch = 1.0; // 音调大小
  double _currentPlaybackRate = 1.0; // 播放速度

  double get currentPitch => _currentPitch;
  double get currentPlaybackRate => _currentPlaybackRate;

  // --- 音量控制 ---
  double _volume = 100.0; // 当前音量
  double _lastVolumeBeforeMute = 100.0; // 静音前的音量

  static const _volumeKey = 'player_volume';
  static const _lastVolumeBeforeMuteKey = 'player_last_volume';

  double get volume => _volume;
  double get lastVolumeBeforeMute => _lastVolumeBeforeMute;

  // --- 歌词相关 --
  List<LyricLine> _currentLyrics = []; // 当前歌曲歌词列表
  int _currentLyricLineIndex = -1; // 当前歌词行索引

  List<LyricLine> get currentLyrics => _currentLyrics;
  int get currentLyricLineIndex => _currentLyricLineIndex;

  final StreamController<int> _lyricLineIndexController =
      StreamController<int>.broadcast(); // 歌词行变动流
  Stream<int> get lyricLineIndexStream => _lyricLineIndexController.stream;

  // --- 搜索相关 ---
  String _searchKeyword = ''; // 当前搜索关键词
  bool _isSearching = false; // 是否正在搜索（用于切换UI）
  List<Song> _filteredSongs = []; // 搜索结果列表

  bool _disableHotKeys = false; // 是否禁用快捷键

  String get searchKeyword => _searchKeyword;
  bool get isSearching => _isSearching;
  List<Song> get filteredSongs => _filteredSongs;

  bool get disableHotKeys => _disableHotKeys;

  // --- 日志相关 ---
  File? _logFile;
  File? get logFile => _logFile;

  // --- 独占模式相关 ---
  bool _isExclusiveModeEnabled = false;
  bool _isExclusiveModeAvailable = false;

  bool get isExclusiveModeEnabled => _isExclusiveModeEnabled;
  bool get isExclusiveModeAvailable => _isExclusiveModeAvailable;

  // --- 多选相关 ---
  bool _isMultiSelectMode = false; // 是否处于多选模式
  final Set<String> _selectedSongPaths = <String>{}; // 选中的歌曲路径集合

  bool get isMultiSelectMode => _isMultiSelectMode;
  Set<String> get selectedSongPaths => _selectedSongPaths;
  List<Song> get selectedSongs => _currentPlaylistSongs
      .where((song) => _selectedSongPaths.contains(song.filePath))
      .toList();

  // --- 当前歌单的歌曲 ---
  List<Song> _currentPlaylistSongs = []; // 当前选中歌单下的所有歌曲
  bool _isLoadingSongs = false; // 是否正在加载歌曲

  List<Song> get currentPlaylistSongs => _currentPlaylistSongs;
  bool get isLoadingSongs => _isLoadingSongs;

  // 支持的音频文件扩展名
  final List<String> _supportedAudioExtensions = [
    '.mp3',
    '.flac',
    '.wav',
    '.aac',
    '.m4a',
    '.ogg',
    '.wma',
    '.ape',
    '.alac',
    '.opus',
  ];

  // --- SMTC ---
  SmtcManager? _smtcManager;
  SmtcManager? get smtcManager => _smtcManager;

  // --- 音频设备相关 ---
  List<AudioDevice> _availableAudioDevices = [];
  AudioDevice? _selectedAudioDevice;
  bool _hasAttemptedRestore = false; // 防止每次设备列表变动都重复执行恢复逻辑

  List<AudioDevice> get availableAudioDevices => _availableAudioDevices;
  AudioDevice? get selectedAudioDevice => _selectedAudioDevice;

  // --- 视图上下文管理 ---
  DetailViewContext _currentDetailViewContext = DetailViewContext.playlist;
  String _activeDetailTitle = ''; // 当前详情页的标题
  List<Song> _activeSongList = []; // 当前详情页显示的歌曲列表

  DetailViewContext get currentDetailViewContext => _currentDetailViewContext;
  String get activeDetailTitle => _activeDetailTitle;
  List<Song> get activeSongList => _activeSongList;

  // --- 存储从JSON加载的排序信息 ---
  Map<String, List<String>> _artistSortOrders = {};
  Map<String, List<String>> _albumSortOrders = {};

  // 播放队列相关
  List<Song>? _currentPlayingQueue; // 独立的播放队列，基于当前播放列表
  List<String>? _currentPlayingQueueFilePaths; // 对应的文件路径列表
  int _currentQueueIndex = -1; // 当前播放的歌曲在队列中的索引
  bool _isUsingQueue = false; // 标记是否使用独立队列

  List<Song> get playingQueue => _currentPlayingQueue ?? [];
  List<String> get playingQueueFilePaths => _currentPlayingQueueFilePaths ?? [];
  int get currentQueueIndex => _currentQueueIndex;
  bool get isUsingQueue => _isUsingQueue;

  // --- 消息通知 ---
  final StreamController<String> _errorStreamController =
      StreamController<String>.broadcast(); // 错误信息流

  final StreamController<String> _infoStreamController =
      StreamController<String>.broadcast(); // 普通信息流

  Stream<String> get errorStream => _errorStreamController.stream;
  Stream<String> get infoStream => _infoStreamController.stream;

  DateTime? _lastAudioDeviceErrorLogged;
  // 限制日志写入间隔
  static const Duration _audioDeviceErrorInterval = Duration(seconds: 5);

  PlaylistContentNotifier(this._settingsProvider, this._themeProvider) {
    _setupMediaPlayerListeners(); // 设置 media-kit 的监听器
    _initLogFile();
    _loadAllData(); // 使用一个统一的方法来加载所有数据
    _listenToPlayingState();
    _loadAudioDevices(); // 加载音频设备
    _smtcManager = SmtcManager(
      onPlay: play,
      onPause: pause,
      onNext: playNext,
      onPrevious: playPrevious,
      onSeek: (position) async {
        await _mediaPlayer.seek(position);
      },
      onSetPosition: (trackId, position) async {
        await _mediaPlayer.seek(position);
      },
    );
  }

  Future<void> _initLogFile() async {
    try {
      final logDir = Directory('logs');
      if (!await logDir.exists()) {
        await logDir.create(recursive: true);
      }
      _logFile = File('${logDir.path}/errors.log');
    } catch (e) {
      // 如果无法创建日志文件，继续运行但不记录日志
    }
  }

  Future<void> _writeErrorToLog(String message, Object error) async {
    if (_logFile == null) return;

    final errorString = error.toString();
    if (errorString.contains('Could not open/initialize audio device')) {
      // 检查上次记录该错误的时间
      final now = DateTime.now();
      if (_lastAudioDeviceErrorLogged != null) {
        final timeSinceLastLog = now.difference(_lastAudioDeviceErrorLogged!);
        if (timeSinceLastLog < _audioDeviceErrorInterval) {
          // 距离上次记录少于5秒不记录
          return;
        }
      }
      // 更新最后记录时间
      _lastAudioDeviceErrorLogged = now;
    }

    try {
      final timestamp = DateTime.now().toString();
      final errorInfo = '[$timestamp] $message\nError details: $error\n\n';
      await _logFile!.writeAsString(errorInfo, mode: FileMode.writeOnlyAppend);
    } catch (e) {
      //
    }
  }

  Future<void> _loadAllData() async {
    // 先加载歌手和专辑排序，避免初始化过程中被覆盖
    _artistSortOrders = await _playlistManager.loadArtistSortOrders();
    _albumSortOrders = await _playlistManager.loadAlbumSortOrders();
    await _loadSongMetadataCache();

    // 加载现有的播放列表
    await _loadPlaylists();
    // 加载播放模式
    await loadPlayMode();
    // 加载音量设置
    await _loadVolumeSetting();
    // 恢复播放状态
    await _restorePlaybackState();
  }

  // 获取规范化的路径
  String _normalizePath(String path) {
    return p.normalize(path);
  }

  // 加载歌曲元数据缓存
  Future<void> _loadSongMetadataCache() async {
    try {
      final cacheFile = await _playlistManager.getSongMetadataCacheFile();
      if (!await cacheFile.exists()) {
        return;
      }

      final contents = await cacheFile.readAsString();
      final decoded = jsonDecode(contents);

      if (decoded is Map<String, dynamic>) {
        _songMetadataCache.clear();
        decoded.forEach((key, value) {
          if (value is Map<String, dynamic>) {
            // 统一路径格式以保证缓存命中一致
            _songMetadataCache[_normalizePath(key)] =
                SongMetadataCacheEntry.fromJson(value);
          }
        });
      }
    } catch (e) {
      _songMetadataCache.clear();
    }
  }

  void _scheduleMetadataCacheSave() {
    _metadataCacheSaveTimer?.cancel();
    // 延迟保存降低IO压力，同时不影响用户感知
    _metadataCacheSaveTimer = Timer(const Duration(milliseconds: 400), () {
      _saveSongMetadataCache();
    });
  }

  // 保存歌曲元数据缓存
  Future<void> _saveSongMetadataCache() async {
    try {
      final cacheFile = await _playlistManager.getSongMetadataCacheFile();
      final data = <String, dynamic>{};
      _songMetadataCache.forEach((key, entry) {
        data[key] = entry.toJson();
      });
      await cacheFile.writeAsString(jsonEncode(data));
    } catch (e) {
      //
    }
  }

  // 清理不需要的元数据缓存
  void _pruneMetadataCache(Set<String> validPaths) {
    final normalizedValidPaths = validPaths.map(_normalizePath).toSet();
    final removedKeys = _songMetadataCache.keys
        .where((key) => !normalizedValidPaths.contains(key))
        .toList();
    if (removedKeys.isEmpty) {
      return;
    }
    for (final key in removedKeys) {
      _songMetadataCache.remove(key);
    }
    _scheduleMetadataCacheSave();
  }

  double _sanitizeVolume(double? value, double fallback) {
    if (value == null || value.isNaN || value.isInfinite) {
      return fallback;
    }
    final clamped = value.clamp(0.0, 100.0);
    return clamped.toDouble();
  }

  Future<void> _loadVolumeSetting() async {
    final prefs = await SharedPreferences.getInstance();
    _volume = _sanitizeVolume(prefs.getDouble(_volumeKey), 100.0);

    final defaultLastVolume = _volume < 1.0 ? 100.0 : _volume;
    final storedLastVolume = _sanitizeVolume(
      prefs.getDouble(_lastVolumeBeforeMuteKey),
      defaultLastVolume,
    );
    _lastVolumeBeforeMute = storedLastVolume < 1.0
        ? defaultLastVolume
        : storedLastVolume;

    await _mediaPlayer.setVolume(_volume);
  }

  Future<void> setVolume(double newVolume) async {
    _volume = _sanitizeVolume(newVolume, 0.0);
    if (_volume > 1.0) _lastVolumeBeforeMute = _volume;

    await _mediaPlayer.setVolume(_volume);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_volumeKey, _volume);
    await prefs.setDouble(_lastVolumeBeforeMuteKey, _lastVolumeBeforeMute);

    notifyListeners();
  }

  void toggleMute() {
    final isMuted = _volume < 1.0;
    final newVolume = isMuted ? _lastVolumeBeforeMute : 0.0;
    setVolume(newVolume);
  }

  @override
  // --- 播放器相关 ---
  void dispose() {
    _lyricLineIndexController.close();
    _errorStreamController.close();
    _exclusiveModeSubscription?.cancel(); // 取消独占模式订阅
    _safeDispose(); // 释放播放器资源
    _cleanupSmtc();
    _metadataCacheSaveTimer?.cancel();
    _saveSongMetadataCache();
    savePlaybackState();
    super.dispose();
  }

  void _safeDispose() {
    _mediaPlayer.stop();
    // 延迟500毫秒销毁播放器
    // 这是为了解决更新到 Flutter 3.38+ 之后某些情况下的崩溃问题
    // 参考https://github.com/media-kit/media-kit/issues/1340
    Future.delayed(const Duration(milliseconds: 500));
    _mediaPlayer.dispose();
  }

  void _setupMediaPlayerListeners() {
    _mediaPlayer.stream.playing.listen((playing) {
      _isPlaying = playing; // 更新内部状态
      notifyListeners();
    });

    _mediaPlayer.stream.completed.listen((completed) async {
      if (completed) {
        _isPlaying = false; // 更新内部状态
        notifyListeners();
        _isAutoPlaying = true; // 标记为自动播放
        await _playNextLogic();
        _isAutoPlaying = false; // 重置标记
      }
    });

    _mediaPlayer.stream.position.listen((position) {
      _currentPosition = position; // 更新当前位置
      updateLyricLine(position);
      _smtcManager?.updateTimeline(
        position: position,
        duration: _totalDuration,
      );
      // notifyListeners();
    });

    _mediaPlayer.stream.duration.listen((duration) {
      _totalDuration = duration; // 更新总时长
      _smtcManager?.updateTimeline(
        position: _currentPosition,
        duration: duration,
      );
      // notifyListeners();
    });

    _mediaPlayer.stream.error.listen((error) {
      final errorString = error.toString();
      final shouldNotifyUI =
          !(_settingsProvider.ignorePlaybackErrors &&
              (errorString.contains('Error decoding audio') ||
                  errorString.contains('Failed to recognize file format')));

      if (_currentSong != null) {
        final errorMessage =
            '播放 ${p.basename(_currentSong!.filePath)} 出错: $error';
        if (shouldNotifyUI) {
          _errorStreamController.add(errorMessage);
        }
        // 记录详细错误信息到日志文件
        _writeErrorToLog(errorMessage, error);
        debugPrint('播放${p.basename(_currentSong!.filePath)}出错: $error');
      } else {
        final errorMessage = '播放出错: $error';
        _errorStreamController.add(errorMessage);
        // 记录详细错误信息到日志文件
        _writeErrorToLog(errorMessage, error);
      }

      // 尝试播放下一首歌曲
      // playNext();
    });
  }

  Future<void> _cleanupSmtc() async {
    await _smtcManager?.dispose();
  }

  // --- 歌单相关 ---

  Future<void> _loadPlaylists() async {
    final List<Playlist> loadedPlaylists = await _playlistManager
        .loadPlaylists();
    _playlists = loadedPlaylists;
    _selectedIndex = _playlists.isNotEmpty ? 0 : -1;
    // await _updateAllSongsList();
    notifyListeners();

    // 异步加载全部歌曲列表，不阻塞UI
    unawaited(_updateAllSongsList());

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
    // 切换歌单时退出多选模式
    if (_isMultiSelectMode) {
      _isMultiSelectMode = false;
      _selectedSongPaths.clear();
    }
    notifyListeners();
    _loadCurrentPlaylistSongs(); // 选中索引变化时加载歌曲到 UI 和播放器
  }

  // 加载当前选中歌单的歌曲列表
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
    // 确保当前播放列表的歌曲已被解析且与文件路径列表一致
    await _ensurePlaylistSongs(currentPlaylist);
    _currentPlaylistSongs = currentPlaylist.songs!;
    unawaited(_verifySongMetadataInBackground(currentPlaylist.songFilePaths));

    _isLoadingSongs = false;
    if (_isSearching) {
      _updateFilteredSongs(); // 如果正在搜索，同步更新结果
    }
    notifyListeners();
  }

  // 解析单个歌曲文件的元数据
  Future<Song> _parseSongMetadata(String filePath) async {
    final cacheKey = _normalizePath(filePath);
    final cached = _songMetadataCache[cacheKey];

    if (cached != null) {
      return Song(
        title: cached.title,
        artist: cached.artist,
        album: cached.album,
        filePath: filePath,
        albumArt: null,
        duration: cached.durationMs != null
            ? Duration(milliseconds: cached.durationMs!)
            : null,
      );
    }

    String title = p.basenameWithoutExtension(filePath);
    String artist = '未知歌手';
    String album = '未知专辑';
    Duration? duration;

    final normalizedPath = Uri.file(
      filePath,
    ).toFilePath(windows: Platform.isWindows);
    final file = File(normalizedPath);

    if (!await file.exists()) {
      return Song(
        title: title,
        artist: '文件不存在 (解析失败)',
        album: '未知专辑',
        filePath: filePath,
        albumArt: null,
        duration: null,
      );
    }

    try {
      final metadata = await readAudioInfo(
        path: normalizedPath,
        options: const AudioInfoOptions(
          needCover: false,
          needLyrics: false,
          needAudioProps: true,
        ),
      );
      final stat = await file.stat();

      if (metadata.title != null && metadata.title!.isNotEmpty) {
        title = metadata.title!;
      }
      if (metadata.artist != null && metadata.artist!.isNotEmpty) {
        artist = metadata.artist!;
      }
      if (metadata.album != null && metadata.album!.isNotEmpty) {
        album = metadata.album!;
      }

      if (metadata.durationMs != null) {
        duration = Duration(milliseconds: metadata.durationMs!.toInt());
      }

      _songMetadataCache[cacheKey] = SongMetadataCacheEntry(
        title: title,
        artist: artist,
        album: album,
        durationMs: metadata.durationMs?.toInt(),
        modifiedMs: stat.modified.millisecondsSinceEpoch,
      );
      _scheduleMetadataCacheSave();
    } catch (e) {
      artist = '未知歌手 (解析失败)';
    }

    return Song(
      title: title,
      artist: artist,
      album: album,
      filePath: filePath,
      albumArt: null,
      duration: duration,
    );
  }

  // 为播放准备完整元数据（包括封面等）
  Future<Song> _prepareSongForPlayback(String filePath) async {
    // 首先获取基础元数据
    final Song basicSong = await _parseSongMetadata(filePath);

    // 只在没有封面的情况下加载元数据
    if (basicSong.albumArt == null) {
      try {
        final normalizedPath = Uri.file(
          filePath,
        ).toFilePath(windows: Platform.isWindows);
        final metadata = await readAudioInfo(
          path: normalizedPath,
          options: const AudioInfoOptions(
            needCover: true,
            needLyrics: false,
            needAudioProps: true,
          ),
        );

        // 使用获取到的完整信息创建Song对象
        String title = basicSong.title;
        String artist = basicSong.artist;
        String album = basicSong.album;
        Duration? duration = basicSong.duration;

        if (metadata.title != null && metadata.title!.isNotEmpty) {
          title = metadata.title!;
        }
        if (metadata.artist != null && metadata.artist!.isNotEmpty) {
          artist = metadata.artist!;
        }
        if (metadata.album != null && metadata.album!.isNotEmpty) {
          album = metadata.album!;
        }
        if (metadata.durationMs != null) {
          duration = Duration(milliseconds: metadata.durationMs!.toInt());
        }

        // 更新缓存
        final cacheKey = _normalizePath(filePath);
        if (_songMetadataCache.containsKey(cacheKey)) {
          final cachedEntry = _songMetadataCache[cacheKey]!;
          _songMetadataCache[cacheKey] = SongMetadataCacheEntry(
            title: cachedEntry.title,
            artist: cachedEntry.artist,
            album: cachedEntry.album,
            durationMs: cachedEntry.durationMs,
            modifiedMs: cachedEntry.modifiedMs,
          );
        }

        return Song(
          title: title,
          artist: artist,
          album: album,
          filePath: filePath,
          albumArt: metadata.cover,
          duration: duration,
        );
      } catch (e) {
        return basicSong;
      }
    }

    return basicSong;
  }

  void _updateSongInCollections(
    String filePath,
    Song Function(Song song) updater,
  ) {
    final targetPath = _normalizePath(filePath);
    bool updated = false;

    void updateList(List<Song> songs) {
      for (int i = 0; i < songs.length; i++) {
        if (_normalizePath(songs[i].filePath) == targetPath) {
          songs[i] = updater(songs[i]);
          updated = true;
        }
      }
    }

    for (final playlist in _playlists) {
      if (playlist.songs != null) {
        updateList(playlist.songs!);
      }
    }

    // 同步更新不同来源的歌曲列表以保持状态一致
    updateList(_allSongs);
    updateList(_currentPlaylistSongs);
    updateList(_activeSongList);

    // 单独处理当前播放歌曲
    if (_currentSong != null &&
        _normalizePath(_currentSong!.filePath) == targetPath) {
      _currentSong = updater(_currentSong!);
      updated = true;
    }

    if (updated) {
      notifyListeners();
    }
  }

  // 应用缓存的元数据
  void _applyCachedMetadata(String filePath, SongMetadataCacheEntry entry) {
    _updateSongInCollections(filePath, (song) {
      return Song(
        title: entry.title,
        artist: entry.artist,
        album: entry.album,
        filePath: song.filePath,
        albumArt: song.albumArt,
        duration: entry.durationMs != null
            ? Duration(milliseconds: entry.durationMs!)
            : song.duration,
      );
    });
  }

  Song _markSongMissing(Song song) {
    return Song(
      title: song.title,
      artist: '文件不存在 (解析失败)',
      album: song.album,
      filePath: song.filePath,
      albumArt: null,
      duration: song.duration,
    );
  }

  // 后台校验更新歌曲的元数据
  Future<void> _verifySongMetadataInBackground(
    Iterable<String> filePaths,
  ) async {
    // 延迟执行以避免与前台操作竞争资源
    await Future.delayed(const Duration(milliseconds: 300));

    for (final filePath in filePaths) {
      final cacheKey = _normalizePath(filePath);
      final cached = _songMetadataCache[cacheKey];
      final normalizedPath = Uri.file(
        filePath,
      ).toFilePath(windows: Platform.isWindows);
      final file = File(normalizedPath);

      try {
        final stat = await file.stat();
        final modifiedMs = stat.modified.millisecondsSinceEpoch;

        if (cached != null && cached.modifiedMs == modifiedMs) {
          continue;
        }

        final metadata = await readAudioInfo(
          path: normalizedPath,
          options: const AudioInfoOptions(
            needCover: false,
            needLyrics: false,
            needAudioProps: true,
          ),
        );

        final title = (metadata.title != null && metadata.title!.isNotEmpty)
            ? metadata.title!
            : p.basenameWithoutExtension(filePath);
        final artist = (metadata.artist != null && metadata.artist!.isNotEmpty)
            ? metadata.artist!
            : '未知歌手';
        final album = (metadata.album != null && metadata.album!.isNotEmpty)
            ? metadata.album!
            : '未知专辑';

        final entry = SongMetadataCacheEntry(
          title: title,
          artist: artist,
          album: album,
          durationMs: metadata.durationMs?.toInt(),
          modifiedMs: modifiedMs,
        );

        _songMetadataCache[cacheKey] = entry;
        _scheduleMetadataCacheSave();
        _applyCachedMetadata(filePath, entry);
      } catch (e) {
        if (_songMetadataCache.remove(cacheKey) != null) {
          _scheduleMetadataCacheSave();
        }
        _updateSongInCollections(filePath, _markSongMissing);
      }
    }
  }

  // 封面处理
  void requestSongCover(String filePath) {
    final cacheKey = _normalizePath(filePath);
    _visibleCoverPaths.add(cacheKey);

    if (_pendingCoverRequests.contains(cacheKey)) {
      return;
    }
    final song = _findSongByPath(filePath);
    if (song?.albumArt != null) {
      return;
    }

    _pendingCoverRequests.add(cacheKey);
    _coverQueue.add(cacheKey);
    _processCoverQueue();
  }

  // 释放封面
  void releaseSongCover(String filePath) {
    final cacheKey = _normalizePath(filePath);
    _visibleCoverPaths.remove(cacheKey);
    _pendingCoverRequests.remove(cacheKey);
    _removeFromCoverQueue(cacheKey);
    if (_currentSong != null &&
        _normalizePath(_currentSong!.filePath) == cacheKey) {
      return;
    }
    _updateSongInCollections(filePath, (song) {
      return Song(
        title: song.title,
        artist: song.artist,
        album: song.album,
        filePath: song.filePath,
        albumArt: null,
        duration: song.duration,
      );
    });
  }

  // 寻找歌曲
  Song? _findSongByPath(String filePath) {
    final target = _normalizePath(filePath);
    for (final song in _currentPlaylistSongs) {
      if (_normalizePath(song.filePath) == target) {
        return song;
      }
    }
    for (final song in _allSongs) {
      if (_normalizePath(song.filePath) == target) {
        return song;
      }
    }
    return null;
  }

  void _removeFromCoverQueue(String cacheKey) {
    if (_coverQueue.isEmpty) {
      return;
    }
    final remaining = ListQueue<String>();
    while (_coverQueue.isNotEmpty) {
      final item = _coverQueue.removeFirst();
      if (item != cacheKey) {
        remaining.add(item);
      }
    }
    _coverQueue.addAll(remaining);
  }

  void _processCoverQueue() {
    if (_coverWorkerRunning) {
      return;
    }
    _coverWorkerRunning = true;
    unawaited(_coverWorker());
  }

  Future<void> _coverWorker() async {
    while (_coverQueue.isNotEmpty) {
      final cacheKey = _coverQueue.removeFirst();
      if (!_visibleCoverPaths.contains(cacheKey)) {
        _pendingCoverRequests.remove(cacheKey);
        continue;
      }
      final filePath = cacheKey;
      try {
        final normalizedPath = Uri.file(
          filePath,
        ).toFilePath(windows: Platform.isWindows);
        final metadata = await readAudioInfo(
          path: normalizedPath,
          options: const AudioInfoOptions(
            needCover: true,
            needLyrics: false,
            needAudioProps: false,
          ),
        );

        if (metadata.cover != null && metadata.cover!.isNotEmpty) {
          _updateSongInCollections(filePath, (song) {
            return Song(
              title: song.title,
              artist: song.artist,
              album: song.album,
              filePath: song.filePath,
              albumArt: metadata.cover,
              duration: song.duration,
            );
          });
        }
      } catch (e) {
        //
      } finally {
        _pendingCoverRequests.remove(cacheKey);
      }
    }
    _coverWorkerRunning = false;
  }

  Future<bool> pickAndAddSongs() async {
    if (_selectedIndex == -1) {
      _infoStreamController.add('请先在左侧选择一个要添加歌曲的歌单');
      return false;
    }

    final bool allowAnyFormat = _settingsProvider.allowAnyFormat;

    FilePickerResult? result;
    if (allowAnyFormat) {
      result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: true,
        lockParentWindow: true,
      );
    } else {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'wav',
          'wady',
          'wavarc',
          'flac',
          'alac',
          'ape',
          'mp3',
          'aac',
          'm4a',
          'ogg',
          'opus',
          'wma',
          'aiff',
          'pcm',
        ],
        allowMultiple: true,
        lockParentWindow: true,
      );
    }

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
    // 如果不为空，说明有新歌曲被添加
    if (newSongPaths.isNotEmpty) {
      // 后台异步处理歌曲添加
      _processSongsInBackground(currentPlaylist, newSongPaths);
      return true; // 真的有添加
    }
    // 如果确实选择了文件，但 newSongPaths 为空，说明选择是重复歌曲
    else if (result.files.isNotEmpty) {
      _infoStreamController.add('所选歌曲已存在于当前歌单中');
      return false;
    }
    // 其他情况不提示
    else {
      return false;
    }
  }

  Future<void> _processSongsInBackground(
    Playlist currentPlaylist,
    List<String> newSongPaths,
  ) async {
    _isLoadingSongs = true;
    notifyListeners();

    try {
      // 分批处理歌曲以避免阻塞UI
      const batchSize = 10;
      final List<Song> parsedSongs = [];

      // 分批解析歌曲元数据
      for (int i = 0; i < newSongPaths.length; i += batchSize) {
        final end = (i + batchSize < newSongPaths.length)
            ? i + batchSize
            : newSongPaths.length;
        final batch = newSongPaths.sublist(i, end);

        // 并行处理同一批次的歌曲
        final batchSongs = await Future.wait(
          batch.map((path) => _parseSongMetadata(path)).toList(),
        );

        parsedSongs.addAll(batchSongs);
        await Future.delayed(const Duration(milliseconds: 10)); // 允许UI更新
      }

      // 添加歌曲路径到播放列表
      currentPlaylist.songFilePaths.addAll(newSongPaths);

      // 更新歌曲对象列表
      if (currentPlaylist.songs != null) {
        currentPlaylist.songs!.addAll(parsedSongs);
      } else {
        // 如果之前没有解析过歌曲，则全部重新解析
        await _ensurePlaylistSongs(currentPlaylist);
      }

      // 保存播放列表
      await _savePlaylists();

      // 更新当前播放列表和所有歌曲列表
      if (_selectedIndex == _playlists.indexOf(currentPlaylist)) {
        _currentPlaylistSongs = List.from(currentPlaylist.songs ?? []);
      }
      await _updateAllSongsList();

      _infoStreamController.add('成功添加 ${newSongPaths.length} 首歌曲');
    } catch (e, stackTrace) {
      _errorStreamController.add('添加歌曲时发生错误: $e');
      _writeErrorToLog('添加歌曲时发生错误', e);
      debugPrint('添加歌曲错误详情: $e\nStack trace: $stackTrace');

      // 恢复到添加前的状态
      // 移除已添加的歌曲路径
      currentPlaylist.songFilePaths.removeWhere(
        (path) => newSongPaths.contains(path),
      );

      // 重新加载播放列表
      await _loadCurrentPlaylistSongs();
      await _updateAllSongsList();
    } finally {
      _isLoadingSongs = false;
      notifyListeners();
    }
  }

  bool addPlaylist(String name, {List<String>? folderPaths}) {
    final trimmedName = name.trim();

    if (trimmedName.isEmpty) {
      _infoStreamController.add('歌单名称不能为空');
      return false; // 失败
    }

    if (_playlists.any((playlist) => playlist.name == trimmedName)) {
      _infoStreamController.add('歌单名称 $trimmedName 已存在');
      return false; // 失败
    }

    // 如果提供了folderPaths，则创建基于文件夹的播放列表
    final playlist = folderPaths != null && folderPaths.isNotEmpty
        ? Playlist(
            name: trimmedName,
            isFolderBased: true,
            folderPaths: folderPaths,
          )
        : Playlist(name: trimmedName);

    _playlists.add(playlist);
    _selectedIndex = _playlists.length - 1;

    // 如果是基于文件夹的播放列表，则扫描文件夹中的歌曲
    if (folderPaths != null && folderPaths.isNotEmpty) {
      _scanFoldersAndAddSongs(folderPaths);
    }

    _savePlaylists();
    _loadCurrentPlaylistSongs(); // 加载当前播放列表歌曲
    _updateAllSongsList(); // 更新所有歌曲列表
    _infoStreamController.add('已成功创建歌单 $trimmedName');

    notifyListeners();
    return true; // 成功
  }

  // 扫描文件夹并添加歌曲
  Future<void> _scanFoldersAndAddSongs(List<String> folderPaths) async {
    if (_selectedIndex < 0 || _selectedIndex >= _playlists.length) return;

    final playlist = _playlists[_selectedIndex];
    if (!playlist.isFolderBased) return;

    _isLoadingSongs = true;
    notifyListeners();

    try {
      final Set<String> songPaths = <String>{};

      // 遍历所有文件夹路径
      for (final folderPath in folderPaths) {
        final directory = Directory(folderPath);
        if (await directory.exists()) {
          await for (final file in directory.list(
            recursive: true,
            followLinks: false,
          )) {
            if (file is File) {
              final extension = p.extension(file.path).toLowerCase();
              // 检查是否为支持的音频文件格式
              if (_supportedAudioExtensions.contains(extension)) {
                songPaths.add(file.path);
              }
            }
          }
        }
      }

      // 比较新旧歌曲路径集合，只添加或删除变化的部分
      final oldSongPaths = playlist.songFilePaths.toSet();
      final newSongPaths = songPaths;

      // 找出新增的歌曲路径
      final addedSongPaths = newSongPaths.difference(oldSongPaths);
      // 找出删除的歌曲路径
      final removedSongPaths = oldSongPaths.difference(newSongPaths);

      // 从现有列表中移除已删除的歌曲
      playlist.songFilePaths.removeWhere(
        (path) => removedSongPaths.contains(path),
      );

      // 添加新增的歌曲到末尾
      playlist.songFilePaths.addAll(addedSongPaths);

      // 解析新增歌曲的元数据
      final List<Song> newSongs = [];
      for (final path in addedSongPaths) {
        final song = await _parseSongMetadata(path);
        newSongs.add(song);
      }

      // 更新播放列表的歌曲对象列表
      if (playlist.songs != null) {
        // 移除已删除的歌曲对象
        playlist.songs!.removeWhere(
          (song) => removedSongPaths.contains(song.filePath),
        );
        // 添加新增的歌曲对象
        playlist.songs!.addAll(newSongs);
      } else {
        // 如果之前没有解析过歌曲，则全部重新解析
        final List<Song> songs = [];
        for (final path in playlist.songFilePaths) {
          final song = await _parseSongMetadata(path);
          songs.add(song);
        }
        playlist.songs = songs;
      }

      _savePlaylists();

      // 如果当前选中的就是这个播放列表，则更新当前播放列表歌曲
      if (_selectedIndex == _playlists.indexOf(playlist)) {
        _currentPlaylistSongs = List.from(playlist.songs ?? []);
      }

      // 更新所有歌曲列表
      await _updateAllSongsList();

      // 显示操作结果信息
      if (addedSongPaths.isNotEmpty || removedSongPaths.isNotEmpty) {
        _infoStreamController.add(
          '刷新完成：新增 ${addedSongPaths.length} 首歌曲，移除 ${removedSongPaths.length} 首歌曲',
        );
      } else {
        _infoStreamController.add('刷新完成：没有发现变化');
      }
    } catch (e) {
      _errorStreamController.add('扫描文件夹时出错: $e');
    } finally {
      _isLoadingSongs = false;
      notifyListeners();
    }
  }

  // 更新播放列表的文件夹路径
  void updatePlaylistFolders(int index, List<String> folderPaths) {
    if (index < 0 || index >= _playlists.length) return;

    final playlist = _playlists[index];
    if (!playlist.isFolderBased) return;

    playlist.folderPaths = List<String>.from(folderPaths);
    _savePlaylists();

    // 重新扫描文件夹内容
    _scanFoldersAndAddSongs(playlist.folderPaths);

    _infoStreamController.add('已更新 ${playlist.name}');
    notifyListeners();
  }

  // 刷新基于文件夹的播放列表
  Future<void> refreshFolderPlaylist() async {
    if (_selectedIndex < 0 || _selectedIndex >= _playlists.length) return;

    final playlist = _playlists[_selectedIndex];
    if (!playlist.isFolderBased) return;

    _isLoadingSongs = true;
    notifyListeners();

    try {
      await _scanFoldersAndAddSongs(playlist.folderPaths);
      // _infoStreamController.add('已刷新文件夹内容');
    } catch (e) {
      // _errorStreamController.add('刷新文件夹内容时出错: $e');
    } finally {
      _isLoadingSongs = false;
      notifyListeners();
    }
  }

  Future<bool> deletePlaylist(int index) async {
    // 边界条件检查
    if (index < 0 || index >= _playlists.length) {
      return false;
    }

    final playlistToDelete = _playlists[index];
    if (playlistToDelete.isDefault) {
      _errorStreamController.add('默认歌单不可删除');
      return false;
    }

    final deletedPlaylistName = playlistToDelete.name;

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
    _infoStreamController.add('已删除歌单 “$deletedPlaylistName”');

    return true; // 表示删除成功
  }

  bool editPlaylistName(int index, String newName) {
    final trimmedName = newName.trim();

    // 检查名称是否为空
    if (trimmedName.isEmpty) {
      _infoStreamController.add('歌单名称不能为空');
      return false; // 操作失败
    }

    // 检查名称是否重复（要排除自己）
    if (_playlists.any(
      (p) => p.name == trimmedName && _playlists.indexOf(p) != index,
    )) {
      _infoStreamController.add('歌单名称 "$trimmedName" 已存在');
      return false; // 操作失败
    }

    // 如果一切正常，执行重命名逻辑
    final oldName = _playlists[index].name;
    final newPlaylists = List<Playlist>.from(_playlists);
    newPlaylists[index].name = trimmedName;
    _playlists = newPlaylists;

    _savePlaylists();

    _infoStreamController.add('已将歌单 “$oldName” 重命名为 “$trimmedName”');
    notifyListeners();

    return true;
  }

  // 获取当前播放队列的歌曲列表
  List<Song> get playingQueueSongs {
    if (_isUsingQueue && _currentPlayingQueue != null) {
      return _currentPlayingQueue!;
    } else {
      if (_playingPlaylist == null || _playingPlaylist!.songs == null) {
        return [];
      }
      return _playingPlaylist!.songs!;
    }
  }

  // 将当前播放队列保存为新歌单
  Future<bool> saveQueueAsPlaylist(
    String playlistName,
    List<Song> queue,
  ) async {
    final trimmedName = playlistName.trim();

    if (trimmedName.isEmpty) {
      _infoStreamController.add('歌单名称不能为空');
      return false;
    }

    if (_playlists.any((playlist) => playlist.name == trimmedName)) {
      _infoStreamController.add('歌单名称 "$trimmedName" 已存在');
      return false;
    }

    if (addPlaylist(trimmedName)) {
      final newPlaylist = _playlists[_playlists.length - 1];

      // 添加歌曲路径和歌曲对象到新歌单
      newPlaylist.songFilePaths = queue.map((song) => song.filePath).toList();
      newPlaylist.songs = List.from(queue);

      await _savePlaylists();

      await _updateAllSongsList();

      _infoStreamController.add(
        '已成功创建歌单 "$trimmedName"，包含 ${queue.length} 首歌曲',
      );

      notifyListeners();
      return true;
    }

    return false;
  }

  // 确保播放列表的歌曲已被解析
  Future<void> _ensurePlaylistSongs(Playlist playlist) async {
    if (playlist.songs == null) {
      final List<Song> songsWithMetadata = [];
      for (final filePath in playlist.songFilePaths) {
        final song = await _parseSongMetadata(filePath);
        songsWithMetadata.add(song);
      }
      playlist.songs = songsWithMetadata;
    } else {
      // 检查歌曲列表是否与文件路径列表一致
      if (playlist.songs!.length != playlist.songFilePaths.length) {
        // 重新解析所有歌曲
        final List<Song> songsWithMetadata = [];
        for (final filePath in playlist.songFilePaths) {
          final song = await _parseSongMetadata(filePath);
          songsWithMetadata.add(song);
        }
        playlist.songs = songsWithMetadata;
      } else {
        // 检查文件路径是否匹配
        bool needsUpdate = false;
        for (int i = 0; i < playlist.songFilePaths.length; i++) {
          if (playlist.songs![i].filePath != playlist.songFilePaths[i]) {
            needsUpdate = true;
            break;
          }
        }

        if (needsUpdate) {
          // 重新解析所有歌曲
          final List<Song> songsWithMetadata = [];
          for (final filePath in playlist.songFilePaths) {
            final song = await _parseSongMetadata(filePath);
            songsWithMetadata.add(song);
          }
          playlist.songs = songsWithMetadata;
        }
      }
    }
  }

  // --- 播放控制 ---
  Future<void> play() async {
    if (!_isPlaying) {
      await _mediaPlayer.play(); // 开始播放
      _isPlaying = true; // 立即更新状态

      // 恢复播放跟踪
      PlaybackTracker().resumeTracking();
    }
    await _smtcManager?.updateState(true);
    notifyListeners();
  }

  Future<void> pause() async {
    if (_isPlaying) {
      await _mediaPlayer.pause();
      _isPlaying = false; // 立即更新状态

      // 暂停播放跟踪
      PlaybackTracker().pauseTracking();
    }
    await _smtcManager?.updateState(false);
    notifyListeners();
  }

  Future<void> stop() async {
    await _mediaPlayer.stop();
    _currentSong = null;
    _currentSongIndex = -1;
    _currentLyrics = [];
    _currentLyricLineIndex = -1;
    _currentPosition = Duration.zero;
    _totalDuration = Duration.zero;
    _isPlaying = false;
    await _smtcManager?.updateState(false);
    await _smtcManager?.updateTimeline(
      position: Duration.zero,
      duration: Duration.zero,
    );
  }

  Future<void> setPitch(double pitch) async {
    if (pitch < 0.5 || pitch > 1.5) return;
    _currentPitch = pitch;
    await _mediaPlayer.setPitch(pitch);
    notifyListeners(); // 通知 UI 更新
  }

  Future<void> setPlaybackRate(double rate) async {
    if (rate < 0.5 || rate > 2.0) return;
    _currentPlaybackRate = rate;
    await _mediaPlayer.setRate(rate);
    notifyListeners(); // 通知 UI 更新
  }

  // 根据播放模式播放下一首
  Future<void> _playNextLogic() async {
    // 独立队列
    if (_isUsingQueue &&
        _currentPlayingQueue != null &&
        _currentPlayingQueue!.isNotEmpty) {
      int nextIndex;
      final songCount = _currentPlayingQueue!.length;
      final currentIndex = _currentQueueIndex;

      if (_playMode == PlayMode.shuffle) {
        // 只有在随机索引列表为空或者长度不匹配时才重新生成
        if (_shuffledIndices.length != songCount) {
          _generateShuffledIndices(count: songCount);
        }

        int currentShuffledPos = _shuffledIndices.indexOf(currentIndex);
        // 如果当前歌曲不在随机列表中（异常情况）
        if (currentShuffledPos == -1) {
          // 重新生成随机列表
          _generateShuffledIndices(count: songCount);
          currentShuffledPos = -1; // 从新的随机列表的第一首开始
        }
        // 如果已经播放到列表末尾
        else if (currentShuffledPos == _shuffledIndices.length - 1) {
          // 播放完一轮后重新生成随机列表
          _generateShuffledIndices(count: songCount);
          currentShuffledPos = -1; // 从新的随机列表的第一首开始
        }

        nextIndex =
            _shuffledIndices[(currentShuffledPos + 1) %
                _shuffledIndices.length];
      } else if (_playMode == PlayMode.repeatOne && _isAutoPlaying) {
        // 只有在自动播放且为单曲循环模式时才重复播放当前歌曲
        nextIndex = currentIndex;
      } else {
        // 顺序播放或其他情况（包括手动点击下一首）
        nextIndex = (currentIndex + 1) % songCount;
      }

      _currentQueueIndex = nextIndex; // 更新队列索引
      await _startPlaybackNow();
      return;
    }

    // 否则按原来的逻辑播放
    if (_playingPlaylist == null || _playingPlaylist!.songFilePaths.isEmpty) {
      await stop();
      return;
    }

    int nextIndex;
    final songCount = _playingPlaylist!.songFilePaths.length;
    final currentIndex = _playingSongIndex;

    if (_playMode == PlayMode.shuffle) {
      // 只有在随机索引列表为空或者长度不匹配时才重新生成
      if (_shuffledIndices.length != songCount) {
        _generateShuffledIndices(count: songCount);
      }

      int currentShuffledPos = _shuffledIndices.indexOf(currentIndex);
      // 如果当前歌曲不在随机列表中（异常情况）
      if (currentShuffledPos == -1) {
        // 重新生成随机列表
        _generateShuffledIndices(count: songCount);
        currentShuffledPos = -1; // 从新的随机列表的第一首开始
      }
      // 如果已经播放到列表末尾
      else if (currentShuffledPos == _shuffledIndices.length - 1) {
        // 播放完一轮后重新生成随机列表
        _generateShuffledIndices(count: songCount);
        currentShuffledPos = -1; // 从新的随机列表的第一首开始
      }
      // // 有10%的概率重新生成随机列表
      // else if (_random.nextDouble() < 0.1) {
      //   _generateShuffledIndices(count: songCount);
      //   currentShuffledPos = -1; // 从新的随机列表的第一首开始
      // }

      nextIndex =
          _shuffledIndices[(currentShuffledPos + 1) % _shuffledIndices.length];
    } else if (_playMode == PlayMode.repeatOne && _isAutoPlaying) {
      // 只有在自动播放且为单曲循环模式时才重复播放当前歌曲
      nextIndex = currentIndex;
    } else {
      // 顺序播放或其他情况（包括手动点击下一首）
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
    // 独立队列
    if (_isUsingQueue &&
        _currentPlayingQueue != null &&
        _currentPlayingQueue!.isNotEmpty) {
      int prevIndex;
      final songCount = _currentPlayingQueue!.length;
      final currentIndex = _currentQueueIndex;

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
            _shuffledIndices[(currentShuffledPos - 1) %
                _shuffledIndices.length];
      } else {
        // 顺序播放或其他情况（包括手动点击上一首）
        // `+ songCount` 是为了防止 `currentIndex` 为 0 时出现负数
        prevIndex = (currentIndex - 1 + songCount) % songCount;
      }

      // 更新队列索引
      _currentQueueIndex = prevIndex;
      _isAutoPlaying = false;
      await _startPlaybackNow();
      return;
    }

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
    } else {
      // 顺序播放或其他情况（包括手动点击上一首）
      // `+ songCount` 是为了防止 `currentIndex` 为 0 时出现负数
      prevIndex = (currentIndex - 1 + songCount) % songCount;
    }

    // 更新播放索引
    _playingSongIndex = prevIndex;
    _isAutoPlaying = false;
    await _startPlaybackNow();
  }

  // 这个方法专门用于播放抽屉内的点击事件
  Future<void> playSongFromQueue(int index) async {
    if (_isUsingQueue) {
      // 队列模式下：播放队列中的歌曲
      if (_currentPlayingQueue == null ||
          index < 0 ||
          index >= _currentPlayingQueue!.length) {
        return;
      }

      _currentQueueIndex = index;
      await _startPlaybackNow();
    } else {
      // 歌单模式下：播放当前播放列表中的歌曲
      if (_playingPlaylist == null ||
          _playingPlaylist!.songs == null ||
          index < 0 ||
          index >= _playingPlaylist!.songs!.length) {
        return;
      }

      _playingSongIndex = index;
      await _startPlaybackNow();
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

  void _initQueueFromCurrentPlaylist() {
    if (_playingPlaylist != null && _playingPlaylist!.songs != null) {
      _currentPlayingQueue = List<Song>.from(_playingPlaylist!.songs!);
      _currentPlayingQueueFilePaths = List<String>.from(
        _playingPlaylist!.songFilePaths,
      );
      _currentQueueIndex = _playingSongIndex;
      _isUsingQueue = true;
    }
  }

  // 批量添加歌曲到当前播放队列
  Future<void> addSongsToPlayingQueue(List<Song> songs) async {
    if (songs.isEmpty) return;

    // 如果没有正在播放的歌单，创建一个临时播放列表
    if (_playingPlaylist == null) {
      await playFromDynamicList(songs, 0);
      _infoStreamController.add('已添加 ${songs.length} 首歌曲到播放队列');
      return;
    }

    await _ensurePlaylistSongs(_playingPlaylist!);

    // 初始化
    if (!_isUsingQueue) {
      _initQueueFromCurrentPlaylist();
    }

    int addedCount = 0;
    int skippedCount = 0;

    for (final song in songs) {
      // 检查歌曲是否已经在队列中
      if (!_currentPlayingQueue!.any((s) => s.filePath == song.filePath)) {
        // 将歌曲添加到队列的末尾
        _currentPlayingQueue!.add(song);
        _currentPlayingQueueFilePaths!.add(song.filePath);
        addedCount++;
      } else {
        skippedCount++;
      }
    }

    // 如果当前是随机播放模式，重新生成随机列表
    if (_playMode == PlayMode.shuffle) {
      _generateShuffledIndices(count: _currentPlayingQueue!.length);
    }

    String message = '';
    if (addedCount > 0) {
      message += '已添加 $addedCount 首歌曲到播放队列';
    }
    if (skippedCount > 0) {
      if (message.isNotEmpty) message += '，';
      message += '跳过 $skippedCount 首已在队列中的歌曲';
    }

    if (message.isNotEmpty) {
      _infoStreamController.add(message);
    }

    notifyListeners();
  }

  // 添加歌曲到当前播放队列
  Future<void> addToPlayingQueue(Song song) async {
    await addSongsToPlayingQueue([song]);
  }

  // 添加歌曲到当前播放队列的下一首位置
  Future<void> addToPlayingQueueNext(Song song) async {
    // 如果没有正在播放的歌单，创建一个临时播放列表，只有这首歌
    if (_playingPlaylist == null) {
      await playFromDynamicList([song], 0);
      _infoStreamController.add('已将歌曲设置为下一首：${song.title}');
      return;
    }

    await _ensurePlaylistSongs(_playingPlaylist!);

    // 初始化
    if (!_isUsingQueue) {
      _initQueueFromCurrentPlaylist();
    }

    // 检查歌曲是否已经在队列中
    if (_currentPlayingQueue!.any((s) => s.filePath == song.filePath)) {
      _infoStreamController.add('歌曲已在播放队列中：${song.title}');
      return;
    }

    // 计算下一首播放的位置
    int nextIndex = _currentQueueIndex + 1;
    if (nextIndex < 0) nextIndex = 0; // 如果当前索引无效，则添加到开头

    // 随机模式的处理
    if (_playMode == PlayMode.shuffle) {
      // 添加到队列中
      _currentPlayingQueue!.insert(nextIndex, song);
      _currentPlayingQueueFilePaths!.insert(nextIndex, song.filePath);

      // 重新生成随机列表，但需要确保新添加的歌曲作为下一首播放
      _generateShuffledIndices(count: _currentPlayingQueue!.length);

      // 找到新歌曲在随机列表中的位置
      final int newSongRandomIndex = _shuffledIndices.indexOf(nextIndex);

      // 如果新歌曲不在预期位置，调整随机列表
      if (newSongRandomIndex !=
          _shuffledIndices.indexOf(_currentQueueIndex) + 1) {
        // 移除新歌曲的索引
        _shuffledIndices.remove(nextIndex);
        // 在当前播放歌曲索引之后插入新歌曲索引
        final int currentSongRandomPos = _shuffledIndices.indexOf(
          _currentQueueIndex,
        );
        if (currentSongRandomPos >= 0) {
          _shuffledIndices.insert(currentSongRandomPos + 1, nextIndex);
        } else {
          // 如果当前歌曲不在随机列表中，添加到开头
          _shuffledIndices.insert(0, nextIndex);
        }
      }
    } else {
      // 在非随机模式下，直接插入到指定位置
      _currentPlayingQueue!.insert(nextIndex, song);
      _currentPlayingQueueFilePaths!.insert(nextIndex, song.filePath);
    }

    _infoStreamController.add('已将歌曲设置为下一首：${song.title}');

    notifyListeners();
  }

  // --- 歌曲播放 ---

  // 播放指定索引的歌曲
  Future<void> playSongAtIndex(int index) async {
    // 切换到歌单播放模式，清空独立队列
    _isUsingQueue = false;
    _currentPlayingQueue = null;
    _currentPlayingQueueFilePaths = null;
    _currentQueueIndex = -1;

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
    Song? songToPlay;
    String? songFilePath;

    if (_isUsingQueue &&
        _currentPlayingQueue != null &&
        _currentQueueIndex >= 0) {
      // 使用队列中的歌曲
      if (_currentQueueIndex >= 0 &&
          _currentQueueIndex < _currentPlayingQueue!.length) {
        songFilePath = _currentPlayingQueueFilePaths![_currentQueueIndex];
        songToPlay = await _prepareSongForPlayback(songFilePath);
      }
    } else {
      // 使用原播放列表中的歌曲
      if (_playingSongIndex >= 0 &&
          _playingPlaylist != null &&
          _playingSongIndex < _playingPlaylist!.songFilePaths.length) {
        await _ensurePlaylistSongs(_playingPlaylist!);
        if (_playingPlaylist!.songs != null &&
            _playingSongIndex < _playingPlaylist!.songs!.length) {
          songFilePath = _playingPlaylist!.songFilePaths[_playingSongIndex];
          songToPlay = await _prepareSongForPlayback(songFilePath);
        }
      }
    }

    if (songToPlay == null || songFilePath == null) {
      return;
    }

    _currentSong = songToPlay;

    try {
      await _mediaPlayer.stop();
      _currentLyrics = [];
      _currentLyricLineIndex = -1;

      // media-kit 默认会读取同名字幕文件，包括.lrc
      // 然后不知道为什么又会在错误流抛出读取失败，导致无法播放带有同名 .lrc 的音频文件

      // 这里直接调用底层 mpv 的属性设置
      if (_mediaPlayer.platform is NativePlayer) {
        try {
          await (_mediaPlayer.platform as dynamic).setProperty(
            'sub-auto',
            'no',
          );

          // // 先不设置独占模式，使用默认音频
          // await (_mediaPlayer.platform as dynamic).setProperty('ao', 'wasapi');

          // 监听播放状态，在开始播放后再启用独占模式
          if (_isExclusiveModeEnabled) {
            _enableExclusive();
          }
        } catch (e) {
          //
        }
      }

      await _mediaPlayer.open(Media(songFilePath));

      _loadLyricsForSong(songFilePath);

      // 在 resume 之前更新SMTC元数据
      await _smtcManager?.updateMetadata(
        title: songToPlay.title,
        artist: songToPlay.artist,
        album: songToPlay.album,
        albumArt: songToPlay.albumArt,
      );
      // await dumpCover(songToPlay.albumArt!);
      await _smtcManager?.updateState(true); // 播放状态

      // 提取并应用动态主题色
      extractAndApplyDynamicColor(songToPlay.albumArt);

      // 开始跟踪播放
      PlaybackTracker().startTracking(songToPlay);

      await _mediaPlayer.play(); // 最后执行播放

      // 保存播放状态
      savePlaybackState();

      notifyListeners();
    } catch (e) {
      // 捕获所有播放相关的异常
      // _errorStreamController.add('无法播放${p.basename(songFilePath)}，可能文件已经损坏');
    }
  }

  // 启用独占模式
  void _enableExclusive() {
    // 取消之前的订阅（如果有的话）
    _exclusiveModeSubscription?.cancel();

    // 添加新的订阅
    _exclusiveModeSubscription = _mediaPlayer.stream.playing.listen((
      isPlaying,
    ) async {
      if (isPlaying && _isExclusiveModeEnabled) {
        // 播放开始后，尝试切换到独占模式
        await Future.delayed(const Duration(milliseconds: 500)); // 等待音频稳定

        try {
          await (_mediaPlayer.platform as dynamic).setProperty(
            'audio-exclusive',
            'yes',
          );
        } catch (e) {
          //
        }
      }
    });
  }

  void toggleExclusiveMode(bool? value) {
    if (value == null) return;

    // 只有在播放器处于活跃状态时才能启用
    if (value && !_mediaPlayer.state.playing) {
      _infoStreamController.add('请先开始播放以启用独占模式');
      notifyListeners();
      return;
    }

    _isExclusiveModeEnabled = value;
    _isExclusiveModeAvailable = _mediaPlayer.state.playing;

    if (value && _isExclusiveModeAvailable) {
      // 立即启用独占模式
      _enableExclusiveNow();
    } else if (!value) {
      // 禁用独占模式
      _disableExclusiveMode();
    }

    notifyListeners();
  }

  void _enableExclusiveNow() {
    try {
      (_mediaPlayer.platform as dynamic).setProperty('audio-exclusive', 'yes');
    } catch (e) {
      _errorStreamController.add('启用独占模式失败: $e');
    }
  }

  void _disableExclusiveMode() {
    try {
      (_mediaPlayer.platform as dynamic).setProperty('audio-exclusive', 'no');
    } catch (e) {
      _errorStreamController.add('禁用独占模式失败: $e');
    }
  }

  // 监听播放状态变化，更新独占模式可用性
  void _listenToPlayingState() {
    _mediaPlayer.stream.playing.listen((isPlaying) async {
      _isExclusiveModeAvailable = isPlaying;

      // 如果启用了独占模式且现在开始播放，则启用独占模式
      if (_isExclusiveModeEnabled && isPlaying) {
        await Future.delayed(const Duration(milliseconds: 500));
        _enableExclusiveNow();
      }

      notifyListeners();
    });
  }

  // 加载可用的音频设备
  Future<void> _loadAudioDevices() async {
    try {
      // 监听音频设备变化
      _mediaPlayer.stream.audioDevices.listen((devices) {
        _availableAudioDevices = devices;
        notifyListeners();

        // 如果是第一次获取到设备列表，尝试恢复用户上次的选择
        if (!_hasAttemptedRestore && devices.isNotEmpty) {
          _restoreSavedDevice(devices);
          _hasAttemptedRestore = true; // 标记已执行过恢复
        }
      });

      // 获取当前选择的音频设备
      _mediaPlayer.stream.audioDevice.listen((device) {
        _selectedAudioDevice = device;
        notifyListeners();
      });
    } catch (e) {
      _errorStreamController.add('加载音频设备时出错: $e');
    }
  }

  // 比对并恢复设备
  Future<void> _restoreSavedDevice(List<AudioDevice> devices) async {
    // 如果上次存的是"自动"，或者没有存储记录，则不做操作(默认为auto)
    if (_settingsProvider.audioDeviceIsAuto) {
      // 使用自动音频设备
      await _mediaPlayer.setAudioDevice(AudioDevice.auto());
      return;
    }

    final String? savedName = _settingsProvider.audioDeviceName;
    final String? savedDesc = _settingsProvider.audioDeviceDesc;

    if (savedName == null) return;

    // 遍历当前可用设备列表进行比对
    // 这里比对name和description，比直接对比对象更安全
    try {
      final matchedDevice = devices.firstWhere((device) {
        return device.name == savedName && device.description == savedDesc;
      });

      await _mediaPlayer.setAudioDevice(matchedDevice);
      // 不需要手动设 _selectedAudioDevice，stream.audioDevice 会回调更新
    } catch (e) {
      // firstWhere 没找到会抛出异常，说明上次保存的设备当前不可用
      // 此时不做任何操作，保持auto即可
      _errorStreamController.add('恢复音频设备失败: $e');
      _settingsProvider.setAudioDeviceToAuto();
    }
  }

  // 选择音频设备
  Future<void> selectAudioDevice(AudioDevice device) async {
    try {
      await _mediaPlayer.setAudioDevice(device);
      _selectedAudioDevice = device;
      notifyListeners();

      _settingsProvider.setAudioDevice(device.name, device.description);
    } catch (e) {
      _errorStreamController.add('设置音频设备失败: $e');
    }
  }

  // 使用自动选择音频设备
  Future<void> useAutoAudioDevice() async {
    try {
      await _mediaPlayer.setAudioDevice(AudioDevice.auto());
      _selectedAudioDevice = AudioDevice.auto();
      notifyListeners();

      _settingsProvider.setAudioDeviceToAuto();
    } catch (e) {
      _errorStreamController.add('设置自动音频设备失败: $e');
    }
  }

  // 保存播放状态
  Future<void> savePlaybackState() async {
    // 只有在有播放列表和当前歌曲索引有效时才保存
    if (_playingPlaylist != null &&
        _playingSongIndex >= 0 &&
        _playingPlaylist!.songFilePaths.length > _playingSongIndex) {
      final playbackState = PlaybackState(
        playlistId: _playingPlaylist!.id,
        songIndex: _playingSongIndex,
      );

      await _playlistManager.savePlaybackState(playbackState);
      // 保存播放队列
      await _playlistManager.savePlaybackQueue(_playingPlaylist!.songFilePaths);
    } else {
      // 如果没有有效的播放状态，清除已保存的状态
      await _playlistManager.clearPlaybackState();
      await _playlistManager.clearPlaybackQueue();
    }
  }

  // 恢复播放状态
  Future<void> _restorePlaybackState() async {
    final playbackState = await _playlistManager.loadPlaybackState();
    final playbackQueue = await _playlistManager.loadPlaybackQueue();

    if (playbackState != null) {
      // 查找对应的播放列表
      Playlist? targetPlaylist;
      if (playbackState.playlistId != null) {
        targetPlaylist = _playlists.firstWhere(
          (playlist) => playlist.id == playbackState.playlistId,
          orElse: () => _allSongsVirtualPlaylist,
        );
      } else {
        // 如果没有playlistId，使用全部歌曲播放列表
        targetPlaylist = _allSongsVirtualPlaylist;
      }

      // 如果有保存的播放队列，则使用它更新播放列表
      if (playbackQueue != null) {
        targetPlaylist.songFilePaths = playbackQueue;
      }

      // 检查歌曲索引是否有效
      if (playbackState.songIndex >= 0 &&
          targetPlaylist.songFilePaths.length > playbackState.songIndex) {
        // 设置播放上下文
        _playingPlaylist = targetPlaylist;
        _playingSongIndex = playbackState.songIndex;

        // 确保播放列表的歌曲已被解析
        await _ensurePlaylistSongs(_playingPlaylist!);

        final songFilePath = _playingPlaylist!.songFilePaths[_playingSongIndex];
        _currentSong = await _prepareSongForPlayback(songFilePath);

        // 加载歌词
        _loadLyricsForSong(songFilePath);

        // 更新SMTC元数据
        await _smtcManager?.updateMetadata(
          title: _currentSong!.title,
          artist: _currentSong!.artist,
          albumArt: _currentSong!.albumArt,
        );

        // 提取并应用动态主题色
        extractAndApplyDynamicColor(_currentSong!.albumArt);

        // 将歌曲加载到播放器中，但不自动播放
        try {
          // 检查文件是否存在
          final songFile = File(songFilePath);
          if (await songFile.exists()) {
            await _mediaPlayer.open(
              Media(songFilePath),
              play: false, // 不自动播放
            );

            if (_mediaPlayer.platform is NativePlayer) {
              try {
                await (_mediaPlayer.platform as dynamic).setProperty(
                  'sub-auto',
                  'no',
                );

                // 监听播放状态，在开始播放后再启用独占模式
                if (_isExclusiveModeEnabled) {
                  _enableExclusive();
                }
              } catch (e) {
                //
              }
            }
          } else {
            // 如果文件不存在，清除播放状态
            await _playlistManager.clearPlaybackState();
            await _playlistManager.clearPlaybackQueue();
            _playingPlaylist = null;
            _playingSongIndex = -1;
            _currentSong = null;
            _currentPosition = Duration.zero;
          }
        } catch (e) {
          // 如果加载失败，清除播放状态
          await _playlistManager.clearPlaybackState();
          await _playlistManager.clearPlaybackQueue();
          _playingPlaylist = null;
          _playingSongIndex = -1;
          _currentSong = null;
          _currentPosition = Duration.zero;
        }

        notifyListeners();
      }
    }
  }

  // -- 主题管理 --
  // 提取并应用动态主题色
  Future<void> extractAndApplyDynamicColor(Uint8List? albumArt) async {
    // 检查设置是否启用了动态颜色
    if (!_settingsProvider.useDynamicColor || albumArt == null) {
      return;
    }

    try {
      final colors = await extractColor(
        MemoryImage(albumArt),
        1, // 提取一种主色调
      );
      if (colors.isNotEmpty) {
        final dominantColor = colors[0];
        final color = Color.fromRGBO(
          dominantColor.r,
          dominantColor.g,
          dominantColor.b,
          1.0,
        );

        // 设置主题色
        _themeProvider.setSeedColor(color);
      }
    } catch (e) {
      // print('提取颜色失败 $e');
    }
  }

  // --- 歌曲排序 ---

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

  // 使用指定方式进行排序
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

      String mixedPinyin(String text) {
        final buffer = StringBuffer();
        for (final char in text.characters) {
          final pinyin = PinyinHelper.getPinyin(char);

          // 如果能成功转换成拼音就用拼音，否则保留原字符
          if (pinyin.isNotEmpty && pinyin != char) {
            buffer.write(pinyin);
          } else {
            buffer.write(char.toLowerCase());
          }
        }
        return buffer.toString();
      }

      // 对这个临时列表进行排序
      sortableList.sort((a, b) {
        final songA = a['metadata'] as Song;
        final songB = b['metadata'] as Song;

        final valueA = (criterion == SortCriterion.title
            ? songA.title
            : songA.artist);
        final valueB = (criterion == SortCriterion.title
            ? songB.title
            : songB.artist);

        final mixedA = mixedPinyin(valueA);
        final mixedB = mixedPinyin(valueB);

        final result = mixedA.compareTo(mixedB);
        return descending ? -result : result;
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

    // 如果是随机排序
    if (criterion == SortCriterion.random) {
      final random = Random();
      final randomizedPaths = List<String>.from(paths);
      // dart 自带的列表元素随机排序
      randomizedPaths.shuffle(random);
      return randomizedPaths;
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

    // 同时更新songs列表的顺序
    if (currentPlaylist.songs != null) {
      final songMap = {
        for (final song in currentPlaylist.songs!) song.filePath: song,
      };
      currentPlaylist.songs = sortedPaths
          .map((path) => songMap[path]!)
          .toList();
    }

    await _savePlaylists();

    await _loadCurrentPlaylistSongs();

    notifyListeners();
  }

  // --- 歌词相关 ---

  // 加载指定歌曲的歌词
  Future<void> _loadLyricsForSong(String songFilePath) async {
    _currentLyrics = []; // 清空之前的歌词
    _currentLyricLineIndex = -1; // 重置歌词行索引
    _lyricLineIndexController.add(-1);
    notifyListeners();

    if (_settingsProvider.preferExternalLyrics) {
      // 优先读取外置LRC歌词
      await _loadExternalLyrics(songFilePath);
      if (_currentLyrics.isNotEmpty) {
        return;
      }
      // 内嵌歌词
      await _loadEmbeddedLyrics(songFilePath);
      if (_currentLyrics.isNotEmpty) {
        return;
      }
    } else {
      // 优先读取内嵌歌词
      await _loadEmbeddedLyrics(songFilePath);
      if (_currentLyrics.isNotEmpty) {
        return;
      }
      // 外置歌词
      await _loadExternalLyrics(songFilePath);
      if (_currentLyrics.isNotEmpty) {
        return;
      }
    }

    if (_settingsProvider.enableOnlineLyrics && currentSong != null) {
      _currentLyrics = []; // 清空歌词
      notifyListeners();

      // 根据设置选择主选歌词源
      if (_settingsProvider.primaryLyricSource == 'qq') {
        // 后台异步加载QQ音乐歌词
        _loadQQLyrics(currentSong!.title);
      } else if (_settingsProvider.primaryLyricSource == 'netease') {
        // 后台异步加载网易云音乐歌词
        _loadOnlineLyrics(currentSong!.title);
      } else {
        // 后台异步加载酷狗音乐歌词
        _loadKugouLyrics(currentSong!.title);
      }
    } else {
      _currentLyrics = []; // 确保在不执行网络请求时清空歌词
      notifyListeners();
    }
  }

  Future<void> _loadExternalLyrics(String songFilePath) async {
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
  }

  // 加载内嵌歌词
  Future<void> _loadEmbeddedLyrics(String songFilePath) async {
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

      final metadata = await readAudioInfo(
        path: normalizedPath,
        options: const AudioInfoOptions(
          needCover: false,
          needLyrics: true,
          needAudioProps: false,
        ),
      );

      if (metadata.lyrics != null && metadata.lyrics!.isNotEmpty) {
        final lines = metadata.lyrics!.split(RegExp(r'\r?\n'));
        _currentLyrics = _parseLrcContent(lines);
        notifyListeners();
        return;
      }
    } catch (e) {
      // _errorStreamController.add('加载歌词失败：${p.basename(songFilePath)}');
      // 未能读取到歌词时不提示错误
    }
  }

  // 后台异步加载网易歌词
  Future<void> _loadOnlineLyrics(String songTitle) async {
    try {
      // 检查 artist 是否为默认值，如果是则设置为空字符串
      final rawArtist = _currentSong?.artist ?? '';
      final artist = (rawArtist == '未知歌手' || rawArtist == '未知歌手 (解析失败)')
          ? ''
          : rawArtist;

      // 组合搜索关键词（有歌手时：歌名 + 歌手；否则只用歌名）
      final searchKeyword = artist.isEmpty
          ? songTitle.trim()
          : '${songTitle.trim()} ${artist.trim()}';

      // 对搜索关键词进行 url 编码
      final encodedSearchKeyword = Uri.encodeComponent(searchKeyword);

      // 第一步：搜索歌曲获取歌曲id
      final searchUrl =
          'https://music.163.com/api/search/get/?s=$encodedSearchKeyword&type=1&limit=1';
      final searchUri = Uri.parse(searchUrl);

      final searchResponse = await http
          .get(
            searchUri,
            headers: {
              'Referer': 'https://music.163.com',
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
            },
          )
          .timeout(const Duration(seconds: 10));

      // 如果状态码不为200，清空并返回
      if (searchResponse.statusCode != 200) {
        _currentLyrics = [];
        notifyListeners();
        return;
      }

      // 解析搜索结果
      final searchResult = json.decode(searchResponse.body);

      // 如果没有找到歌曲，同样清空歌词
      if (searchResult['result'] == null ||
          searchResult['result']['songs'] == null ||
          searchResult['result']['songs'].isEmpty) {
        _currentLyrics = [];
        notifyListeners();
        return;
      }

      // 取第一首匹配歌曲的id
      final songId = searchResult['result']['songs'][0]['id'].toString();

      // 第二步：分别获取原文歌词和翻译歌词
      // 获取原文歌词
      final lrcUrl =
          'https://music.163.com/api/song/lyric?os=pc&id=$songId&lv=-1';
      final lrcUri = Uri.parse(lrcUrl);

      final lrcResponse = await http
          .get(
            lrcUri,
            headers: {
              'Referer': 'https://music.163.com',
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
            },
          )
          .timeout(const Duration(seconds: 10));

      // 如果状态码不为200，清空并返回
      if (lrcResponse.statusCode != 200) {
        _currentLyrics = [];
        notifyListeners();
        return;
      }

      final lrcResult = json.decode(lrcResponse.body);

      // 获取翻译歌词
      final tlyricUrl =
          'https://music.163.com/api/song/lyric?os=pc&id=$songId&tv=-1';
      final tlyricUri = Uri.parse(tlyricUrl);

      final tlyricResponse = await http
          .get(
            tlyricUri,
            headers: {
              'Referer': 'https://music.163.com',
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
            },
          )
          .timeout(const Duration(seconds: 10));

      final tlyricResult = json.decode(tlyricResponse.body);

      // 处理原文歌词数据
      List<String> lrcLines = [];
      if (lrcResult['lrc'] != null &&
          lrcResult['lrc']['lyric'] != null &&
          lrcResult['lrc']['lyric'].toString().isNotEmpty) {
        lrcLines = lrcResult['lrc']['lyric'].toString().split('\n');
      }

      // 处理翻译歌词数据
      List<String> tlyricLines = [];
      if (tlyricResult['tlyric'] != null &&
          tlyricResult['tlyric']['lyric'] != null &&
          tlyricResult['tlyric']['lyric'].toString().isNotEmpty) {
        tlyricLines = tlyricResult['tlyric']['lyric'].toString().split('\n');
      }

      // 合并歌词
      final List<String> mergedLyrics = [];
      mergedLyrics.addAll(lrcLines);

      if (tlyricLines.isNotEmpty) {
        mergedLyrics.add(''); // 空行分隔
        mergedLyrics.addAll(tlyricLines);
      }

      // 解析歌词
      _currentLyrics = _parseLrcContent(mergedLyrics);
    } catch (e) {
      _currentLyrics = [];
    }
    notifyListeners();
  }

  // 酷狗歌词获取方法
  Future<void> _loadKugouLyrics(String songTitle) async {
    try {
      // 检查 artist 是否为默认值，如果是则设置为空字符串
      final rawArtist = _currentSong?.artist ?? '';
      final artist = (rawArtist == '未知歌手' || rawArtist == '未知歌手 (解析失败)')
          ? ''
          : rawArtist;

      // 组合搜索关键词（有歌手时：歌名 + 歌手；否则只用歌名）
      final searchKeyword = artist.isEmpty
          ? songTitle.trim()
          : '${songTitle.trim()} ${artist.trim()}';

      // 对搜索关键词进行 url 编码
      final encodedSearchKeyword = Uri.encodeComponent(searchKeyword);

      // 第一步：搜索歌曲获取歌曲hash
      final searchUrl =
          'http://mobilecdnbj.kugou.com/api/v3/search/song?keyword=$encodedSearchKeyword&page=1&pagesize=1';
      final searchUri = Uri.parse(searchUrl);

      final searchResponse = await http
          .get(searchUri)
          .timeout(const Duration(seconds: 10));

      // 如果状态码不为200，清空并返回
      if (searchResponse.statusCode != 200) {
        _currentLyrics = [];
        notifyListeners();
        return;
      }

      // 解析搜索结果
      final searchResult = json.decode(searchResponse.body);

      // 如果没有找到歌曲，同样清空歌词
      if (searchResult['data'] == null ||
          searchResult['data']['info'] == null ||
          searchResult['data']['info'].isEmpty) {
        _currentLyrics = [];
        notifyListeners();
        return;
      }

      // 取第一首匹配歌曲的hash
      final songHash = searchResult['data']['info'][0]['hash'].toString();

      // 第二步：获取歌词候选列表
      final candidatesUrl =
          'https://krcs.kugou.com/search?man=yes&hash=$songHash';
      final candidatesUri = Uri.parse(candidatesUrl);

      final candidatesResponse = await http
          .get(candidatesUri)
          .timeout(const Duration(seconds: 10));

      // 如果状态码不为200，清空并返回
      if (candidatesResponse.statusCode != 200) {
        _currentLyrics = [];
        notifyListeners();
        return;
      }

      final candidatesResult = json.decode(candidatesResponse.body);

      // 检查是否有候选歌词
      if (candidatesResult['candidates'] == null ||
          candidatesResult['candidates'].isEmpty) {
        _currentLyrics = [];
        notifyListeners();
        return;
      }

      // 获取第一个候选歌词的id和accesskey
      final lyricId = candidatesResult['candidates'][0]['id'].toString();
      final accessKey = candidatesResult['candidates'][0]['accesskey']
          .toString();

      // 第三步：获取加密的歌词内容
      final lyricUrl =
          'https://lyrics.kugou.com/download?ver=1&id=$lyricId&accesskey=$accessKey&fmt=lrc';
      final lyricUri = Uri.parse(lyricUrl);

      final lyricResponse = await http
          .get(lyricUri)
          .timeout(const Duration(seconds: 10));

      // 如果状态码不为200，清空并返回
      if (lyricResponse.statusCode != 200) {
        _currentLyrics = [];
        notifyListeners();
        return;
      }

      final lyricResult = json.decode(lyricResponse.body);

      // 检查是否有歌词内容
      if (lyricResult['content'] == null) {
        _currentLyrics = [];
        notifyListeners();
        return;
      }

      // 第四步：解码base64歌词
      final base64Lyric = lyricResult['content'].toString();
      final decodedLyric = utf8.decode(base64Decode(base64Lyric));

      // 解析歌词
      _currentLyrics = _parseLrcContent([decodedLyric]);
    } catch (e) {
      _currentLyrics = [];
    }
    notifyListeners();
  }

  // 企鹅音乐歌词获取方法
  Future<void> _loadQQLyrics(String songTitle) async {
    try {
      // 检查 artist 是否为默认值，如果是则设置为空字符串
      final rawArtist = _currentSong?.artist ?? '';
      final artist = (rawArtist == '未知歌手' || rawArtist == '未知歌手 (解析失败)')
          ? ''
          : rawArtist;

      // 组合搜索关键词（有歌手时：歌手 - 歌名；否则只用歌名）
      final searchKeyword = artist.isEmpty
          ? songTitle.trim()
          : '${artist.trim()} - ${songTitle.trim()}';

      // 第一步：搜索歌曲
      const searchUrl = 'https://u.y.qq.com/cgi-bin/musicu.fcg';
      final searchBody = jsonEncode({
        "comm": {"ct": "19", "cv": "1873", "uin": "0"},
        "music.search.SearchCgiService": {
          "method": "DoSearchForQQMusicDesktop",
          "module": "music.search.SearchCgiService",
          "param": {
            "grp": 1,
            "num_per_page": 40,
            "page_num": 1,
            "query": searchKeyword,
            "search_type": 0,
          },
        },
      });

      final searchRequest = http.Request('POST', Uri.parse(searchUrl))
        ..headers['User-Agent'] =
            'Mozilla/5.0 (compatible; MSIE 9.0; Windows NT 6.1; WOW64; Trident/5.0)'
        ..body = searchBody;

      final searchStreamedResponse = await http.Client().send(searchRequest);
      final searchResponse = await http.Response.fromStream(
        searchStreamedResponse,
      );

      if (searchResponse.statusCode != 200) {
        _currentLyrics = [];
        notifyListeners();
        return;
      }

      // 直接使用bodyBytes避免Content-Type解析问题
      final searchResult = json.decode(utf8.decode(searchResponse.bodyBytes));

      // 检查搜索结果
      if (searchResult['music.search.SearchCgiService'] == null ||
          searchResult['music.search.SearchCgiService']['data'] == null ||
          searchResult['music.search.SearchCgiService']['data']['body'] ==
              null ||
          searchResult['music.search.SearchCgiService']['data']['body']['song'] ==
              null ||
          searchResult['music.search.SearchCgiService']['data']['body']['song']['list'] ==
              null ||
          searchResult['music.search.SearchCgiService']['data']['body']['song']['list']
              .isEmpty) {
        _currentLyrics = [];
        notifyListeners();
        return;
      }

      // 获取第一首歌曲的信息
      final songList =
          searchResult['music.search.SearchCgiService']['data']['body']['song']['list'];
      final firstSong = songList[0];
      final songMid = firstSong['mid'].toString();
      final musicId = firstSong['id'].toString();

      // 第二步：获取歌词
      final lyricUrl = Uri.parse(
        'https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg'
        '?songmid=$songMid'
        '&musicid=$musicId'
        '&format=json'
        '&g_tk=5381',
      );

      final lyricRequest = http.Request('GET', lyricUrl)
        ..headers['Referer'] = 'https://y.qq.com/n/ryqq/player'
        ..headers['User-Agent'] =
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/102.0.5005.63 Safari/537.36';

      final lyricStreamedResponse = await http.Client().send(lyricRequest);
      final lyricResponse = await http.Response.fromStream(
        lyricStreamedResponse,
      );

      if (lyricResponse.statusCode != 200) {
        _currentLyrics = [];
        notifyListeners();
        return;
      }

      // 手动处理响应体，避免因Content-Type导致的解析问题
      final lyricResult = json.decode(utf8.decode(lyricResponse.bodyBytes));

      // 处理歌词内容
      List<String> lrcLines = [];
      if (lyricResult['lyric'] != null) {
        try {
          final lyricBase64 = lyricResult['lyric'];
          final lyricData = utf8.decode(base64Decode(lyricBase64));
          lrcLines = lyricData.split('\n');
        } catch (e) {
          //
        }
      }

      // 处理翻译歌词内容
      List<String> tlyricLines = [];
      if (lyricResult['trans'] != null && lyricResult['trans'].isNotEmpty) {
        try {
          final transBase64 = lyricResult['trans'];
          final transData = utf8.decode(base64Decode(transBase64));
          tlyricLines = transData.split('\n');
        } catch (e) {
          //
        }
      }

      // 合并歌词
      final List<String> mergedLyrics = [];
      mergedLyrics.addAll(lrcLines);

      if (tlyricLines.isNotEmpty) {
        mergedLyrics.add(''); // 空行分隔
        mergedLyrics.addAll(tlyricLines);
      }

      // 解析歌词
      _currentLyrics = _parseLrcContent(mergedLyrics);
    } catch (e) {
      _currentLyrics = [];
    }
    notifyListeners();
  }

  // 解析歌词
  List<LyricLine> _parseLrcContent(List<String> lines) {
    // 检查是否有awlrc标签，如果有则优先使用awlrc解析的结果
    final awlrcResult = _checkAndParseAwlrcFirst(lines);
    if (awlrcResult != null) {
      return awlrcResult;
    }

    final Map<Duration, List<String>> groupedLyrics = {};
    final Map<Duration, List<List<LyricToken>>> karaokeTokenMap = {};

    // 兼容不带毫秒的时间戳格式（到底是谁在用这种）
    final RegExp timeStampRegExp = RegExp(
      r'\[(\d{1,2}):(\d{2})[.:](\d{1,3})\](.*)',
    );

    for (final line in lines) {
      final matches = timeStampRegExp.allMatches(line);

      // 跳过无时间戳的行
      if (matches.isEmpty) {
        continue;
      }

      // 只处理每行的第一个时间戳作为该行的起始时间
      // 行内后续的时间戳会被 _parseKaraokeTokens 识别为逐字标记
      final match = matches.first;

      try {
        final int minutes = int.parse(match.group(1)!);
        final int seconds = int.parse(match.group(2)!);
        // 处理可选的毫秒部分
        final int milliseconds = match.group(3) != null
            ? int.parse(match.group(3)!.padRight(3, '0'))
            : 0;
        final Duration timestamp = Duration(
          minutes: minutes,
          seconds: seconds,
          milliseconds: milliseconds,
        );

        // 获取歌词内容
        final String rawText = match.group(4)!.trim();

        // 检查是否为逐字歌词格式
        if (_isKaraokeLyric(rawText)) {
          final tokens = _parseKaraokeTokens(rawText, timestamp);
          final displayText = _extractDisplayText(rawText);

          if (displayText.isNotEmpty) {
            // 添加到对应时间戳的文本列表中
            groupedLyrics.putIfAbsent(timestamp, () => []).add(displayText);
          }

          // 将当前行的tokens添加到列表中，而不是覆盖
          // 这样可以支持多行共享同一时间戳的逐字歌词
          if (tokens.isNotEmpty) {
            karaokeTokenMap.putIfAbsent(timestamp, () => []).add(tokens);
          }
        } else {
          // 清除普通歌词里的时间标记（ <> [] () ）
          // 这里是为了解析逐字歌词失败时不被时间标记所污染
          final String cleanedText = rawText.replaceAll(
            RegExp(
              r'(<\d{2}:\d{2}\.\d{2,3}>|\[\d{2}:\d{2}\.\d{2,3}\]|\(\d{2}:\d{2}\.\d{2,3}\))',
            ),
            '',
          );

          if (cleanedText.isEmpty) continue;
          groupedLyrics.putIfAbsent(timestamp, () => []).add(cleanedText);
        }
      } catch (e) {
        _errorStreamController.add('无法解析当前歌词');
      }
    }

    final List<LyricLine> parsedLyrics =
        groupedLyrics.entries
            .map(
              (entry) => LyricLine(
                timestamp: entry.key,
                texts: entry.value,
                tokens: karaokeTokenMap[entry.key],
              ),
            )
            .toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return parsedLyrics;
  }

  List<LyricLine>? _checkAndParseAwlrcFirst(List<String> lines) {
    for (final line in lines) {
      if (line.startsWith('[awlrc:')) {
        final RegExp awlrcRegExp = RegExp(r'\[awlrc:(.*?)\]');
        final match = awlrcRegExp.firstMatch(line);
        if (match != null) {
          final content = match.group(1)!;
          final parts = content.split(',');

          for (final part in parts) {
            if (part.startsWith('awlrc:')) {
              // 包含awlrc.awlrc字段才进入LX的歌词解析逻辑
              // 因为不包含的已经有普通的lrc 没必要再解析一次
              return _parseAwlrcContent(lines);
            }
          }
        }
      }
    }
    // 返回null表示继续使用普通解析逻辑
    return null;
  }

  // 解析包含awlrc标签的歌词内容
  List<LyricLine> _parseAwlrcContent(List<String> lines) {
    final Map<Duration, List<String>> groupedLyrics = {};
    final Map<Duration, List<List<LyricToken>>> karaokeTokenMap = {};

    final List<String> processedLines = _preprocessLrcLines(lines);

    // 兼容不带毫秒的时间戳格式（到底是谁在用这种）
    final RegExp timeStampRegExp = RegExp(
      r'\[(\d{1,2}):(\d{2})[.:](\d{1,3})\](.*)',
    );

    for (final line in processedLines) {
      final matches = timeStampRegExp.allMatches(line);

      // 跳过无时间戳的行
      if (matches.isEmpty) {
        continue;
      }

      // 只处理每行的第一个时间戳作为该行的起始时间
      // 行内后续的时间戳会被 _parseKaraokeTokens 识别为逐字标记
      final match = matches.first;

      try {
        final int minutes = int.parse(match.group(1)!);
        final int seconds = int.parse(match.group(2)!);
        // 处理可选的毫秒部分
        final int milliseconds = match.group(3) != null
            ? int.parse(match.group(3)!.padRight(3, '0'))
            : 0;
        final Duration timestamp = Duration(
          minutes: minutes,
          seconds: seconds,
          milliseconds: milliseconds,
        );

        // 获取歌词内容
        final String rawText = match.group(4)!.trim();

        // 检查是否为逐字歌词格式
        if (_isKaraokeLyric(rawText)) {
          final tokens = _parseKaraokeTokens(rawText, timestamp);
          final displayText = _extractDisplayText(rawText);

          if (displayText.isNotEmpty) {
            // 添加到对应时间戳的文本列表中
            groupedLyrics.putIfAbsent(timestamp, () => []).add(displayText);
          }

          // 将当前行的tokens添加到列表中，而不是覆盖
          // 这样可以支持多行共享同一时间戳的逐字歌词
          if (tokens.isNotEmpty) {
            karaokeTokenMap.putIfAbsent(timestamp, () => []).add(tokens);
          }
        } else {
          // 清除普通歌词里的时间标记（ <> [] () ）
          // 这里是为了解析逐字歌词失败时不被时间标记所污染
          final String cleanedText = rawText.replaceAll(
            RegExp(
              r'(<\d{2}:\d{2}\.\d{2,3}>|\[\d{2}:\d{2}\.\d{2,3}\]|\(\d{2}:\d{2}\.\d{2,3}\))',
            ),
            '',
          );

          if (cleanedText.isEmpty) continue;
          groupedLyrics.putIfAbsent(timestamp, () => []).add(cleanedText);
        }
      } catch (e) {
        _errorStreamController.add('无法解析当前歌词');
      }
    }

    final List<LyricLine> parsedLyrics =
        groupedLyrics.entries
            .map(
              (entry) => LyricLine(
                timestamp: entry.key,
                texts: entry.value,
                tokens: karaokeTokenMap[entry.key],
              ),
            )
            .toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return parsedLyrics;
  }

  // 预处理LRC行，处理awlrc标签
  List<String> _preprocessLrcLines(List<String> lines) {
    final List<String> result = [];
    final List<String> awlrcLines = [];

    for (final line in lines) {
      if (line.startsWith('[awlrc:')) {
        awlrcLines.addAll(_parseAwlrcTag(line));
      } else {
        // 普通行直接跳过（因为awlrc优先级最高，会替换其他歌词）
        continue;
      }
    }

    // 将awlrc解析后的内容添加到结果中
    result.addAll(awlrcLines);

    return result;
  }

  // 解析awlrc标签
  List<String> _parseAwlrcTag(String tagLine) {
    final List<String> result = [];

    // 匹配awlrc标签格式
    final RegExp awlrcRegExp = RegExp(r'\[awlrc:(.*?)\]');
    final match = awlrcRegExp.firstMatch(tagLine);

    if (match != null) {
      final content = match.group(1)!;
      final parts = content.split(',');

      final Map<String, String> partsMap = {};
      for (final part in parts) {
        final colonIndex = part.indexOf(':');
        if (colonIndex > 0) {
          final key = part.substring(0, colonIndex);
          final value = part.substring(colonIndex + 1);
          partsMap[key] = value;
        }
      }

      // 处理LX的逐字歌词(awlrc.awlrc)
      if (partsMap.containsKey('awlrc')) {
        final awlrcContent = partsMap['awlrc']!;
        try {
          final decodedContent = utf8.decode(base64Decode(awlrcContent));
          result.addAll(_convertLxLyricsToStandardFormat(decodedContent));
        } catch (e) {
          //
        }
      }

      // 处理翻译歌词(awlrc.tlrc)
      if (partsMap.containsKey('tlrc')) {
        final tlrcContent = partsMap['tlrc']!;
        try {
          final decodedContent = utf8.decode(base64Decode(tlrcContent));
          result.addAll(decodedContent.split('\n'));
        } catch (e) {
          //
        }
      }

      // 处理罗马音歌词(awlrc.rlrc)
      if (partsMap.containsKey('rlrc')) {
        final rlrcContent = partsMap['rlrc']!;
        try {
          final decodedContent = utf8.decode(base64Decode(rlrcContent));
          result.addAll(decodedContent.split('\n'));
        } catch (e) {
          //
        }
      }
    }

    // 不需要普通歌词(awlrc.lrc) 因为LX的逐字歌词(awlrc.awlrc)已经包含了
    // 对于没有LX的逐字歌词(awlrc.awlrc)的情况 仍然不需要普通歌词(awlrc.lrc)
    // 因为普通lrc已经包含了歌词

    return result;
  }

  // 将LX格式的歌词转换为标准格式
  List<String> _convertLxLyricsToStandardFormat(String lxLyrics) {
    final List<String> result = [];
    final lines = lxLyrics.split('\n');

    for (final line in lines) {
      // 格式：[分钟:秒.毫秒]<开始时间（基于该句）,持续时间>歌词文字
      // 例如：[00:10.124]<0,248>嫌<248,313>菜<561,288>煮<849,296>了
      final RegExp lxLyricsRegExp = RegExp(
        r'\[(\d{2}):(\d{2})\.(\d{1,3})\](.*)',
      );
      final match = lxLyricsRegExp.firstMatch(line);

      if (match != null) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        // 处理不足3位的毫秒数，例如 40->400
        final millisecondsStr = match.group(3)!.padRight(3, '0');
        final milliseconds = int.parse(millisecondsStr);
        final content = match.group(4)!;

        final baseTimestamp = Duration(
          minutes: minutes,
          seconds: seconds,
          milliseconds: milliseconds,
        );

        // 解析歌词内容部分，格式为<开始时间,持续时间>文字
        final RegExp timeTagRegExp = RegExp(r'<(\d+),(\d+)>');
        final timeMatches = timeTagRegExp.allMatches(content).toList();

        if (timeMatches.isNotEmpty) {
          // 生成转换后的时间戳格式，用于逐字歌词
          String convertedLine = '[${_formatTime(baseTimestamp)}]';

          for (int i = 0; i < timeMatches.length; i++) {
            final timeMatch = timeMatches[i];
            final relativeStart = int.parse(timeMatch.group(1)!);
            final durationMs = int.parse(timeMatch.group(2)!);

            final absoluteStart =
                baseTimestamp + Duration(milliseconds: relativeStart);

            final textStart = timeMatch.end;
            int textEnd = content.length;

            // 下一个时间标记的开始位置作为当前文字的结束位置
            for (final nextMatch in timeMatches) {
              if (nextMatch.start > timeMatch.start) {
                textEnd = nextMatch.start;
                break;
              }
            }

            final String text = content.substring(textStart, textEnd);

            convertedLine += '<${_formatTime(absoluteStart)}>$text';

            // 最后一个词另外补一个时间戳
            if (i == timeMatches.length - 1) {
              final absoluteEnd =
                  absoluteStart + Duration(milliseconds: durationMs);
              convertedLine += '<${_formatTime(absoluteEnd)}>';
            }
          }

          result.add(convertedLine);
        } else {
          result.add(line);
        }
      } else {
        result.add(line);
      }
    }

    return result;
  }

  // 格式化时间为[mm:ss.mmm]格式
  String _formatTime(Duration duration) {
    final int totalSeconds = duration.inSeconds;
    final int minutes = totalSeconds ~/ 60;
    final int seconds = totalSeconds % 60;
    final int milliseconds = duration.inMilliseconds % 1000;

    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}.${milliseconds.toString().padLeft(3, '0')}';
  }

  // 检测是否为逐字歌词格式
  bool _isKaraokeLyric(String text) {
    if (RegExp(r'<\d+:\d+').hasMatch(text)) return true;
    return RegExp(r'\[\d{2}:\d{2}(\.\d+)?\]').hasMatch(text);
  }

  // 从逐字歌词中提取显示文本
  String _extractDisplayText(String rawText) {
    // 移除所有时间戳标记，保留纯文本内容
    return rawText
        .replaceAll(
          RegExp(
            r'<\d{2}:\d{2}\.\d{2,3}>|\[\d{2}:\d{2}\.\d{2,3}\]|\(\d{2}:\d{2}\.\d{2,3}\)',
          ),
          '',
        )
        .trim();
  }

  List<LyricToken> _parseKaraokeTokens(String rawText, Duration lineStart) {
    final List<LyricToken> tokens = [];

    final RegExp inline = RegExp(r'<(\d{2}):(\d{2})\.(\d{2,3})>');
    final RegExp bracket = RegExp(r'\[(\d{2}):(\d{2})\.(\d{2,3})\]');

    final matches = <Match>[
      ...inline.allMatches(rawText),
      ...bracket.allMatches(rawText),
    ]..sort((a, b) => a.start.compareTo(b.start));

    // 如果只有一个时间戳，将整行作为一个持续500ms的token
    if (matches.length == 1) {
      final displayText = _extractDisplayText(rawText);
      if (displayText.isNotEmpty) {
        tokens.add(
          LyricToken(
            text: displayText,
            start: lineStart,
            end: lineStart + const Duration(milliseconds: 500),
          ),
        );
      }
      return tokens;
    }

    Duration? pendingStart = lineStart;
    int lastIndex = 0;

    for (final match in matches) {
      final text = rawText.substring(lastIndex, match.start);
      final time = _parseTimestamp(match);

      if (text.isNotEmpty) {
        // 前置时间戳：text的start在pendingStart
        tokens.add(
          LyricToken(
            text: text,
            start: pendingStart!,
            end: time, // 暂定为end
          ),
        );
        pendingStart = time;
      } else {
        // 后置时间戳：给上一个token补end
        if (tokens.isNotEmpty) {
          final last = tokens.removeLast();
          tokens.add(LyricToken(text: last.text, start: last.start, end: time));
        } else {
          // 行首时间戳
          pendingStart = time;
        }
      }

      lastIndex = match.end;
    }

    // 处理最后一段文本
    if (lastIndex < rawText.length) {
      final text = rawText.substring(lastIndex);
      if (text.isNotEmpty) {
        tokens.add(
          LyricToken(
            text: text,
            start: pendingStart!,
            end: Duration.zero, // 暂空
          ),
        );
      }
    }

    // 统一补 end
    for (int i = 0; i < tokens.length; i++) {
      if (tokens[i].end == Duration.zero) {
        if (i + 1 < tokens.length) {
          tokens[i] = LyricToken(
            text: tokens[i].text,
            start: tokens[i].start,
            end: tokens[i + 1].start,
          );
        } else {
          tokens[i] = LyricToken(
            text: tokens[i].text,
            start: tokens[i].start,
            end: _fallbackEndForToken(tokens[i].start),
          );
        }
      }
    }

    return tokens;
  }

  // 统一解析 match 中的时间
  Duration _parseTimestamp(Match match) {
    final minutes = int.parse(match.group(1)!);
    final seconds = int.parse(match.group(2)!);
    final millisecondsStr = match.group(3)!;
    final milliseconds = int.parse(millisecondsStr.padRight(3, '0'));
    return Duration(
      minutes: minutes,
      seconds: seconds,
      milliseconds: milliseconds,
    );
  }

  // 为token提供一个合理的结束时间fallback
  Duration _fallbackEndForToken(Duration start) {
    return start +
        const Duration(milliseconds: 500); // 使用token开始时间+500ms作为默认持续时间
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

    // // 如果当前是暂停状态，则开始播放
    // if (!_isPlaying) {
    //   _mediaPlayer.play();
    // }

    if (newIndex != _currentLyricLineIndex) {
      _currentLyricLineIndex = newIndex;
      _lyricLineIndexController.add(newIndex); // 广播新索引
    }
  }

  // --- 对选中歌曲的一些操作 ---

  // 删除选定的歌曲
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
    _infoStreamController.add('已删除歌曲：${songToRemove.title}');
    await _loadCurrentPlaylistSongs();

    await _updateAllSongsList();

    await _savePlaylists();
  }

  // 同上,适用于全部歌曲页面
  Future<void> removeSongFromAllPlaylists(
    String filePath, {
    required String songTitle,
  }) async {
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
    _infoStreamController.add('已删除歌曲：$songTitle');
    await _loadCurrentPlaylistSongs();

    notifyListeners();
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
    _infoStreamController.add('已将歌曲“${songToMove.title}”置于顶部');

    await _playlistManager.savePlaylists(_playlists);
    await _smtcManager?.updateState(false);
    notifyListeners();
  }

  // --- 多选相关 ---

  // 进入多选模式
  void enterMultiSelectMode() {
    if (_isMultiSelectMode) return;
    _isMultiSelectMode = true;
    _selectedSongPaths.clear();
    notifyListeners();
  }

  // 退出多选模式
  void exitMultiSelectMode() {
    if (!_isMultiSelectMode) return;
    _isMultiSelectMode = false;
    _selectedSongPaths.clear();
    notifyListeners();
  }

  // 切换歌曲的选中状态
  void toggleSongSelection(Song song) {
    if (!_isMultiSelectMode) return;

    if (_selectedSongPaths.contains(song.filePath)) {
      _selectedSongPaths.remove(song.filePath);
    } else {
      _selectedSongPaths.add(song.filePath);
    }
    notifyListeners();
  }

  // 删除选中的歌曲
  Future<void> removeSelectedSongs() async {
    if (!_isMultiSelectMode) return;
    if (_selectedSongPaths.isEmpty) return;
    if (_selectedIndex < 0 || _selectedIndex >= _playlists.length) return;

    final currentPlaylist = _playlists[_selectedIndex];

    // // 检查是否是基于文件夹的播放列表
    // if (currentPlaylist.isFolderBased) {
    //   _infoStreamController.add('基于文件夹歌单不支持删除歌曲');
    //   return;
    // }

    final selectedSongs = _currentPlaylistSongs
        .where((song) => _selectedSongPaths.contains(song.filePath))
        .toList();

    // 从当前播放列表中移除选中的歌曲
    for (final song in selectedSongs) {
      currentPlaylist.songFilePaths.remove(song.filePath);

      // 如果删除的是正在播放的歌曲
      if (_currentSong?.filePath == song.filePath &&
          _playingPlaylist?.id == currentPlaylist.id) {
        await stop(); // 直接停止
      }
    }

    _infoStreamController.add('已删除 ${selectedSongs.length} 首歌曲');

    // 清空选中状态
    _selectedSongPaths.clear();
    _isMultiSelectMode = false;

    // 重新加载当前播放列表
    await _loadCurrentPlaylistSongs();
    await _updateAllSongsList();

    await _savePlaylists();
  }

  // 全选所有歌曲
  void selectAllSongs() {
    if (!_isMultiSelectMode) return;

    _selectedSongPaths.clear();
    for (final song in _currentPlaylistSongs) {
      _selectedSongPaths.add(song.filePath);
    }
    notifyListeners();
  }

  // 取消选择所有歌曲
  void deselectAllSongs() {
    if (!_isMultiSelectMode) return;

    _selectedSongPaths.clear();
    notifyListeners();
  }

  // 直接添加歌曲到指定歌单（通过路径列表）
  Future<void> addSongsToPlaylist(
    int playlistIndex,
    List<String> songPaths,
  ) async {
    if (playlistIndex < 0 || playlistIndex >= _playlists.length) {
      _errorStreamController.add('无效的歌单索引');
      return;
    }

    final targetPlaylist = _playlists[playlistIndex];

    // 检查是否是基于文件夹的播放列表
    if (targetPlaylist.isFolderBased) {
      _infoStreamController.add('基于文件夹的歌单不支持手动添加歌曲');
      return;
    }

    // 过滤掉已经存在于目标歌单中的歌曲
    final newSongPaths = songPaths
        .where((path) => !targetPlaylist.songFilePaths.contains(path))
        .toList();

    if (newSongPaths.isEmpty) {
      _infoStreamController.add('所选歌曲已存在于目标歌单中');
      return;
    }

    // 添加新歌曲到目标歌单
    targetPlaylist.songFilePaths.addAll(newSongPaths);

    // 如果目标歌单已经解析过歌曲，则同时解析并添加新歌曲
    if (targetPlaylist.songs != null) {
      final List<Song> newSongs = [];
      for (final path in newSongPaths) {
        final song = await _parseSongMetadata(path);
        newSongs.add(song);
      }
      targetPlaylist.songs!.addAll(newSongs);
    }

    // 保存播放列表
    await _savePlaylists();

    // 如果目标歌单是当前选中的歌单，则更新UI
    if (_selectedIndex == playlistIndex) {
      await _loadCurrentPlaylistSongs();
    }

    // 更新所有歌曲列表
    await _updateAllSongsList();

    // 计算被排除的歌曲数量
    final excludedCount = songPaths.length - newSongPaths.length;
    final message = excludedCount > 0
        ? '成功添加 ${newSongPaths.length} 首歌曲到歌单"${targetPlaylist.name}"（已排除 $excludedCount 首重复歌曲）'
        : '成功添加 ${newSongPaths.length} 首歌曲到歌单"${targetPlaylist.name}"';

    _infoStreamController.add(message);
  }

  // -------

  // 这个方法是专门给歌曲详情页用的
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
      final metadata = await readAudioInfo(
        path: normalizedPath,
        options: const AudioInfoOptions(
          needCover: true,
          needLyrics: false,
          needAudioProps: true,
        ),
      );
      final stat = await file.stat();

      final Uint8List? albumArtBytes = metadata.cover;

      return SongDetails(
        title: metadata.title ?? p.basenameWithoutExtension(filePath),
        artist: metadata.artist ?? '未知歌手',
        album: metadata.album ?? '未知专辑',
        duration: metadata.durationMs != null
            ? Duration(milliseconds: metadata.durationMs!.toInt())
            : Duration.zero,
        albumArt: albumArtBytes,
        bitrate: metadata.bitrate,
        sampleRate: metadata.sampleRate,
        filePath: filePath,
        created: stat.type == FileSystemEntityType.file ? stat.changed : null,
        modified: stat.type == FileSystemEntityType.file ? stat.modified : null,
      );
    } catch (e) {
      _errorStreamController.add('读取歌曲详情失败：${p.basename(filePath)}');
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

  // --- 上下文管理 ---

  void setActiveArtistView(String artistName) {
    _currentDetailViewContext = DetailViewContext.artist;
    _activeDetailTitle = artistName;
    _activeSongList = List<Song>.from(songsByArtist[artistName] ?? []);

    // 应用持久化排序
    final savedOrder = _artistSortOrders[artistName];
    if (savedOrder != null) {
      // 如果存在已保存的顺序，就按这个顺序重新排列歌曲列表
      final songMap = {for (final song in _activeSongList) song.filePath: song};
      // 过滤掉已不存在的歌曲路径，并按保存的顺序排列
      _activeSongList = savedOrder
          .map((path) => songMap[path])
          .where((song) => song != null)
          .cast<Song>()
          .toList();
    }

    if (_isSearching) stopSearch();
    notifyListeners();
  }

  void setActiveAlbumView(String albumName) {
    _currentDetailViewContext = DetailViewContext.album;
    _activeDetailTitle = albumName;
    _activeSongList = List<Song>.from(songsByAlbum[albumName] ?? []);

    // 应用持久化排序
    final savedOrder = _albumSortOrders[albumName];
    if (savedOrder != null) {
      final songMap = {for (final song in _activeSongList) song.filePath: song};
      _activeSongList = savedOrder
          .map((path) => songMap[path])
          .where((song) => song != null)
          .cast<Song>()
          .toList();
    }

    if (_isSearching) stopSearch();
    notifyListeners();
  }

  // 进入全部歌曲页面时调用
  void setActiveAllSongsView() {
    _currentDetailViewContext = DetailViewContext.allSongs;
    // 进入新视图时，如果正在搜索，则停止上一个视图的搜索
    if (_isSearching) {
      stopSearch();
    }
    notifyListeners();
  }

  // 返回到主播放列表视图时调用
  void clearActiveDetailView() {
    _currentDetailViewContext = DetailViewContext.playlist;
    _activeDetailTitle = '';
    _activeSongList = [];
    if (_isSearching) {
      stopSearch();
    }
    notifyListeners();
  }

  // 为歌手/专辑详情页提供排序的功能
  Future<void> sortActiveSongList({
    required SortCriterion criterion,
    required bool descending,
  }) async {
    // 确保当前视图是歌手或专辑，否则直接返回
    if (_currentDetailViewContext != DetailViewContext.artist &&
        _currentDetailViewContext != DetailViewContext.album) {
      return;
    }

    if (_activeSongList.isEmpty) {
      return;
    }

    final sortedPaths = await _sortFilePaths(
      paths: _activeSongList.map((s) => s.filePath).toList(),
      criterion: criterion,
      descending: descending,
    );

    // 根据排好序的路径，更新内存中的_activeSongList
    final Map<String, Song> songMap = {
      for (final s in _activeSongList) s.filePath: s,
    };
    _activeSongList = sortedPaths.map((path) => songMap[path]!).toList();

    if (_currentDetailViewContext == DetailViewContext.artist) {
      // 如果当前是歌手视图，更新歌手排序 Map
      _artistSortOrders[_activeDetailTitle] = sortedPaths;

      await _playlistManager.saveArtistSortOrders(_artistSortOrders);
    } else if (_currentDetailViewContext == DetailViewContext.album) {
      // 如果当前是专辑视图，更新专辑排序 Map
      _albumSortOrders[_activeDetailTitle] = sortedPaths;

      await _playlistManager.saveAlbumSortOrders(_albumSortOrders);
    }

    notifyListeners();
  }

  // 清理无效的排序数据（指向不存在歌曲的路径）
  void _cleanupInvalidSortingData() {
    final validPaths = _allSongs.map((song) => song.filePath).toSet();

    // 清理专辑排序数据
    final albumsToRemove = <String>[];
    _albumSortOrders.forEach((albumName, paths) {
      paths.removeWhere((path) => !validPaths.contains(path));
      // 如果排序列表为空，则移除该专辑的排序数据
      if (paths.isEmpty) {
        albumsToRemove.add(albumName);
      }
    });
    for (final albumName in albumsToRemove) {
      _albumSortOrders.remove(albumName);
    }

    // 清理歌手排序数据
    final artistsToRemove = <String>[];
    _artistSortOrders.forEach((artistName, paths) {
      paths.removeWhere((path) => !validPaths.contains(path));
      // 如果排序列表为空，则移除该歌手的排序数据
      if (paths.isEmpty) {
        artistsToRemove.add(artistName);
      }
    });
    for (final artistName in artistsToRemove) {
      _artistSortOrders.remove(artistName);
    }

    // 保存清理后的排序数据
    _playlistManager.saveAlbumSortOrders(_albumSortOrders);
    _playlistManager.saveArtistSortOrders(_artistSortOrders);
  }

  Future<void> playFromDynamicList(List<Song> songs, int startIndex) async {
    // 确保索引有效
    if (startIndex < 0 || startIndex >= songs.length) {
      return;
    }

    final dynamicPlaylist = Playlist(
      // 使用时间戳确保ID的唯一性，避免与现有歌单冲突
      id: 'dynamic-playlist-${DateTime.now().millisecondsSinceEpoch}',
      name: '动态播放列表',
      // 将 List<Song> 转换为播放器需要的 List<String>
      songFilePaths: songs.map((s) => s.filePath).toList(),
    );

    // 设置播放上下文为这个新创建的临时歌单
    _playingPlaylist = dynamicPlaylist;
    _playingSongIndex = startIndex;

    notifyListeners();

    // 所有后续的播放逻辑都将在这个临时歌单上进行
    await _startPlaybackNow();
  }

  // --- 分组歌曲 ---

  // 多歌手识别与分组
  Map<String, List<Song>> get songsByArtist {
    final Map<String, List<Song>> grouped = {};

    // 使用自定义的分隔符
    final separators = _settingsProvider.artistSeparators;
    // 增强验证，过滤掉无效分隔符
    final validSeparators = separators
        .where(
          (separator) => separator.isNotEmpty && separator.trim().isNotEmpty,
        )
        .toList();

    if (validSeparators.isNotEmpty) {
      final pattern = validSeparators.map((s) => RegExp.escape(s)).join('|');
      final RegExp separatorRegExp = RegExp('[$pattern]');

      // 遍历所有歌曲
      for (final song in _allSongs) {
        // 1. 使用正则表达式拆分 artist 字符串
        final individualArtists = song.artist
            .split(separatorRegExp)
            // 2. 对拆分后的每个名字进行处理，去除首尾的空格
            .map((artist) => artist.trim())
            // 3. 过滤掉因连续分隔符而产生的空字符串
            .where((artist) => artist.isNotEmpty)
            .toList();

        // 如果拆分后没有有效的歌手名 则直接使用原始字段作为唯一的歌手名
        if (individualArtists.isEmpty) {
          if (song.artist.isNotEmpty) {
            individualArtists.add(song.artist);
          } else {
            // 如果字段为空 则归类到未知歌手
            individualArtists.add('未知歌手');
          }
        }

        // 遍历拆分出的每一个独立歌手名
        for (final artistName in individualArtists) {
          // 将当前歌曲添加到这位歌手的列表中
          grouped.putIfAbsent(artistName, () => []).add(song);
        }
      }
    } else {
      // 如果没有有效的分隔符，则不进行拆分
      for (final song in _allSongs) {
        final artistName = song.artist.isNotEmpty ? song.artist : '未知歌手';
        grouped.putIfAbsent(artistName, () => []).add(song);
      }
    }

    return grouped;
  }

  // 这个的逻辑与上面类似，只是键变成了专辑名
  Map<String, List<Song>> get songsByAlbum {
    final Map<String, List<Song>> grouped = {};
    for (final song in _allSongs) {
      // 使用专辑名作为分组的键
      grouped.putIfAbsent(song.album, () => []).add(song);
    }
    return grouped;
  }

  // 处理在歌手/专辑详情页中的拖动排序
  Future<void> reorderActiveSongList(int oldIndex, int newIndex) async {
    // 安全检查，确保当前视图是歌手或专辑
    if (_currentDetailViewContext != DetailViewContext.artist &&
        _currentDetailViewContext != DetailViewContext.album) {
      return;
    }

    // 如果项目向下移动，新的索引会比实际插入位置大1
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }

    // 更新列表顺序
    final song = _activeSongList.removeAt(oldIndex);
    _activeSongList.insert(newIndex, song);

    // 提取出新的文件路径顺序
    final newPathOrder = _activeSongList.map((s) => s.filePath).toList();

    // 根据当前视图上下文，保存到对应的json文件
    if (_currentDetailViewContext == DetailViewContext.artist) {
      _artistSortOrders[_activeDetailTitle] = newPathOrder;
      await _playlistManager.saveArtistSortOrders(_artistSortOrders);
    } else if (_currentDetailViewContext == DetailViewContext.album) {
      _albumSortOrders[_activeDetailTitle] = newPathOrder;
      await _playlistManager.saveAlbumSortOrders(_albumSortOrders);
    }

    notifyListeners();
  }

  // --- 全部歌曲页面相关 ---

  Future<void> _updateAllSongsList() async {
    // 初始化加载状态
    _allSongsLoaded = false;
    notifyListeners();

    // 从所有歌单中获取当前所有可用的、不重复的歌曲路径集合
    final allAvailablePaths = <String>{};
    for (final playlist in _playlists) {
      allAvailablePaths.addAll(playlist.songFilePaths);
    }
    _pruneMetadataCache(allAvailablePaths);

    // 加载旧顺序并合并新路径
    final List<String> savedOrder = await _playlistManager.loadAllSongsOrder();
    savedOrder.removeWhere((path) => !allAvailablePaths.contains(path));
    final existingPathsInOrder = savedOrder.toSet();
    final newPaths = allAvailablePaths.where(
      (path) => !existingPathsInOrder.contains(path),
    );
    savedOrder.addAll(newPaths);

    // 解析元数据
    final List<Song> songsWithMetadata = [];

    // final stopwatch = Stopwatch()..start();

    for (final path in savedOrder) {
      final song = await _parseSongMetadata(path);
      songsWithMetadata.add(song);
    }

    // stopwatch.stop();
    // print('解析耗时: ${stopwatch.elapsedMicroseconds} µs');

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

    final finalPathOrder = _allSongs.map((s) => s.filePath).toList();
    await _playlistManager.saveAllSongsOrder(finalPathOrder);

    // 同步更新虚拟播放列表的路径，以便播放逻辑正常工作
    _allSongsVirtualPlaylist.songFilePaths = _allSongs
        .map((s) => s.filePath)
        .toList();
    unawaited(
      _verifySongMetadataInBackground(_allSongsVirtualPlaylist.songFilePaths),
    );
    // if (_isSearching) {
    //   _updateFilteredSongs(searchInAllSongs: true); // 如果正在搜索，同步更新结果
    // }
    // 清理无效的排序数据
    _cleanupInvalidSortingData();

    // 标记加载完成
    _allSongsLoaded = true;
    notifyListeners();
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

  // 给全部歌曲页面用的置于顶部方法
  Future<void> moveSongToTopInAllSongs(int index) async {
    if (index <= 0 || index >= _allSongs.length) {
      // 如果已经是第一首或索引无效，则不操作
      return;
    }

    final songToMove = _allSongs.removeAt(index);
    _allSongs.insert(0, songToMove);

    // 提取出新的文件路径顺序
    final newPathOrder = _allSongs.map((s) => s.filePath).toList();

    await _playlistManager.saveAllSongsOrder(newPathOrder);

    // 更新播放列表以匹配新顺序
    _allSongsVirtualPlaylist.songFilePaths = newPathOrder;

    _infoStreamController.add('已将歌曲“${songToMove.title}”置于顶部');

    notifyListeners();
  }

  // --- 搜索相关 ---

  void setViewContextForPlaylist() {
    _currentDetailViewContext = DetailViewContext.playlist;
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

  void search(String keyword) {
    _searchKeyword = keyword.toLowerCase();
    _updateFilteredSongs();
    notifyListeners();
  }

  void _updateFilteredSongs() {
    List<Song> sourceList;

    // 根据当前视图上下文，选择正确的数据源
    switch (_currentDetailViewContext) {
      case DetailViewContext.playlist:
        sourceList = _currentPlaylistSongs;
        break;
      case DetailViewContext.allSongs:
        sourceList = _allSongs;
        break;
      case DetailViewContext.artist:
      case DetailViewContext.album:
        // 对于歌手和专辑详情页，都从_activeSongList中搜索
        sourceList = _activeSongList;
        break;
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

  // --- 消息通知 ---
  void postError(String errorMessage) {
    _errorStreamController.add(errorMessage);
  }

  void postInfo(String infoMessage) {
    _infoStreamController.add(infoMessage);
  }

  // 控制快捷键启用/禁用的方法
  void setDisableHotKeys(bool value) {
    _disableHotKeys = value;
  }
}
