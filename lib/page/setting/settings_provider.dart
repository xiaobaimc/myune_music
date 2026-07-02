import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

class SettingsProvider with ChangeNotifier {
  static const _enableGlobalHotkeysKey = 'enableGlobalHotkeys';
  static const _playPauseHotKeyKey = 'playPauseHotKey';
  static const _nextTrackHotKeyKey = 'nextTrackHotKey';
  static const _prevTrackHotKeyKey = 'prevTrackHotKey';
  static const _volumeUpHotKeyKey = 'volumeUpHotKey';
  static const _volumeDownHotKeyKey = 'volumeDownHotKey';

  static const _prefsKey = 'maxLinesPerLyric';
  static const _fontSizeKey = 'fontSize';
  static const _lyricAlignmentKey = 'lyricAlignment';
  static const _useBlurBackgroundKey = 'useBlurBackground'; // 模糊背景设置的 key
  static const _useDynamicColorKey = 'useDynamicColor'; // 动态颜色设置的 key
  static const _allowAnyFormatKey = 'allowAnyFormat'; // 允许任何格式设置的 key
  static const _forceSingleLineLyricKey =
      'forceSingleLineLyric'; // 强制单行歌词设置的 key
  static const _showAlbumNameKey = 'showAlbumName'; // 显示专辑名称设置的 key

  static const _enableOnlineLyricsKey = 'enableOnlineLyrics';
  static const _lyricVerticalSpacingKey =
      'lyricVerticalSpacing'; // 歌词垂直间距设置的 key
  static const _primaryLyricSourceKey = 'primaryLyricSource'; // 主要歌词源设置的 key
  static const _secondaryLyricSourceKey =
      'secondaryLyricSource'; // 备用歌词源设置的 key
  static const _addLyricPaddingKey = 'addLyricPadding'; // 歌词上下补位设置的 key
  static const _artistSeparatorsKey = 'artistSeparators'; // 艺术家分隔符设置的 key
  static const _minimizeToTrayKey = 'minimizeToTray'; // 最小化到托盘设置的 key
  static const _enableLyricBlurKey = 'enableLyricBlur'; // 歌词模糊效果设置的 key
  static const _lyricBlurStrengthKey = 'lyricBlurStrength'; // 歌词模糊强度设置的 key
  static const _showTaskbarProgressKey =
      'showTaskbarProgress'; // 任务栏进度显示设置的 key
  static const _hiddenPagesKey = 'hiddenPages'; // 隐藏页面设置的 key
  static const _enableDynamicBackgroundKey =
      'enableDynamicBackground'; // 动态背景设置的 key
  static const _audioDeviceNameKey = 'audio_device_name';
  static const _audioDeviceDescKey = 'audio_device_desc';
  static const _audioDeviceIsAutoKey = 'audio_device_is_auto';
  static const _ignorePlaybackErrorsKey = 'ignorePlaybackErrors';
  static const _preferExternalLyricsKey = 'preferExternalLyrics';

  static const _enableLyricElasticScrollKey = 'enableLyricElasticScroll';
  static const _enableLoudnessKey = 'enableLoudness';
  static const _enableReplayGainKey = 'enableReplayGain';
  static const _enableGaplessPlaybackKey = 'enableGaplessPlayback';

  int _maxLinesPerLyric = 2;
  double _fontSize = 22.0; // 默认字体大小
  TextAlign _lyricAlignment = TextAlign.center; // 默认居中对齐
  bool _useBlurBackground = true; // 默认启用模糊背景
  bool _useDynamicColor = true; // 默认启用动态颜色
  bool _allowAnyFormat = false; // 默认不允许任何格式
  bool _forceSingleLineLyric = false; // 默认不强制单行显示歌词
  double _lyricVerticalSpacing = 6.0; // 默认歌词垂直间距为6.0
  bool _addLyricPadding = true; // 默认启用歌词上下补位
  bool _minimizeToTray = false; // 默认不启用最小化到托盘
  bool _enableLyricBlur = true; // 默认启用歌词模糊效果
  double _lyricBlurStrength = 2.5; // 歌词模糊强度，范围 1.0~4.0
  bool _showAlbumName = false; // 默认不显示专辑名称
  bool _enableDynamicBackground = false; // 默认不启用动态背景
  bool _audioDeviceIsAuto = true; // 默认音频设备为自动
  String? _audioDeviceName; // 音频设备名称
  String? _audioDeviceDesc; // 音频设备描述
  bool _ignorePlaybackErrors = false; // 默认不忽略播放错误
  bool _preferExternalLyrics = false; // 默认不优先读取外置LRC歌词
  bool _enableLyricElasticScroll = false;
  bool _enableLoudness = false;
  bool _enableReplayGain = false;
  bool _enableGaplessPlayback = false; // 默认不启用无缝播放

