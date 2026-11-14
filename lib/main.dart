// NOTE：Flutter 3.47+ 的 material_ui / cupertino_ui 解耦
// https://docs.flutter.dev/release/breaking-changes/material-ui-and-cupertino-ui

// 等待以下包或类似的替代品支持：
// markdown_widget
// silky_scroll
// window_manager
// mesh_gradient
// scrollable_positioned_list

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:system_fonts/system_fonts.dart';
import 'package:window_manager/window_manager.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart'
    show
        ContextMenuTrigger,
        ImageAsset,
        Menu,
        MenuItem,
        MenuItemClickedEvent,
        MenuItemType,
        TrayIcon,
        TrayIconClickedEvent,
        TrayManager;
import 'package:windows_taskbar/windows_taskbar.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'hot_keys.dart';
import 'theme/theme_provider.dart';
import 'layout/app_shell.dart';
import 'page/playlist/playlist_content_notifier.dart';
import 'services/notification_service.dart';
import 'services/update_check_service.dart';
import 'page/setting/settings_provider.dart';
import 'page/setting/setting_page.dart';
import 'src/rust/frb_generated.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'page/statistics_page/statistics_manager.dart';
import 'layout/navigation_notifier.dart';
import 'services/license_service.dart';
import 'window/app_window.dart';
import 'window/single_instance.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SingleInstance.enforceIfEnabled();

  AppLicenses.register();

  // 初始化全局快捷键管理器
  await hotKeyManager.unregisterAll();

  PaintingBinding.instance.imageCache.maximumSize = 200;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 20 * 1024 * 1024;

  MpvAudioKit.ensureInitialized();

  await RustLib.init();

  // 初始化窗口
  final windowState = WindowStateManager(AppWindow.instance);
  final initialSize = await windowState.loadWindowSize();
  final initialPosition = await windowState.loadWindowPosition();

  Future<void> setupWindow() async {
    final window = AppWindow.instance;
    if (window == null) return;

    window.titleBarStyle = TitleBarStyle.hidden;
    window.isWindowControlButtonsVisible = true;

    window.setSize(initialSize.toNative(), false);
    window.center();
    window.minimumSize = const Size(480, 600).toNative();

    if (!Platform.isLinux) {
      window.hasShadow = true;
    }

    // 恢复上次保存的窗口位置
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey('window_x') && prefs.containsKey('window_y')) {
      window.position = initialPosition.toNative();
    }

    window.show();
    window.focus();

    //  添加监听器 保存窗口大小
    windowState.window = window;
    window.addListener(windowState.onWindowEvent);
  }

  if (AppWindow.instance != null) {
    await setupWindow();
  } else {
    // 窗口句柄暂时拿不到（例如 Linux 上窗口还没 realize），等第一帧后再试一次
    debugPrint('暂未获取到主窗口，推迟到首帧后再设置窗口');
    WidgetsBinding.instance.addPostFrameCallback((_) => setupWindow());
  }

  final themeProvider = ThemeProvider();
  await themeProvider.initialize();

  final statsManager = StatisticsManager();
  await statsManager.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider.value(value: themeProvider),
        ChangeNotifierProvider(create: (_) => NotificationService()),
        ChangeNotifierProvider(
          create: (context) => PlaylistContentNotifier(
            context.read<SettingsProvider>(),
            context.read<ThemeProvider>(),
            context.read<NotificationService>(),
          ),
        ),
        ChangeNotifierProvider<StatisticsManager>(
          create: (context) => StatisticsManager(),
        ),
        ChangeNotifierProvider(create: (_) => NavigationNotifier()),
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

class _MyAppState extends State<MyApp> {
  late PlaylistContentNotifier _playlistNotifier;
  SettingsProvider? _settingsProvider;
  StreamSubscription<Duration>? _taskbarPositionSubscription;
  StreamSubscription<bool>? _taskbarPlayingSubscription;
  StreamSubscription<bool>? _taskbarCompletedSubscription;
  bool _taskbarReady = false;
  bool _listenersBound = false;

