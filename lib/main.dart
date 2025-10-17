import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:system_fonts/system_fonts.dart';
import 'package:window_manager/window_manager.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart';

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

  // 初始化系统托盘
  await trayManager.setIcon('assets/images/icon/tray_icon.ico');
  await trayManager.setToolTip('MyuneMusic');

  final Menu menu = Menu(
    items: [
      MenuItem(key: 'show_window', label: '显示窗口'),
      MenuItem.separator(),
      MenuItem(key: 'exit_app', label: '退出'),
    ],
  );
  await trayManager.setContextMenu(menu);

  // 初始化window_manager
  await windowManager.ensureInitialized();

  // 初始化窗口状态管理器
  final windowState = WindowStateManager();
  final initialSize = await windowState.loadWindowSize();
  final initialPosition = await windowState.loadWindowPosition();

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
    // 设置窗口位置
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey('window_x') && prefs.containsKey('window_y')) {
      await windowManager.setPosition(initialPosition);
    }
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

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with TrayListener {
  @override
  void initState() {
    trayManager.addListener(this);
    super.initState();
  }

  @override
  void dispose() {
    trayManager.removeListener(this);
    super.dispose();
  }

  @override
  void onTrayIconMouseDown() {
    // 点击托盘图标时显示窗口
    windowManager.show();
  }

  @override
  void onTrayIconRightMouseDown() {
    // 右键点击托盘图标时弹出菜单
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'show_window') {
      windowManager.show();
    } else if (menuItem.key == 'exit_app') {
      trayManager.destroy();
      windowManager.destroy();
    }
  }

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
    final width = prefs.getDouble('window_width') ?? 1150;
    final height = prefs.getDouble('window_height') ?? 620;
    return Size(width, height);
  }

  Future<Offset> loadWindowPosition() async {
    final prefs = await SharedPreferences.getInstance();
    final x = prefs.getDouble('window_x') ?? 0;
    final y = prefs.getDouble('window_y') ?? 0;
    return Offset(x, y);
  }

  @override
  void onWindowResize() async {
    final size = await windowManager.getSize();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('window_width', size.width);
    await prefs.setDouble('window_height', size.height);
  }

  @override
  void onWindowMove() async {
    final position = await windowManager.getPosition();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('window_x', position.dx);
    await prefs.setDouble('window_y', position.dy);
  }
}
