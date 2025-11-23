import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider with ChangeNotifier {
  static const _prefsKey = 'maxLinesPerLyric';
  static const _fontSizeKey = 'fontSize';
  static const _lyricAlignmentKey = 'lyricAlignment';
  static const _useBlurBackgroundKey = 'useBlurBackground'; // 模糊背景设置的 key
  static const _useDynamicColorKey = 'useDynamicColor'; // 动态颜色设置的 key
  static const _allowAnyFormatKey = 'allowAnyFormat'; // 允许任何格式设置的 key
  static const _forceSingleLineLyricKey =
      'forceSingleLineLyric'; // 强制单行歌词设置的 key

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
  static const _showTaskbarProgressKey =
      'showTaskbarProgress'; // 任务栏进度显示设置的 key

  int _maxLinesPerLyric = 2;
  double _fontSize = 20.0; // 默认字体大小
  TextAlign _lyricAlignment = TextAlign.center; // 默认居中对齐
  bool _useBlurBackground = true; // 默认启用模糊背景
  bool _useDynamicColor = true; // 默认启用动态颜色
  bool _allowAnyFormat = false; // 默认不允许任何格式
  bool _forceSingleLineLyric = false; // 默认不强制单行显示歌词
  double _lyricVerticalSpacing = 6.0; // 默认歌词垂直间距为6.0
  bool _addLyricPadding = false; // 默认不启用歌词上下补位
  bool _minimizeToTray = false; // 默认不启用最小化到托盘
  bool _enableLyricBlur = false; // 默认不启用歌词模糊效果

  bool _showTaskbarProgress = false;
  bool _enableOnlineLyrics = false; // 默认不启用从网络获取歌词
  String _primaryLyricSource = 'qq'; // 默认主要歌词源为qq音乐
  String _secondaryLyricSource = 'netease'; // 默认备用歌词源为网易云音乐

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
  bool get showTaskbarProgress => _showTaskbarProgress; // 获取任务栏进度显示设置

  bool get enableOnlineLyrics => _enableOnlineLyrics;
  String get primaryLyricSource => _primaryLyricSource; // 获取主要歌词源
  String get secondaryLyricSource => _secondaryLyricSource; // 获取备用歌词源

  List<String> get artistSeparators => _artistSeparators; // 获取艺术家分隔符

  SettingsProvider() {
    _loadFromPrefs();
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
    _enableOnlineLyrics = prefs.getBool(_enableOnlineLyricsKey) ?? false;
    _lyricVerticalSpacing =
        prefs.getDouble(_lyricVerticalSpacingKey) ?? 6.0; // 加载歌词垂直间距设置
    _addLyricPadding =
        prefs.getBool(_addLyricPaddingKey) ?? false; // 加载歌词上下补位设置
    _minimizeToTray = prefs.getBool(_minimizeToTrayKey) ?? false; // 加载最小化到托盘设置
    _enableLyricBlur =
        prefs.getBool(_enableLyricBlurKey) ?? false; // 加载歌词模糊效果设置
    _primaryLyricSource =
        prefs.getString(_primaryLyricSourceKey) ?? 'qq'; // 加载主要歌词源设置
    _secondaryLyricSource =
        prefs.getString(_secondaryLyricSourceKey) ?? 'netease'; // 加载备用歌词源设置
    _showTaskbarProgress =
        prefs.getBool(_showTaskbarProgressKey) ?? false; // 加载任务栏进度显示设置

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

  void setShowTaskbarProgress(bool value) async {
    _showTaskbarProgress = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showTaskbarProgressKey, value);
  }
}