  bool _enableGlobalHotkeys = true;
  HotKey? _playPauseHotKey;
  HotKey? _nextTrackHotKey;
  HotKey? _prevTrackHotKey;
  HotKey? _volumeUpHotKey;
  HotKey? _volumeDownHotKey;

  bool _showTaskbarProgress = false;
  bool _enableOnlineLyrics = false; // 默认不启用从网络获取歌词
  String _primaryLyricSource = 'qq'; // 默认主要歌词源为qq音乐
  String _secondaryLyricSource = 'netease'; // 默认备用歌词源为网易云音乐

  // 隐藏页面列表，默认为空（都不隐藏）
  List<String> _hiddenPages = [];

  // 默认艺术家分隔符
  List<String> _artistSeparators = [';', '、', '；', '，', ','];

  int get maxLinesPerLyric => _maxLinesPerLyric;
  double get fontSize => _fontSize;
  TextAlign get lyricAlignment => _lyricAlignment;
  bool get useBlurBackground => _useBlurBackground; // 获取模糊背景设置
  bool get useDynamicColor => _useDynamicColor; // 获取动态颜色设置
  bool get allowAnyFormat => _allowAnyFormat; // 获取允许任何格式设置
  bool get forceSingleLineLyric => _forceSingleLineLyric; // 获取强制单行歌词设置
  double get lyricVerticalSpacing => _lyricVerticalSpacing; // 获取歌词垂直间距
  bool get addLyricPadding => _addLyricPadding; // 获取歌词上下补位设置
  bool get minimizeToTray => _minimizeToTray; // 获取最小化到托盘设置
  bool get enableLyricBlur => _enableLyricBlur; // 获取歌词模糊效果设置
  double get lyricBlurStrength => _lyricBlurStrength; // 获取歌词模糊强度设置
  bool get showTaskbarProgress => _showTaskbarProgress; // 获取任务栏进度显示设置
  bool get showAlbumName => _showAlbumName; // 获取显示专辑名称设置
  bool get enableDynamicBackground => _enableDynamicBackground; // 获取动态背景设置

  bool get enableOnlineLyrics => _enableOnlineLyrics;
  String get primaryLyricSource => _primaryLyricSource; // 获取主要歌词源
  String get secondaryLyricSource => _secondaryLyricSource; // 获取备用歌词源

  List<String> get hiddenPages => _hiddenPages; // 获取隐藏页面列表

  List<String> get artistSeparators => _artistSeparators; // 获取艺术家分隔符

  bool get audioDeviceIsAuto => _audioDeviceIsAuto;
  String? get audioDeviceName => _audioDeviceName;
  String? get audioDeviceDesc => _audioDeviceDesc;
  bool get ignorePlaybackErrors => _ignorePlaybackErrors;

  bool get preferExternalLyrics => _preferExternalLyrics; // 获取优先读取外置LRC歌词设置
  bool get enableLyricElasticScroll => _enableLyricElasticScroll;
  bool get enableLoudness => _enableLoudness;
  bool get enableReplayGain => _enableReplayGain;
  bool get enableGaplessPlayback => _enableGaplessPlayback;

  bool get enableGlobalHotkeys => _enableGlobalHotkeys;
  HotKey? get playPauseHotKey => _playPauseHotKey;
  HotKey? get nextTrackHotKey => _nextTrackHotKey;
  HotKey? get prevTrackHotKey => _prevTrackHotKey;
  HotKey? get volumeUpHotKey => _volumeUpHotKey;
  HotKey? get volumeDownHotKey => _volumeDownHotKey;

  late final Future<void> initializationFuture;

