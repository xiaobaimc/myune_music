import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:system_fonts/system_fonts.dart';
import 'package:window_manager/window_manager.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'hot_keys.dart';
import 'theme/theme_provider.dart';
import 'layout/app_shell.dart';
import 'page/playlist/playlist_content_notifier.dart';
import 'page/setting/settings_provider.dart';
import 'src/rust/frb_generated.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  MediaKit.ensureInitialized();

  await RustLib.init();

  // 初始化window_manager
  await windowManager.ensureInitialized();

  // 初始化窗口状态管理器
  final windowState = WindowStateManager();
  final initialSize = await windowState.loadWindowSize();

  const minPossibleSize = Size(480, 600);
  final windowOptions = WindowOptions(
    size: initialSize,
    minimumSize: minPossibleSize,
    center: true,
    title: "MyuneMusic",
    titleBarStyle: TitleBarStyle.hidden,
    // backgroundColor: Colors.transparent, // 让原生窗口背景透明
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setAsFrameless();
    await windowManager.setHasShadow(true);
    await windowManager.show();
    await windowManager.focus();
  });

  // 添加监听器 保存窗口大小
  windowManager.addListener(windowState);

  final themeProvider = ThemeProvider();
  await themeProvider.initialize();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider.value(value: themeProvider),
        ChangeNotifierProvider(
          create: (context) => PlaylistContentNotifier(
            context.read<SettingsProvider>(),
            context.read<ThemeProvider>(),
          ),
        ),
      ],
      child: const MyApp(),
    ),
  );

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.dumpErrorToConsole(details);
  };

  final systemFonts = SystemFonts();
  await themeProvider.loadCurrentFont(systemFonts);
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'MyuneMusic',
          theme: themeProvider.lightThemeData,
          darkTheme: themeProvider.darkThemeData,
          themeMode: themeProvider.themeMode,
          builder: (context, materialAppChild) {
            return DragToResizeArea(child: Hotkeys(child: materialAppChild!));
          },

          home: const AppShell(),
        );
      },
    );
  }
}

// 管理窗口大小的加载与保存
class WindowStateManager with WindowListener {
  Future<Size> loadWindowSize() async {
    final prefs = await SharedPreferences.getInstance();
    final width = prefs.getDouble('window_width') ?? 1200;
    final height = prefs.getDouble('window_height') ?? 700;
    return Size(width, height);
  }

  @override
  void onWindowResize() async {
    final size = await windowManager.getSize();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('window_width', size.width);
    await prefs.setDouble('window_height', size.height);
  }
}
