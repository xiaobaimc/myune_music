import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider with ChangeNotifier {
  static const _prefsKey = 'maxLinesPerLyric';
  int _maxLinesPerLyric = 2;

  int get maxLinesPerLyric => _maxLinesPerLyric;

  SettingsProvider() {
    _loadFromPrefs();
  }

  void _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _maxLinesPerLyric = prefs.getInt(_prefsKey) ?? 2;
    notifyListeners(); // 读取完毕后刷新界面
  }

  void setMaxLinesPerLyric(int value) async {
    _maxLinesPerLyric = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsKey, value);
  }
}