  SettingsProvider() {
    initializationFuture = _loadFromPrefs();
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _maxLinesPerLyric = prefs.getInt(_prefsKey) ?? 2;
    _fontSize = prefs.getDouble(_fontSizeKey) ?? 20.0;
    _useBlurBackground = prefs.getBool(_useBlurBackgroundKey) ?? true;
    _useDynamicColor = prefs.getBool(_useDynamicColorKey) ?? true; // 加载动态颜色设置
    _allowAnyFormat = prefs.getBool(_allowAnyFormatKey) ?? false; // 加载允许任何格式设置
    _forceSingleLineLyric =
        prefs.getBool(_forceSingleLineLyricKey) ?? false; // 加载强制单行歌词设置
    _showAlbumName = prefs.getBool(_showAlbumNameKey) ?? false; // 加载显示专辑名称设置
    _enableOnlineLyrics = prefs.getBool(_enableOnlineLyricsKey) ?? false;
    _lyricVerticalSpacing =
        prefs.getDouble(_lyricVerticalSpacingKey) ?? 6.0; // 加载歌词垂直间距设置
    _addLyricPadding = prefs.getBool(_addLyricPaddingKey) ?? true; // 加载歌词上下补位设置
    _minimizeToTray = prefs.getBool(_minimizeToTrayKey) ?? false; // 加载最小化到托盘设置
    _enableLyricBlur = prefs.getBool(_enableLyricBlurKey) ?? true; // 加载歌词模糊效果设置
    _lyricBlurStrength =
        prefs.getDouble(_lyricBlurStrengthKey) ?? 2.5; // 加载歌词模糊强度设置
    _primaryLyricSource =
        prefs.getString(_primaryLyricSourceKey) ?? 'qq'; // 加载主要歌词源设置
    _secondaryLyricSource =
        prefs.getString(_secondaryLyricSourceKey) ?? 'netease'; // 加载备用歌词源设置
    _showTaskbarProgress =
        prefs.getBool(_showTaskbarProgressKey) ?? false; // 加载任务栏进度显示设置
    _enableDynamicBackground =
        prefs.getBool(_enableDynamicBackgroundKey) ?? false; // 加载动态背景设置

    _audioDeviceIsAuto = prefs.getBool(_audioDeviceIsAutoKey) ?? true;
    _audioDeviceName = prefs.getString(_audioDeviceNameKey);
    _audioDeviceDesc = prefs.getString(_audioDeviceDescKey);
    _ignorePlaybackErrors = prefs.getBool(_ignorePlaybackErrorsKey) ?? false;
    _preferExternalLyrics = prefs.getBool(_preferExternalLyricsKey) ?? false;
    _enableLyricElasticScroll =
        prefs.getBool(_enableLyricElasticScrollKey) ?? false;
    _enableLoudness = prefs.getBool(_enableLoudnessKey) ?? false;
    _enableReplayGain = prefs.getBool(_enableReplayGainKey) ?? false;
    _enableGaplessPlayback = prefs.getBool(_enableGaplessPlaybackKey) ?? false;
    if (_enableLoudness && _enableReplayGain) {
      _enableReplayGain = false;
      await prefs.setBool(_enableReplayGainKey, false);
    }

    // 加载隐藏页面设置
    final hiddenPagesList = prefs.getStringList(_hiddenPagesKey);
    if (hiddenPagesList != null) {
      _hiddenPages = hiddenPagesList;
    }

    // 加载艺术家分隔符设置
    final separatorsList = prefs.getStringList(_artistSeparatorsKey);
    if (separatorsList != null && separatorsList.isNotEmpty) {
      _artistSeparators = separatorsList;
    }

    final alignmentString = prefs.getString(_lyricAlignmentKey);
    _lyricAlignment = alignmentString != null
        ? TextAlign.values.firstWhere(
            (e) => e.toString() == alignmentString,
            orElse: () => TextAlign.center,
          )
        : TextAlign.center;

    _enableGlobalHotkeys = prefs.getBool(_enableGlobalHotkeysKey) ?? true;
    _playPauseHotKey = _parseHotKey(prefs.getString(_playPauseHotKeyKey), 'play_pause');
    _nextTrackHotKey = _parseHotKey(prefs.getString(_nextTrackHotKeyKey), 'next_track');
    _prevTrackHotKey = _parseHotKey(prefs.getString(_prevTrackHotKeyKey), 'prev_track');
    _volumeUpHotKey = _parseHotKey(prefs.getString(_volumeUpHotKeyKey), 'volume_up');
    _volumeDownHotKey = _parseHotKey(prefs.getString(_volumeDownHotKeyKey), 'volume_down');

    notifyListeners(); // 读取完毕后刷新界面
  }

