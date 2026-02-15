import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:system_fonts/system_fonts.dart';
import 'package:window_manager/window_manager.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:windows_taskbar/windows_taskbar.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'hot_keys.dart';
import 'theme/theme_provider.dart';
import 'layout/app_shell.dart';
import 'page/playlist/playlist_content_notifier.dart';
import 'page/setting/settings_provider.dart';
import 'src/rust/frb_generated.dart';
import 'package:flutter_single_instance/flutter_single_instance.dart';
import 'page/statistics_page/statistics_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 先初始化window_manager
  await windowManager.ensureInitialized();

  // 回调函数
  FlutterSingleInstance.onFocus =
      (Map<String, dynamic> metadata) async {
            // 先恢复窗口，再显示和聚焦
            await windowManager.restore();
            await windowManager.show();
            await windowManager.focus();
          }
          as FutureOr<void> Function(Map<String, dynamic>)?;

  // 单实例检测
  final singleInstance = FlutterSingleInstance();
  if (!await singleInstance.isFirstInstance()) {
    await singleInstance.focus();
    exit(0); // 退出第二个实例
  }

  MediaKit.ensureInitialized();

  await RustLib.init();

  // 初始化系统托盘
  await trayManager.setIcon('assets/images/icon/tray_icon.ico');
  if (!Platform.isLinux) {
    await trayManager.setToolTip('MyuneMusic');
  }

  final Menu menu = Menu(
    items: [
      MenuItem(key: 'show_window', label: '显示窗口'),
      MenuItem.separator(),
      MenuItem(key: 'exit_app', label: '退出'),
    ],
  );
  await trayManager.setContextMenu(menu);

  // // 初始化window_manager
  // await windowManager.ensureInitialized();

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
    // 这一行会导致全屏的时候抖3次
    // await windowManager.setAsFrameless();

    if (!Platform.isLinux) {
      await windowManager.setHasShadow(true);
    }
    // 设置窗口位置
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey('window_x') && prefs.containsKey('window_y')) {
      await windowManager.setPosition(initialPosition);
    }
    await windowManager.show();
    await windowManager.focus();
  });

  //  添加监听器 保存窗口大小
  windowManager.addListener(windowState);

  final themeProvider = ThemeProvider();
  await themeProvider.initialize();

  final statsManager = StatisticsManager();
  await statsManager.init();

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
  late PlaylistContentNotifier _playlistNotifier;
  bool _taskbarReady = false;

  @override
  void initState() {
    trayManager.addListener(this);
    super.initState();

    // 确保窗口已经初始化
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (Platform.isWindows) {
        // 等待窗口完全准备就绪后再初始化任务栏功能
        await Future.delayed(const Duration(milliseconds: 100));
        _taskbarReady = true; // 标记任务栏功能已准备就绪
        _initializeThumbnailToolbar();
        _initializeTaskbarProgress();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _playlistNotifier = context.read<PlaylistContentNotifier>();

    // 监听播放状态变化以更新工具栏按钮
    if (Platform.isWindows) {
      _playlistNotifier.addListener(_updateThumbnailToolbar);
    }

    // 监听设置变化以更新任务栏状态
    context.read<SettingsProvider>().addListener(_onSettingsChanged);
  }

  void _onSettingsChanged() {
    try {
      final settings = context.read<SettingsProvider>();
      if (!settings.showTaskbarProgress) {
        // 当关闭任务栏进度显示时，立即重置进度条状态
        if (Platform.isWindows && _taskbarReady) {
          try {
            WindowsTaskbar.setProgressMode(TaskbarProgressMode.noProgress);
          } catch (_) {}
        }
      } else {
        // 当开启任务栏进度显示时，根据当前播放状态设置进度条模式
        if (Platform.isWindows && _taskbarReady) {
          try {
            if (_playlistNotifier.isPlaying) {
              WindowsTaskbar.setProgressMode(TaskbarProgressMode.normal);
            } else {
              WindowsTaskbar.setProgressMode(TaskbarProgressMode.paused);
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('_onSettingsChanged出现错误: $e');
    }
  }

  Future<void> _initializeThumbnailToolbar() async {
    if (!_taskbarReady) return;

    try {
      WindowsTaskbar.setWindowTitle('MyuneMusic');
      await WindowsTaskbar.setThumbnailToolbar([
        ThumbnailToolbarButton(
          ThumbnailToolbarAssetIcon('assets/images/icon/prev.ico'),
          '上一首',
          _playlistNotifier.playPrevious,
        ),
        ThumbnailToolbarButton(
          ThumbnailToolbarAssetIcon('assets/images/icon/play.ico'),
          '播放',
          _playlistNotifier.play,
        ),
        ThumbnailToolbarButton(
          ThumbnailToolbarAssetIcon('assets/images/icon/next.ico'),
          '下一首',
          _playlistNotifier.playNext,
        ),
      ]);

      // 初始化任务栏进度模式
      await WindowsTaskbar.setProgressMode(TaskbarProgressMode.normal);
    } catch (e) {
      debugPrint('_initializeThumbnailToolbar出现错误: $e');
    }
  }

  Future<void> _updateThumbnailToolbar() async {
    if (!_taskbarReady) return;

    try {
      final isPlaying = _playlistNotifier.isPlaying;

      await WindowsTaskbar.setThumbnailToolbar([
        ThumbnailToolbarButton(
          ThumbnailToolbarAssetIcon('assets/images/icon/prev.ico'),
          '上一首',
          _playlistNotifier.playPrevious,
        ),
        ThumbnailToolbarButton(
          ThumbnailToolbarAssetIcon(
            isPlaying
                ? 'assets/images/icon/pause.ico'
                : 'assets/images/icon/play.ico',
          ),
          isPlaying ? '暂停' : '播放',
          isPlaying ? _playlistNotifier.pause : _playlistNotifier.play,
        ),
        ThumbnailToolbarButton(
          ThumbnailToolbarAssetIcon('assets/images/icon/next.ico'),
          '下一首',
          _playlistNotifier.playNext,
        ),
      ]);
    } catch (e) {
      // debugPrint('_updateThumbnailToolbar出现错误: $e');
    }
  }

  Future<void> _initializeTaskbarProgress() async {
    final settings = context.read<SettingsProvider>();

    // 监听播放进度变化以更新任务栏进度
    _playlistNotifier.mediaPlayer.stream.position.listen((position) async {
      if (!_taskbarReady || !settings.showTaskbarProgress) return;

      final bool isVisible = await windowManager.isVisible();
      if (!isVisible) return;

      try {
        final duration = _playlistNotifier.totalDuration;
        if (duration != Duration.zero) {
          final progress =
              (position.inMilliseconds / duration.inMilliseconds * 100).round();
          WindowsTaskbar.setProgress(progress.clamp(0, 100), 100);
        }
      } catch (_) {}
    });

    // 监听播放状态变化
    _playlistNotifier.mediaPlayer.stream.playing.listen((playing) async {
      if (!_taskbarReady || !settings.showTaskbarProgress) {
        // 当关闭任务栏进度显示时，重置进度条状态
        try {
          WindowsTaskbar.setProgressMode(TaskbarProgressMode.noProgress);
        } catch (_) {}
        return;
      }

      final bool isVisible = await windowManager.isVisible();
      if (!isVisible) return;

      try {
        WindowsTaskbar.setProgressMode(
          playing ? TaskbarProgressMode.normal : TaskbarProgressMode.paused,
        );
      } catch (_) {}
    });

    // 监听播放完成
    _playlistNotifier.mediaPlayer.stream.completed.listen((completed) async {
      if (!_taskbarReady || !settings.showTaskbarProgress) {
        // 当关闭任务栏进度显示时，重置进度条状态
        try {
          WindowsTaskbar.setProgressMode(TaskbarProgressMode.noProgress);
        } catch (_) {}
        return;
      }

      final bool isVisible = await windowManager.isVisible();
      if (!isVisible) return;

      if (completed) {
        try {
          WindowsTaskbar.setProgress(0, 100);
        } catch (_) {}
      }
    });
  }

  @override
  void dispose() {
    trayManager.removeListener(this);
    _playlistNotifier.removeListener(_updateThumbnailToolbar);
    context.read<SettingsProvider>().removeListener(_onSettingsChanged);
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
    if (!Platform.isLinux) {
      trayManager.popUpContextMenu();
    }
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'show_window') {
      windowManager.show();
    } else if (menuItem.key == 'exit_app') {
      windowManager.close();

      // exit是为了确保即使有后台任务，进程也能立即结束
      // 如果close已经让进程自毁了，这一行就不会执行
      exit(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return MaterialApp(
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('zh', 'CH'), Locale('en', 'US')],
          locale: const Locale('zh', 'CH'),

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

  Timer? _resizeTimer;
  @override
  void onWindowResize() async {
    _resizeTimer?.cancel();
    _resizeTimer = Timer(const Duration(milliseconds: 300), () async {
      final size = await windowManager.getSize();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('window_width', size.width);
      await prefs.setDouble('window_height', size.height);
    });
  }

  Timer? _moveTimer;
  @override
  void onWindowMove() async {
    _moveTimer?.cancel();
    _moveTimer = Timer(const Duration(milliseconds: 300), () async {
      final position = await windowManager.getPosition();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('window_x', position.dx);
      await prefs.setDouble('window_y', position.dy);
    });
  }
}
