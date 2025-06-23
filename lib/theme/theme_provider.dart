import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider with ChangeNotifier {
  static const TextStyle defaultStyle = TextStyle(fontWeight: FontWeight.w400);

  static const TextTheme misansTextTheme = TextTheme(
    displayLarge: defaultStyle,
    displayMedium: defaultStyle,
    displaySmall: defaultStyle,
    headlineLarge: defaultStyle,
    headlineMedium: defaultStyle,
    headlineSmall: defaultStyle,
    titleLarge: defaultStyle,
    titleMedium: defaultStyle,
    titleSmall: defaultStyle,
    bodyLarge: defaultStyle,
    bodyMedium: defaultStyle,
    bodySmall: defaultStyle,
    labelLarge: defaultStyle,
    labelMedium: defaultStyle,
    labelSmall: defaultStyle,
  );

  static final int _defaultSeedColorValue = Colors.blue.toARGB32(); // 默认蓝色
  Color _currentSeedColor = Color(_defaultSeedColorValue);

  ThemeMode _themeMode = ThemeMode.light;
  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  static const String _seedColorKey = 'user_seed_color';

  ThemeProvider() {
    _loadSeedColor();
    _loadDarkMode();
  }

  Color get currentSeedColor => _currentSeedColor;

  ColorScheme get currentColorScheme {
    return ColorScheme.fromSeed(seedColor: _currentSeedColor);
  }

  ThemeData get lightThemeData => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _currentSeedColor,
      brightness: Brightness.light,
    ),
    fontFamily: 'Misans',
    textTheme: misansTextTheme,
  );

  ThemeData get darkThemeData => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _currentSeedColor,
      brightness: Brightness.dark,
    ),
    fontFamily: 'Misans',
    textTheme: misansTextTheme,
  );

  void setSeedColor(Color newColor) async {
    if (_currentSeedColor != newColor) {
      _currentSeedColor = newColor;
      notifyListeners();
      _saveSeedColor(newColor);
    }
  }

  Future<void> _loadSeedColor() async {
    final prefs = await SharedPreferences.getInstance();
    final int? savedColorValue = prefs.getInt(_seedColorKey);
    if (savedColorValue != null) {
      _currentSeedColor = Color(savedColorValue);
      notifyListeners();
    }
  }

  Future<void> _saveSeedColor(Color color) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_seedColorKey, color.toARGB32());
  }

  void toggleDarkMode() async {
    _themeMode = isDarkMode ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('user_dark_mode', _themeMode == ThemeMode.dark);
  }

  Future<void> _loadDarkMode() async {
    final prefs = await SharedPreferences.getInstance();
    final bool isDark = prefs.getBool('user_dark_mode') ?? false;
    _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }
}