  void setMaxLinesPerLyric(int value) async {
    _maxLinesPerLyric = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsKey, value);
  }

  void setFontSize(double size) async {
    _fontSize = size.clamp(12.0, 32.0); // 限制字体大小范围
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_fontSizeKey, _fontSize);
  }

  void setLyricAlignment(TextAlign alignment) async {
    _lyricAlignment = alignment;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lyricAlignmentKey, alignment.toString());
  }

  void setUseBlurBackground(bool value) async {
    _useBlurBackground = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_useBlurBackgroundKey, value);
  }

  void setUseDynamicColor(bool value) async {
    if (_useDynamicColor != value) {
      _useDynamicColor = value;
      notifyListeners();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_useDynamicColorKey, value);
    }
  }

  void setEnableOnlineLyrics(bool value) async {
    _enableOnlineLyrics = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enableOnlineLyricsKey, value);
  }

  void setLyricVerticalSpacing(double value) async {
    _lyricVerticalSpacing = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_lyricVerticalSpacingKey, value);
  }

  void setPrimaryLyricSource(String value) async {
    _primaryLyricSource = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_primaryLyricSourceKey, value);
  }

  void setSecondaryLyricSource(String value) async {
    _secondaryLyricSource = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_secondaryLyricSourceKey, value);
  }

  void setAllowAnyFormat(bool value) async {
    _allowAnyFormat = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_allowAnyFormatKey, value);
  }

  void setForceSingleLineLyric(bool value) async {
    _forceSingleLineLyric = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_forceSingleLineLyricKey, value);
  }

  void setAddLyricPadding(bool value) async {
    _addLyricPadding = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_addLyricPaddingKey, value);
  }

  void setArtistSeparators(List<String> separators) async {
    _artistSeparators = separators;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    // 使用字符串列表而不是用逗号连接的字符串，避免与分隔符冲突
    await prefs.setStringList(_artistSeparatorsKey, separators);
  }

  void setMinimizeToTray(bool value) async {
    _minimizeToTray = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_minimizeToTrayKey, value);
  }

  void setEnableLyricBlur(bool value) async {
    _enableLyricBlur = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enableLyricBlurKey, value);
  }

  void setLyricBlurStrength(double value) async {
    final clampedValue = value.clamp(1.0, 4.0);
    if (_lyricBlurStrength == clampedValue) return;

    _lyricBlurStrength = clampedValue;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_lyricBlurStrengthKey, clampedValue);
  }

  void setShowTaskbarProgress(bool value) async {
    _showTaskbarProgress = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showTaskbarProgressKey, value);
  }

  void setShowAlbumName(bool value) async {
    _showAlbumName = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showAlbumNameKey, value);
  }

  void setHiddenPages(List<String> hiddenPages) async {
    // 确保歌单和设置不会被隐藏
    final filteredHiddenPages = hiddenPages
        .where((page) => page != '歌单' && page != '设置')
        .toList();

    _hiddenPages = filteredHiddenPages;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_hiddenPagesKey, filteredHiddenPages);
  }

  void setEnableDynamicBackground(bool value) async {
    _enableDynamicBackground = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enableDynamicBackgroundKey, value);
  }

  void setAudioDevice(String name, String desc) async {
    _audioDeviceIsAuto = false;
    _audioDeviceName = name;
    _audioDeviceDesc = desc;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_audioDeviceIsAutoKey, false);
    await prefs.setString(_audioDeviceNameKey, name);
    await prefs.setString(_audioDeviceDescKey, desc);
  }

  void setAudioDeviceToAuto() async {
    _audioDeviceIsAuto = true;
    _audioDeviceName = null;
    _audioDeviceDesc = null;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_audioDeviceIsAutoKey, true);
    await prefs.remove(_audioDeviceNameKey);
    await prefs.remove(_audioDeviceDescKey);
  }

  void setIgnorePlaybackErrors(bool value) async {
    _ignorePlaybackErrors = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_ignorePlaybackErrorsKey, value);
  }

  void setPreferExternalLyrics(bool value) async {
    _preferExternalLyrics = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_preferExternalLyricsKey, value);
  }

  void setEnableLyricElasticScroll(bool value) async {
    _enableLyricElasticScroll = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enableLyricElasticScrollKey, value);
  }

  void setEnableLoudness(bool value) async {
    _enableLoudness = value;
    if (value) {
      _enableReplayGain = false;
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enableLoudnessKey, value);
    if (value) {
      await prefs.setBool(_enableReplayGainKey, false);
    }
  }

  void setEnableReplayGain(bool value) async {
    _enableReplayGain = value;
    if (value) {
      _enableLoudness = false;
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enableReplayGainKey, value);
    if (value) {
      await prefs.setBool(_enableLoudnessKey, false);
    }
  }

  void setEnableGaplessPlayback(bool value) async {
    _enableGaplessPlayback = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enableGaplessPlaybackKey, value);
  }

  HotKey? _parseHotKey(String? jsonStr, String type) {
    if (jsonStr != null && jsonStr.isNotEmpty) {
      try {
        final Map<String, dynamic> json = jsonDecode(jsonStr);
        return HotKey.fromJson(json);
      } catch (e) {
        // Fallback to default
      }
    }
    return _getDefaultHotKey(type);
  }

  HotKey _getDefaultHotKey(String type) {
    switch (type) {
      case 'play_pause':
        return HotKey(
          key: PhysicalKeyboardKey.space,
          modifiers: [HotKeyModifier.control, HotKeyModifier.alt],
          scope: HotKeyScope.system,
          identifier: 'play_pause',
        );
      case 'next_track':
        return HotKey(
          key: PhysicalKeyboardKey.arrowRight,
          modifiers: [HotKeyModifier.control, HotKeyModifier.alt],
          scope: HotKeyScope.system,
          identifier: 'next_track',
        );
      case 'prev_track':
        return HotKey(
          key: PhysicalKeyboardKey.arrowLeft,
          modifiers: [HotKeyModifier.control, HotKeyModifier.alt],
          scope: HotKeyScope.system,
          identifier: 'prev_track',
        );
      case 'volume_up':
        return HotKey(
          key: PhysicalKeyboardKey.arrowUp,
          modifiers: [HotKeyModifier.control, HotKeyModifier.alt],
          scope: HotKeyScope.system,
          identifier: 'volume_up',
        );
      case 'volume_down':
        return HotKey(
          key: PhysicalKeyboardKey.arrowDown,
          modifiers: [HotKeyModifier.control, HotKeyModifier.alt],
          scope: HotKeyScope.system,
          identifier: 'volume_down',
        );
      default:
        throw ArgumentError('Invalid hotkey type');
    }
  }

  Future<void> setEnableGlobalHotkeys(bool value) async {
    _enableGlobalHotkeys = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enableGlobalHotkeysKey, value);
  }

  Future<void> setHotKey(String type, HotKey? hotKey) async {
    final prefs = await SharedPreferences.getInstance();
    final String key;
    switch (type) {
      case 'play_pause':
        _playPauseHotKey = hotKey;
        key = _playPauseHotKeyKey;
        break;
      case 'next_track':
        _nextTrackHotKey = hotKey;
        key = _nextTrackHotKeyKey;
        break;
      case 'prev_track':
        _prevTrackHotKey = hotKey;
        key = _prevTrackHotKeyKey;
        break;
      case 'volume_up':
        _volumeUpHotKey = hotKey;
        key = _volumeUpHotKeyKey;
        break;
      case 'volume_down':
        _volumeDownHotKey = hotKey;
        key = _volumeDownHotKeyKey;
        break;
      default:
        return;
    }
    notifyListeners();
    if (hotKey != null) {
      await prefs.setString(key, jsonEncode(hotKey.toJson()));
    } else {
      await prefs.remove(key);
    }
  }

  Future<void> resetToDefaultHotKeys() async {
    final prefs = await SharedPreferences.getInstance();
    _playPauseHotKey = _getDefaultHotKey('play_pause');
    _nextTrackHotKey = _getDefaultHotKey('next_track');
    _prevTrackHotKey = _getDefaultHotKey('prev_track');
    _volumeUpHotKey = _getDefaultHotKey('volume_up');
    _volumeDownHotKey = _getDefaultHotKey('volume_down');
    notifyListeners();
    await prefs.setString(_playPauseHotKeyKey, jsonEncode(_playPauseHotKey!.toJson()));
    await prefs.setString(_nextTrackHotKeyKey, jsonEncode(_nextTrackHotKey!.toJson()));
    await prefs.setString(_prevTrackHotKeyKey, jsonEncode(_prevTrackHotKey!.toJson()));
    await prefs.setString(_volumeUpHotKeyKey, jsonEncode(_volumeUpHotKey!.toJson()));
    await prefs.setString(_volumeDownHotKeyKey, jsonEncode(_volumeDownHotKey!.toJson()));
  }
}
