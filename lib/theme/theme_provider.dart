import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:system_fonts/system_fonts.dart';

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

  static const String _fontFamilyKey = 'user_font_family';
  String _currentFontFamily = 'Misans'; // 默认字体

  ThemeProvider() {
    initialize();
  }

  Color get currentSeedColor => _currentSeedColor;

  String get currentFontFamily => _currentFontFamily;

  ColorScheme get currentColorScheme {
    return ColorScheme.fromSeed(seedColor: _currentSeedColor);
  }

  ThemeData get lightThemeData => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _currentSeedColor,
      brightness: Brightness.light,
    ),
    fontFamily: _currentFontFamily,
    textTheme: misansTextTheme,
  );

  ThemeData get darkThemeData => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _currentSeedColor,
      brightness: Brightness.dark,
    ),
    fontFamily: _currentFontFamily,
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

  Future<void> _loadFontFamily() async {
    final prefs = await SharedPreferences.getInstance();
    final savedFont = prefs.getString(_fontFamilyKey);
    if (savedFont != null && savedFont.isNotEmpty) {
      _currentFontFamily = savedFont;
      notifyListeners();
    }
  }

  void setFontFamily(String fontFamily) async {
    if (_currentFontFamily == fontFamily) return; // 没变就直接退出
    _currentFontFamily = fontFamily;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_fontFamilyKey, fontFamily);
  }

  void resetFontFamily() async {
    _currentFontFamily = 'Misans'; // 默认字体
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_fontFamilyKey);
  }

  Future<void> initialize() async {
    await Future.wait([_loadSeedColor(), _loadDarkMode(), _loadFontFamily()]);
    notifyListeners();
  }

  Future<void> loadCurrentFont(SystemFonts systemFonts) async {
    if (_currentFontFamily != 'Misans') {
      await systemFonts.loadFont(_currentFontFamily);
      notifyListeners();
    }
  }
}
