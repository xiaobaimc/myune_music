// 音频可视化:https://pub.dev/packages/sonix

import 'dart:async';
import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mesh_gradient/mesh_gradient.dart';
import 'package:colorgram/colorgram.dart';

import '../widgets/lyrics_widget.dart';
import 'playlist/playlist_content_notifier.dart';
import '../widgets/song_detail_page/playbar.dart';
import '../widgets/song_detail_page/app_window_title_bar.dart';
import './setting/settings_provider.dart';
import '../widgets/playing_queue_drawer.dart';
import '../widgets/lyrics_settings_drawer.dart';
import 'playlist/playlist_models.dart';

// 公共模糊背景组件
class BackgroundBlurWidget extends StatefulWidget {
  final Widget child;
  const BackgroundBlurWidget({super.key, required this.child});

  @override
  State<BackgroundBlurWidget> createState() => _BackgroundBlurWidgetState();
}

class _BackgroundBlurWidgetState extends State<BackgroundBlurWidget>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;

  List<Color>? _extractedColors;
  String? _lastSongFilePath;
  bool _isProcessingColor = false;

  // 初始网格位置
  static const List<Offset> _gridPositions = [
    Offset(0.15, 0.2),
    Offset(0.85, 0.15),
    Offset(0.2, 0.85),
    Offset(0.8, 0.8),
  ];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(seconds: 10),
      vsync: this,
    );

    _animation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.linear),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _checkAndUpdateColors(Song? song, bool isDarkTheme) {
    if (song == null || song.albumArt == null) {
      if (_extractedColors != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _extractedColors = null);
        });
      }
      return;
    }

    if (song.filePath == _lastSongFilePath || _isProcessingColor) return;

    _lastSongFilePath = song.filePath;
    _isProcessingColor = true;

    _extractColorsAsync(song, isDarkTheme);
  }

  Future<void> _extractColorsAsync(Song song, bool isDarkTheme) async {
    try {
      final ImageProvider imageProvider = MemoryImage(song.albumArt!);
      final List<CgColor> cgColors = await extractColor(imageProvider, 6);

      if (!mounted || song.filePath != _lastSongFilePath) return;

      final List<Color> adjustedColors = cgColors.map((cg) {
        final rawColor = Color.fromARGB(255, cg.r, cg.g, cg.b);
        final hsl = HSLColor.fromColor(rawColor);

        double newLightness;
        double newSaturation;

        if (isDarkTheme) {
          newLightness = hsl.lightness.clamp(0.08, 0.18);
          newSaturation = hsl.saturation.clamp(0.18, 0.35);
        } else {
          newLightness = hsl.lightness.clamp(0.35, 0.55);
          newSaturation = hsl.saturation.clamp(0.18, 0.38);
        }

        return hsl
            .withLightness(newLightness)
            .withSaturation(newSaturation)
            .toColor();
      }).toList();

      while (adjustedColors.length < 4) {
        adjustedColors.add(
          adjustedColors.isNotEmpty ? adjustedColors.first : Colors.blueGrey,
        );
      }

      if (mounted) {
        setState(() {
          _extractedColors = adjustedColors.sublist(0, 4);
        });
      }
    } catch (e) {
      //
    } finally {
      _isProcessingColor = false;
    }
  }

  List<MeshGradientPoint> _getMeshPoints(bool isDarkTheme) {
    final List<Color> baseColors =
        _extractedColors ??
        (isDarkTheme
            ? const [
                Color(0xFF0B0B0F),
                Color(0xFF08090D),
                Color(0xFF0A0B10),
                Color(0xFF0D0A12),
              ]
            : const [
                Color(0xFFD6D0D2),
                Color(0xFFD0D5D8),
                Color(0xFFD5D8DC),
                Color(0xFFD8D1D6),
              ]);

    return List.generate(_gridPositions.length, (i) {
      return MeshGradientPoint(
        position: _gridPositions[i],
        // 浅色模式下不稀释颜色
        color: baseColors[i].withValues(alpha: isDarkTheme ? 0.28 : 1.0),
      );
    });
  }

  void _manageAnimation(bool shouldAnimate) {
    if (shouldAnimate) {
      if (!_animationController.isAnimating) {
        _animationController.repeat(reverse: true); // 重复播放，反向播放
      }
    } else {
      if (_animationController.isAnimating) {
        _animationController.stop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final useBlurBackground = settings.useBlurBackground;
    final enableDynamicBackground = settings.enableDynamicBackground;

    // 动画开关逻辑，通过延迟到帧后来避免 build 期间的副作用
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _manageAnimation(enableDynamicBackground && useBlurBackground);
      }
    });

    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;

    return Consumer<PlaylistContentNotifier>(
      builder: (context, playlistNotifier, child) {
        final currentSong = playlistNotifier.currentSong;

        _checkAndUpdateColors(currentSong, isDarkTheme);
        // 当没有封面图或用户未启用模糊背景时，使用纯色背景
        if (currentSong?.albumArt == null || !useBlurBackground) {
          return Container(
            color: Theme.of(context).colorScheme.surface,
            child: child,
          );
        }

        if (enableDynamicBackground) {
          final basePoints = _getMeshPoints(isDarkTheme);

          return Stack(
            fit: StackFit.expand,
            children: [
              AnimatedBuilder(
                animation: _animation,
                builder: (context, _) {
                  final List<MeshGradientPoint> animatedPoints = [];
                  const double amplitude = 0.35;
                  final double time = _animation.value * 2 * math.pi;

                  for (int i = 0; i < basePoints.length; i++) {
                    final point = basePoints[i];
                    double offsetX = 0.0;
                    double offsetY = 0.0;

                    if (i == 0) {
                      offsetX = amplitude * math.sin(time);
                      offsetY = amplitude * math.cos(time * 1.2);
                    } else if (i == 1) {
                      offsetX = amplitude * math.cos(time * 0.9);
                      offsetY = amplitude * math.sin(time * 1.1);
                    } else if (i == 2) {
                      offsetX = amplitude * math.sin(time * 1.3);
                      offsetY = amplitude * math.sin(time * 0.8);
                    } else {
                      offsetX = amplitude * math.cos(time * 1.1);
                      offsetY = amplitude * math.cos(time * 1.4);
                    }

                    animatedPoints.add(
                      MeshGradientPoint(
                        position: Offset(
                          (point.position.dx + offsetX).clamp(0.0, 1.0),
                          (point.position.dy + offsetY).clamp(0.0, 1.0),
                        ),
                        color: point.color,
                      ),
                    );
                  }

                  return MeshGradient(
                    points: animatedPoints,
                    options: MeshGradientOptions(
                      blend: 4.0,
                      noiseIntensity: 0.1,
                    ),
                  );
                },
              ),
              Container(
                color: Theme.of(context).colorScheme.surface.withValues(
                  alpha: isDarkTheme ? 0.4 : 0.6,
                ),
              ),
              if (child != null) child,
            ],
          );
        }

        // 静态高斯模糊背景部分
        return Stack(
          fit: StackFit.expand,
          children: [
            ImageFiltered(
              imageFilter: ui.ImageFilter.blur(
                sigmaX: 40,
                sigmaY: 40,
                tileMode: TileMode.decal,
              ),
              child: Image.memory(
                currentSong!.albumArt!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    Container(color: Theme.of(context).colorScheme.surface),
              ),
            ),
            IgnorePointer(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Theme.of(
                        context,
                      ).colorScheme.surface.withValues(alpha: 0.8),
                      Theme.of(
                        context,
                      ).colorScheme.surface.withValues(alpha: 0.8),
                    ],
                  ),
                ),
              ),
            ),
            if (child != null) child,
          ],
        );
      },
      child: widget.child,
    );
  }
}