  // nativeapi 的 TrayIcon 是独立对象，需要一直持有引用
  TrayIcon? _trayIcon;
  Menu? _trayMenu;
  final List<MenuItem> _trayMenuItems = <MenuItem>[];
  bool _traySetup = false;

  @override
  void initState() {
    super.initState();

    _setupTray();

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

    // 启动时自动检查更新
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runStartupUpdateCheck();
    });
  }

  // 初始化系统托盘：图标、提示、右键菜单和点击事件
  void _setupTray() {
    if (_traySetup) return;
    _traySetup = true;

    try {
      if (!TrayManager.instance.isSupported()) return;

      final trayIcon = TrayIcon.create();
      if (trayIcon == null) return;
      _trayIcon = trayIcon;

      final icon = ImageAsset.fromAsset('assets/images/icon/tray_icon.ico');
      if (icon != null) {
        trayIcon.icon = icon;
      }

      if (!Platform.isLinux) {
        trayIcon.setTooltip('MyuneMusic');
      }

      final menu = Menu.create();
      if (menu != null) {
        _trayMenu = menu;
        _addTrayMenuItem(menu, '上一首', () => _playlistNotifier.playPrevious());
        _addTrayMenuItem(
          menu,
          '播放/暂停',
          () => _playlistNotifier.isPlaying
              ? _playlistNotifier.pause()
              : _playlistNotifier.play(),
        );
        _addTrayMenuItem(menu, '下一首', () => _playlistNotifier.playNext());
        menu.addSeparator();
        _addTrayMenuItem(menu, '显示窗口', _showWindow);
        menu.addSeparator();
        _addTrayMenuItem(menu, '退出', () {
          AppWindow.instance?.close();
          // exit 是为了确保即使有后台任务，进程也能立即结束
          exit(0);
        });
        trayIcon.setContextMenu(menu);
        // Windows 上右键弹出菜单；Linux 的面板需要这个触发条件才会导出菜单
        trayIcon.setContextMenuTrigger(ContextMenuTrigger.rightClicked);
      }

      trayIcon.addListener((event) {
        if (event is TrayIconClickedEvent) {
          _showWindow();
        }
      });

      trayIcon.setVisible(true);
    } catch (e) {
      debugPrint('初始化系统托盘失败: $e');
    }
  }

  void _addTrayMenuItem(Menu menu, String label, void Function() onTap) {
    final item = MenuItem.createWithLabelAndType(label, MenuItemType.normal);
    if (item == null) return;
    item.addListener((event) {
      if (event is MenuItemClickedEvent) {
        onTap();
      }
    });
    menu.addItem(item);
    _trayMenuItems.add(item);
  }

  Future<void> _runStartupUpdateCheck() async {
    try {
      final settings = _settingsProvider ?? context.read<SettingsProvider>();
      // 等待设置读取完成，避免拿到默认值
      await settings.initializationFuture;
      if (!mounted || !settings.autoCheckUpdates) return;

      await UpdateCheckService.runSilentCheck(
        currentVersion: appVersion,
        notificationService: context.read<NotificationService>(),
      );
    } catch (e) {
      debugPrint('启动时自动检查更新出现错误: $e');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextPlaylistNotifier = context.read<PlaylistContentNotifier>();
    final nextSettingsProvider = context.read<SettingsProvider>();

    if (_listenersBound) {
      if (identical(_playlistNotifier, nextPlaylistNotifier) &&
          identical(_settingsProvider, nextSettingsProvider)) {
        return;
      }

      if (Platform.isWindows) {
        _playlistNotifier.removeListener(_updateThumbnailToolbar);
      }
      _settingsProvider?.removeListener(_onSettingsChanged);
    }

    _playlistNotifier = nextPlaylistNotifier;
    _settingsProvider = nextSettingsProvider;

    if (Platform.isWindows) {
      _playlistNotifier.addListener(_updateThumbnailToolbar);
    }

    _settingsProvider?.addListener(_onSettingsChanged);
    _listenersBound = true;
  }

  void _onSettingsChanged() {
    try {
      final settings = _settingsProvider ?? context.read<SettingsProvider>();
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
    final settings = _settingsProvider ?? context.read<SettingsProvider>();

    // 监听播放进度变化以更新任务栏进度
    _taskbarPositionSubscription = _playlistNotifier.mediaPlayer.stream.position
        .throttleTime(const Duration(milliseconds: 500))
        .listen((position) async {
          if (!_taskbarReady || !settings.showTaskbarProgress) return;

          final bool isVisible = AppWindow.instance?.isVisible ?? false;
          if (!isVisible) return;

          try {
            final duration = _playlistNotifier.totalDuration;
            if (duration != Duration.zero) {
              final progress =
                  (position.inMilliseconds / duration.inMilliseconds * 100)
                      .round();
              WindowsTaskbar.setProgress(progress.clamp(0, 100), 100);
            }
          } catch (_) {}
        });

    // 监听播放状态变化
    _taskbarPlayingSubscription = _playlistNotifier.mediaPlayer.stream.playing
        .listen((playing) async {
          if (!_taskbarReady || !settings.showTaskbarProgress) {
            // 当关闭任务栏进度显示时，重置进度条状态
            try {
              WindowsTaskbar.setProgressMode(TaskbarProgressMode.noProgress);
            } catch (_) {}
            return;
          }

          final bool isVisible = AppWindow.instance?.isVisible ?? false;
          if (!isVisible) return;

          try {
            WindowsTaskbar.setProgressMode(
              playing ? TaskbarProgressMode.normal : TaskbarProgressMode.paused,
            );
          } catch (_) {}
        });

    // 监听播放完成
    _taskbarCompletedSubscription = _playlistNotifier
        .mediaPlayer
        .stream
        .completed
        .listen((completed) async {
          if (!_taskbarReady || !settings.showTaskbarProgress) {
            // 当关闭任务栏进度显示时，重置进度条状态
            try {
              WindowsTaskbar.setProgressMode(TaskbarProgressMode.noProgress);
            } catch (_) {}
            return;
          }

          final bool isVisible = AppWindow.instance?.isVisible ?? false;
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
    _trayIcon?.dispose();
    _trayIcon = null;
    _trayMenu?.dispose();
    _trayMenu = null;
    _trayMenuItems.clear();
    _taskbarPositionSubscription?.cancel();
    _taskbarPlayingSubscription?.cancel();
    _taskbarCompletedSubscription?.cancel();
    if (_listenersBound) {
      if (Platform.isWindows) {
        _playlistNotifier.removeListener(_updateThumbnailToolbar);
      }
      _settingsProvider?.removeListener(_onSettingsChanged);
    }
    super.dispose();
  }

  void _showWindow() {
    final window = AppWindow.instance;
    if (window == null) return;
    if (window.isMinimized) {
      window.restore();
    }
    window.show();
    window.focus();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        Widget app = MaterialApp(
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
            return DragToResizeArea(
              window: AppWindow.instance,
              child: Hotkeys(child: materialAppChild!),
            );
          },

          home: const AppShell(),
        );

        // 在 Windows 平台上排除语义化
        // https://github.com/flutter/flutter/issues/182444
        // TODO: 待修复
        if (Platform.isWindows) {
          app = ExcludeSemantics(child: app);
        }

        return app;
      },
    );
  }
}

// 管理窗口大小的加载与保存
class WindowStateManager {
  WindowStateManager(this.window);

  Window? window;

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

  Future<void> onWindowEvent(WindowEvent event) async {
    switch (event) {
      case WindowResizedEvent():
        _resizeTimer?.cancel();
        _resizeTimer = Timer(
          const Duration(milliseconds: 300),
          _saveWindowSize,
        );
      case WindowMovedEvent():
        _moveTimer?.cancel();
        _moveTimer = Timer(
          const Duration(milliseconds: 300),
          _saveWindowPosition,
        );
      default:
        break;
    }
  }

  Future<void> _saveWindowSize() async {
    final size = window?.size.toSize();
    if (size == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('window_width', size.width);
    await prefs.setDouble('window_height', size.height);
  }

  Timer? _moveTimer;

  Future<void> _saveWindowPosition() async {
    final position = window?.position.toOffset();
    if (position == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('window_x', position.dx);
    await prefs.setDouble('window_y', position.dy);
  }
}
