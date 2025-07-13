import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider with ChangeNotifier {
  static const _prefsKey = 'maxLinesPerLyric';
  static const _fontSizeKey = 'fontSize';
  static const _lyricAlignmentKey = 'lyricAlignment';
  static const _useBlurBackgroundKey = 'useBlurBackground'; // 模糊背景设置的 key
  static const _useDynamicColorKey = 'useDynamicColor'; // 动态颜色设置的 key

  int _maxLinesPerLyric = 2;
  double _fontSize = 20.0; // 默认字体大小
  TextAlign _lyricAlignment = TextAlign.center; // 默认居中对齐
  bool _useBlurBackground = true; // 默认启用模糊背景
  bool _useDynamicColor = true; // 默认启用动态颜色

  int get maxLinesPerLyric => _maxLinesPerLyric;
  double get fontSize => _fontSize;
  TextAlign get lyricAlignment => _lyricAlignment;
  bool get useBlurBackground => _useBlurBackground; // 获取模糊背景设置
  bool get useDynamicColor => _useDynamicColor; // 获取动态颜色设置

  SettingsProvider() {
    _loadFromPrefs();
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _maxLinesPerLyric = prefs.getInt(_prefsKey) ?? 2;
    _fontSize = prefs.getDouble(_fontSizeKey) ?? 20.0;
    _useBlurBackground = prefs.getBool(_useBlurBackgroundKey) ?? true;
    _useDynamicColor = prefs.getBool(_useDynamicColorKey) ?? true; // 加载动态颜色设置
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
}