class SongDetailPage extends StatefulWidget {
  const SongDetailPage({super.key});

  @override
  State<SongDetailPage> createState() => _SongDetailPageState();
}

class _SongDetailPageState extends State<SongDetailPage> {
  bool _isHidden = false;
  Timer? _hideTimer;
  bool _lastSettingValue = false;

  void _startTimer() {
    _cancelTimer();
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() {
          _isHidden = true;
        });
      }
    });
  }

  void _cancelTimer() {
    _hideTimer?.cancel();
    _hideTimer = null;
  }

  void _handleUserInteraction(bool autoHideEnabled) {
    if (!autoHideEnabled) return;
    _cancelTimer();
    if (_isHidden) {
      setState(() {
        _isHidden = false;
      });
    }
    _startTimer();
  }

  @override
  void dispose() {
    _cancelTimer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final autoHideEnabled = settings.autoHidePlayPageComponents;

    // 监听设置变化
    if (autoHideEnabled != _lastSettingValue) {
      _lastSettingValue = autoHideEnabled;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (autoHideEnabled) {
          _startTimer();
        } else {
          _cancelTimer();
          if (mounted && _isHidden) {
            setState(() {
              _isHidden = false;
            });
          }
        }
      });
    }

    // 获取窗口宽高比
    final size = MediaQuery.of(context).size;
    final aspectRatio = size.aspectRatio;
    final isPortrait = aspectRatio <= 1.0; // 竖屏判断

    // 计算窗口分辨率缩放系数
    final double width = size.width > 0 ? size.width : 1150.0;
    final double height = size.height > 0 ? size.height : 620.0;
    final double scale = (math.sqrt(
      (width * height) / (1150.0 * 620.0),
    )).clamp(0.5, 2.0);

    return Listener(
      onPointerDown: (_) => _handleUserInteraction(autoHideEnabled),
      onPointerMove: (_) => _handleUserInteraction(autoHideEnabled),
      onPointerHover: (_) => _handleUserInteraction(autoHideEnabled),
      onPointerSignal: (_) => _handleUserInteraction(autoHideEnabled),
      child: MouseRegion(
        cursor: _isHidden ? SystemMouseCursors.none : MouseCursor.defer,
        onHover: (_) => _handleUserInteraction(autoHideEnabled),
        child: Scaffold(
          endDrawer: const PlayingQueueDrawer(),
          body: BackgroundBlurWidget(
            child: Column(
              children: [
                // 标题栏
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 300),
                  opacity: _isHidden ? 0.0 : 1.0,
                  child: IgnorePointer(
                    ignoring: _isHidden,
                    child: Builder(
                      builder: (BuildContext context) {
                        return AppWindowTitleBar(
                          onSettingsPressed: () {
                            Scaffold.of(context).openDrawer();
                          },
                        );
                      },
                    ),
                  ),
                ),
                // 主内容区域
                Expanded(
                  child: isPortrait
                      ? // 竖屏：显示歌词和底部播放控制
                        Column(
                          children: [
                            // 歌词区域
                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.all(20 * scale),
                                child: Center(
                                  child: Builder(
                                    builder: (context) {
                                      final playlistNotifier = context
                                          .watch<PlaylistContentNotifier>();
                                      final currentLyrics =
                                          playlistNotifier.currentLyrics;
                                      if (currentLyrics.isEmpty) {
                                        return const Center(
                                          child: Text(
                                            '无歌词数据',
                                            style: TextStyle(
                                              fontSize: 20,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        );
                                      }
                                      return StreamBuilder<int>(
                                        stream: playlistNotifier
                                            .lyricLineIndexStream,
                                        initialData: playlistNotifier
                                            .currentLyricLineIndex,
                                        builder: (context, snapshot) {
                                          return LyricsView(
                                            maxLinesPerLyric: context
                                                .watch<SettingsProvider>()
                                                .maxLinesPerLyric,
                                            onTapLine: (index) {
                                              final seekTime =
                                                  currentLyrics[index]
                                                      .timestamp;
                                              playlistNotifier.mediaPlayer.seek(
                                                seekTime,
                                              );
                                            },
                                          );
                                        },
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                            // 底部播放控制栏
                            AnimatedOpacity(
                              duration: const Duration(milliseconds: 300),
                              opacity: _isHidden ? 0.0 : 1.0,
                              child: IgnorePointer(
                                ignoring: _isHidden,
                                child: const PortraitPlaybar(),
                              ),
                            ),
                          ],
                        )
                      : // 横屏：保留原有布局
                        Row(
                          children: [
                            SizedBox(width: 80 * scale),
                            // 左侧歌曲信息和播放控制区域
                            Expanded(
                              flex: 2,
                              child: Padding(
                                padding: EdgeInsets.only(
                                  top: 10 * scale,
                                  bottom: 55 * scale,
                                ),
                                child: Center(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      // 歌曲信息
                                      Consumer<PlaylistContentNotifier>(
                                        builder: (context, playlistNotifier, child) {
                                          final currentSong =
                                              playlistNotifier.currentSong;
                                          return LayoutBuilder(
                                            builder: (context, constraints) {
                                              final w = constraints.maxWidth;
                                              // 基于窗口分辨率缩放系数计算封面大小，同时不超过父容器宽度
                                              final double baseImageSize =
                                                  310.0 * scale;
                                              final double imageSize = math.min(
                                                w,
                                                baseImageSize,
                                              );

                                              // 根据图片大小计算字体大小
                                              final double titleFontSize =
                                                  (imageSize * 0.05).clamp(
                                                    20.0,
                                                    32.0,
                                                  );
                                              final double artistFontSize =
                                                  (imageSize * 0.03).clamp(
                                                    14.0,
                                                    28.0,
                                                  );

                                              final borderRadius =
                                                  BorderRadius.circular(12);
                                              const Widget fallback = Icon(
                                                Icons.music_note,
                                                size: 72,
                                                color: Colors.black12,
                                              );

                                              return Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.center,
                                                children: [
                                                  SizedBox(
                                                    width: imageSize,
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .stretch,
                                                      children: [
                                                        SizedBox(
                                                          height: 45 * scale,
                                                        ),
                                                        // 歌曲标题
                                                        AnimatedAlign(
                                                          duration:
                                                              const Duration(
                                                                milliseconds:
                                                                    500,
                                                              ),
                                                          curve:
                                                              Curves.easeInOut,
                                                          alignment: _isHidden
                                                              ? Alignment
                                                                    .centerLeft
                                                              : Alignment
                                                                    .center,
                                                          child: AnimatedPadding(
                                                            duration:
                                                                const Duration(
                                                                  milliseconds:
                                                                      500,
                                                                ),
                                                            curve: Curves
                                                                .easeInOut,
                                                            padding:
                                                                EdgeInsets.only(
                                                                  left:
                                                                      _isHidden
                                                                      ? 2.0 *
                                                                            scale
                                                                      : 0.0,
                                                                ),
                                                            child: Text(
                                                              currentSong
                                                                      ?.title ??
                                                                  '未知歌曲',
                                                              style: TextStyle(
                                                                fontSize:
                                                                    titleFontSize,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                              ),
                                                              textAlign:
                                                                  _isHidden
                                                                  ? TextAlign
                                                                        .left
                                                                  : TextAlign
                                                                        .center,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                              maxLines: 1,
                                                              softWrap: false,
                                                            ),
                                                          ),
                                                        ),
                                                        // 艺术家
                                                        AnimatedAlign(
                                                          duration:
                                                              const Duration(
                                                                milliseconds:
                                                                    500,
                                                              ),
                                                          curve:
                                                              Curves.easeInOut,
                                                          alignment: _isHidden
                                                              ? Alignment
                                                                    .centerLeft
                                                              : Alignment
                                                                    .center,
                                                          child: AnimatedPadding(
                                                            duration:
                                                                const Duration(
                                                                  milliseconds:
                                                                      500,
                                                                ),
                                                            curve: Curves
                                                                .easeInOut,
                                                            padding:
                                                                EdgeInsets.only(
                                                                  left:
                                                                      _isHidden
                                                                      ? 2.0 *
                                                                            scale
                                                                      : 0.0,
                                                                ),
                                                            child: Text(
                                                              currentSong !=
                                                                      null
                                                                  ? context
                                                                            .watch<
                                                                              SettingsProvider
                                                                            >()
                                                                            .showAlbumName
                                                                        ? '${currentSong.artist} - ${currentSong.album}'
                                                                        : currentSong
                                                                              .artist
                                                                  : '未知歌手',
                                                              style: TextStyle(
                                                                fontSize:
                                                                    artistFontSize,
                                                                color:
                                                                    Theme.of(
                                                                          context,
                                                                        )
                                                                        .colorScheme
                                                                        .onSurface
                                                                        .withValues(
                                                                          alpha:
                                                                              0.7,
                                                                        ),
                                                              ),
                                                              textAlign:
                                                                  _isHidden
                                                                  ? TextAlign
                                                                        .left
                                                                  : TextAlign
                                                                        .center,
                                                              maxLines: 1,
                                                              overflow:
                                                                  TextOverflow
                                                                      .clip,
                                                              softWrap: false,
                                                            ),
                                                          ),
                                                        ),
                                                        SizedBox(
                                                          height: 6 * scale,
                                                        ),
                                                        // 专辑封面
                                                        SizedBox.square(
                                                          dimension: imageSize,
                                                          child: DecoratedBox(
                                                            decoration: BoxDecoration(
                                                              borderRadius:
                                                                  borderRadius,
                                                              boxShadow: [
                                                                BoxShadow(
                                                                  color: Colors
                                                                      .black
                                                                      .withValues(
                                                                        alpha:
                                                                            0.3,
                                                                      ),
                                                                  blurRadius:
                                                                      12,
                                                                  offset:
                                                                      const Offset(
                                                                        0,
                                                                        2,
                                                                      ),
                                                                ),
                                                              ],
                                                            ),
                                                            child: ClipRRect(
                                                              borderRadius:
                                                                  borderRadius,
                                                              child: AspectRatio(
                                                                aspectRatio: 1,
                                                                child:
                                                                    (currentSong?.albumArt !=
                                                                            null &&
                                                                        currentSong!
                                                                            .albumArt!
                                                                            .isNotEmpty)
                                                                    ? Image.memory(
                                                                        currentSong
                                                                            .albumArt!,
                                                                        fit: BoxFit
                                                                            .cover,
                                                                        errorBuilder:
                                                                            (
                                                                              _,
                                                                              __,
                                                                              ___,
                                                                            ) =>
                                                                                fallback,
                                                                      )
                                                                    : const ColoredBox(
                                                                        color: Colors
                                                                            .black12,
                                                                        child: Center(
                                                                          child:
                                                                              fallback,
                                                                        ),
                                                                      ),
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  SizedBox(height: 8 * scale),
                                                  // 播放控制区域
                                                  AnimatedOpacity(
                                                    duration: const Duration(
                                                      milliseconds: 300,
                                                    ),
                                                    opacity: _isHidden
                                                        ? 0.0
                                                        : 1.0,
                                                    child: IgnorePointer(
                                                      ignoring: _isHidden,
                                                      child: const Playbar(),
                                                    ),
                                                  ),
                                                ],
                                              );
                                            },
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            // 歌词区域
                            Expanded(
                              flex: 3,
                              child: Padding(
                                padding: EdgeInsets.only(
                                  left: 80 * scale,
                                  right: 80 * scale,
                                  top: 20 * scale,
                                  bottom: 40 * scale,
                                ),
                                child: Center(
                                  child: Builder(
                                    builder: (context) {
                                      final playlistNotifier = context
                                          .watch<PlaylistContentNotifier>();
                                      final currentLyrics =
                                          playlistNotifier.currentLyrics;
                                      if (currentLyrics.isEmpty) {
                                        return const Center(
                                          child: Text(
                                            '无歌词数据',
                                            style: TextStyle(
                                              fontSize: 20,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        );
                                      }
                                      return StreamBuilder<int>(
                                        stream: playlistNotifier
                                            .lyricLineIndexStream,
                                        initialData: playlistNotifier
                                            .currentLyricLineIndex,
                                        builder: (context, snapshot) {
                                          return LyricsView(
                                            maxLinesPerLyric: context
                                                .watch<SettingsProvider>()
                                                .maxLinesPerLyric,
                                            onTapLine: (index) {
                                              final seekTime =
                                                  currentLyrics[index]
                                                      .timestamp;
                                              playlistNotifier.mediaPlayer.seek(
                                                seekTime,
                                              );
                                            },
                                          );
                                        },
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
          drawer: const LyricsSettingsDrawer(),
        ),
      ),
    );
  }
}
