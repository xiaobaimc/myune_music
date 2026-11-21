// NOTE：Flutter 3.47+ 的 material_ui / cupertino_ui 解耦
// https://docs.flutter.dev/release/breaking-changes/material-ui-and-cupertino-ui
//
// 本项目自身代码已迁移到 package:material_ui。window_manager / tray_manager /
// hotkey_manager 也已升级到支持 material_ui 的版本（0.7 / 0.9 / 0.4）。
//
// 仍有以下依赖基于 package:flutter/material.dart，通过官方提供的
// MaterialUiCompatibilityBridge 做 Theme / Localizations 桥接
// （见下方 MaterialApp.builder），等它们支持 material_ui 后可以移除：
//   - markdown_widget
//   - silky_scroll
//   - mesh_gradient
//   - scrollable_positioned_list

import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
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
import 'window/app_freeze.dart';
import 'window/app_window.dart';
import 'window/single_instance.dart';

/// 当前窗口状态管理器，供 MaterialApp.builder 里上报 Flutter 视图尺寸用。
WindowStateManager? _windowState;

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
  _windowState = windowState;
  final initialSize = await windowState.loadWindowSize();
  final initialPosition = await windowState.loadWindowPosition();

  Future<void> setupWindow() async {
    final window = AppWindow.instance;
    if (window == null) return;

    window.titleBarStyle = TitleBarStyle.hidden;
    window.isWindowControlButtonsVisible = true;

    if (Platform.isLinux) {
      // 与保存值同义：Flutter 视图尺寸 == 窗口内容区尺寸
      window.contentSize = initialSize.toNative();
    } else {
      window.setSize(initialSize.toNative(), false);
    }
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

    if (Platform.isLinux) {
      // nativeapi 在 Linux/Wayland 上不保证 resize 立即生效，也不保证 resize 事件会送达
      final confirmed = await _waitForLinuxViewSize(window, initialSize);
      if (!confirmed) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Timer(const Duration(milliseconds: 300), () {
            window.contentSize = initialSize.toNative();
          });
        });
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Timer(
          const Duration(milliseconds: 1200),
          windowState.enableViewSizePersistence,
        );
      });
    }
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
          supportedLocales: const [Locale('zh', 'CH'), Locale('en', 'US')],
          locale: const Locale('zh', 'CH'),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,

          debugShowCheckedModeBanner: false,
          title: 'MyuneMusic',
          theme: themeProvider.lightThemeData,
          darkTheme: themeProvider.darkThemeData,
          themeMode: themeProvider.themeMode,
          builder: (context, materialAppChild) {
            // 项目已迁移到 package:material_ui，但下面这些依赖仍基于
            // package:flutter/material.dart；用官方提供的桥接把 material_ui 的
            // Theme / Localizations 映射过去，等它们支持 material_ui 后删掉：
            // markdown_widget / silky_scroll / mesh_gradient /
            // scrollable_positioned_list
            // ignore: deprecated_member_use
            final bridged = MaterialUiCompatibilityBridge(
              child: materialAppChild!,
            );
            final content = Hotkeys(child: bridged);
            // Linux 窗口尺寸以 Flutter 视图的实际布局尺寸为准
            final measured = Platform.isLinux
                ? LayoutBuilder(
                    builder: (context, constraints) {
                      _windowState?.noteViewSize(
                        Size(constraints.maxWidth, constraints.maxHeight),
                      );
                      return content;
                    },
                  )
                : content;
            return AppFreezeGate(
              child: DragToResizeArea(
                window: AppWindow.instance,
                child: measured,
              ),
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

Future<bool> _waitForLinuxViewSize(Window window, Size target) async {
  bool matches() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) {
      // 拿不到视图信息时不阻塞启动
      return true;
    }
    final view = views.first;
    final ratio = view.devicePixelRatio;
    if (ratio <= 0) return true;
    final size = view.physicalSize / ratio;
    return (size.width - target.width).abs() <= 1 &&
        (size.height - target.height).abs() <= 1;
  }

  for (var i = 0; i < 13; i++) {
    if (matches()) return true;
    if (i > 0 && i % 3 == 0) {
      window.contentSize = target.toNative();
    }
    await Future<void>.delayed(const Duration(milliseconds: 30));
  }
  return matches();
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

  /// Flutter 视图的最新布局尺寸
  Size? _viewSize;
  Timer? _viewSizeSaveTimer;

  bool _viewSizePersistenceEnabled = false;

  void enableViewSizePersistence() {
    // 只启用写盘，不立即写入
    _viewSizePersistenceEnabled = true;
  }

  void noteViewSize(Size size) {
    if (!Platform.isLinux) return;
    if (size.width <= 0 || size.height <= 0) return;
    final previous = _viewSize;
    if (previous != null &&
        (previous.width - size.width).abs() < 0.5 &&
        (previous.height - size.height).abs() < 0.5) {
      return;
    }
    _viewSize = size;
    if (!_viewSizePersistenceEnabled) return;
    _viewSizeSaveTimer?.cancel();
    _viewSizeSaveTimer = Timer(
      const Duration(milliseconds: 500),
      () => _persistViewSize(size),
    );
  }

  Future<void> _persistViewSize(Size size) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('window_width', size.width);
    await prefs.setDouble('window_height', size.height);
  }

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
    // Linux 走 noteViewSize 的视图尺寸，不使用 nativeapi 的 Window.size
    if (Platform.isLinux) return;
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
