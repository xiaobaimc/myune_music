import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:system_fonts/system_fonts.dart';
import 'package:flutter/foundation.dart';

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
  Color _currentSeedColor = Color(
    _defaultSeedColorValue,
  ); // 当前正在使用的主题种子色（可能是动态色或手动色）
  Color _lastManualSeedColor = Color(
    _defaultSeedColorValue,
  ); // 用户最后一次手动选择的种子色，用于在关闭动态配色时恢复

  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  static const String _seedColorKey = 'user_seed_color';
  static const String _lastManualSeedColorKey =
      'user_last_manual_seed_color'; // 用户手动选择的种子色，用于在关闭动态配色时恢复

  static const String _fontFamilyKey = 'user_font_family';
  String _currentFontFamily = 'Misans'; // 默认字体

  ThemeProvider() {
    initialize();
  }

  Color get currentSeedColor => _currentSeedColor;

  Color get lastManualSeedColor => _lastManualSeedColor;

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
  ).makeMouseClickable();

  ThemeData get darkThemeData => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _currentSeedColor,
      brightness: Brightness.dark,
    ),
    fontFamily: _currentFontFamily,
    textTheme: misansTextTheme,
  ).makeMouseClickable();

  Future<void> setSeedColor(Color newColor, {bool isManual = false}) async {
    if (_currentSeedColor != newColor) {
      _currentSeedColor = newColor;
      notifyListeners();
      await _saveSeedColor(newColor);
    }
    if (isManual) {
      _lastManualSeedColor = newColor;
      await _saveLastManualSeedColor(newColor);
    }
  }

  Future<void> _loadSeedColor() async {
    final prefs = await SharedPreferences.getInstance();
    final int? savedColorValue = prefs.getInt(_seedColorKey);
    if (savedColorValue != null) {
      _currentSeedColor = Color(savedColorValue);
    }
  }

  Future<void> _saveSeedColor(Color color) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_seedColorKey, color.toARGB32());
  }

  Future<void> _saveLastManualSeedColor(Color color) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastManualSeedColorKey, color.toARGB32());
  }

  Future<void> _loadLastManualSeedColor() async {
    final prefs = await SharedPreferences.getInstance();
    final int? savedColorValue = prefs.getInt(_lastManualSeedColorKey);
    if (savedColorValue != null) {
      _lastManualSeedColor = Color(savedColorValue);
    }
  }

  Future<void> restoreLastManualColor() async {
    final prefs = await SharedPreferences.getInstance();
    final int? savedColorValue = prefs.getInt(_lastManualSeedColorKey);
    final color = savedColorValue != null
        ? Color(savedColorValue)
        : Color(_defaultSeedColorValue);
    if (_currentSeedColor != color) {
      _currentSeedColor = color;
      notifyListeners();
      await _saveSeedColor(color);
    }
  }

  // 迁移手动选择的种子色键名
  // 如果用户手动选择的种子色键名不存在，从种子色键中获取颜色值并迁移到用户手动选择的种子色键名
  // 这是为了在应用升级时，用户手动选择的种子色能够被恢复
  Future<void> _migrateManualColorKey() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_lastManualSeedColorKey)) {
      final existingSeed = prefs.getInt(_seedColorKey);
      if (existingSeed != null) {
        await prefs.setInt(_lastManualSeedColorKey, existingSeed);
      }
    }
  }

  void toggleDarkMode() async {
    switch (_themeMode) {
      case ThemeMode.light:
        _themeMode = ThemeMode.dark;
        break;
      case ThemeMode.dark:
        _themeMode = ThemeMode.system;
        break;
      case ThemeMode.system:
        _themeMode = ThemeMode.light;
        break;
    }
    notifyListeners();

    setThemeMode(_themeMode);
  }

  void setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_theme_mode', _themeModeToString(_themeMode));
  }

  String _themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  ThemeMode _stringToThemeMode(String? modeString) {
    switch (modeString) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> _loadDarkMode() async {
    final prefs = await SharedPreferences.getInstance();
    final String? modeString = prefs.getString('user_theme_mode');
    _themeMode = _stringToThemeMode(modeString);
  }

  Future<void> _loadFontFamily() async {
    final prefs = await SharedPreferences.getInstance();
    final savedFont = prefs.getString(_fontFamilyKey);
    if (savedFont != null && savedFont.isNotEmpty) {
      _currentFontFamily = savedFont;
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
    await _migrateManualColorKey();
    await _loadLastManualSeedColor();
    notifyListeners();
  }

  Future<void> loadCurrentFont(SystemFonts systemFonts) async {
    if (_currentFontFamily != 'Misans') {
      await systemFonts.loadFont(_currentFontFamily);
      notifyListeners();
    }
  }
}

class DesktopButtonTheme {
  const DesktopButtonTheme._(); // 防止实例化

  static const WidgetStateProperty<MouseCursor> clickableCursor =
      WidgetStatePropertyAll(SystemMouseCursors.click);

  static const TextButtonThemeData textButtonTheme = TextButtonThemeData(
    style: ButtonStyle(mouseCursor: clickableCursor),
  );

  static const ElevatedButtonThemeData elevatedButtonTheme =
      ElevatedButtonThemeData(style: ButtonStyle(mouseCursor: clickableCursor));

  static const OutlinedButtonThemeData outlinedButtonTheme =
      OutlinedButtonThemeData(style: ButtonStyle(mouseCursor: clickableCursor));
}

// 代码来源: https://github.com/flutter/flutter/issues/182466#issuecomment-3932182424
// 旨在修复Flutter 3.40+ 鼠标点击光标被移除的问题
// 参考 https://github.com/flutter/flutter/issues/182466
// TODO: 请等待Flutter修复该问题

extension on ThemeData {
  ThemeData makeMouseClickable() {
    final WidgetStateMouseCursor clickable =
        defaultTargetPlatform != TargetPlatform.android
        ? WidgetStateMouseCursor.clickable
        : WidgetStateMouseCursor.adaptiveClickable;
    return copyWith(
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: (elevatedButtonTheme.style ?? const ButtonStyle()).copyWith(
          mouseCursor: clickable,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: (filledButtonTheme.style ?? const ButtonStyle()).copyWith(
          mouseCursor: clickable,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: (outlinedButtonTheme.style ?? const ButtonStyle()).copyWith(
          mouseCursor: clickable,
        ),
      ),
      floatingActionButtonTheme: floatingActionButtonTheme.copyWith(
        mouseCursor: clickable,
      ),
      iconButtonTheme: IconButtonThemeData(
        style: (iconButtonTheme.style ?? const ButtonStyle()).copyWith(
          mouseCursor: clickable,
        ),
      ),
      menuButtonTheme: MenuButtonThemeData(
        style: (menuButtonTheme.style ?? const ButtonStyle()).copyWith(
          mouseCursor: clickable,
        ),
      ),
      menuTheme: MenuThemeData(
        submenuIcon: menuTheme.submenuIcon,
        style: (menuTheme.style ?? const MenuStyle()).copyWith(
          mouseCursor: clickable,
        ),
      ),
      checkboxTheme: checkboxTheme.copyWith(mouseCursor: clickable),
      popupMenuTheme: popupMenuTheme.copyWith(mouseCursor: clickable),
      segmentedButtonTheme: segmentedButtonTheme.copyWith(
        style: (segmentedButtonTheme.style ?? const ButtonStyle()).copyWith(
          mouseCursor: clickable,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: (textButtonTheme.style ?? const ButtonStyle()).copyWith(
          mouseCursor: clickable,
        ),
      ),
    );
  }
}
