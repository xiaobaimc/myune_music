import 'dart:io';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../page/setting/settings_provider.dart';

class CustomBackgroundImageLayer extends StatelessWidget {
  const CustomBackgroundImageLayer({super.key});

  @override
  Widget build(BuildContext context) {
    final (path, isGlass, blur) = context
        .select<SettingsProvider, (String?, bool, double)>(
          (s) => (
            s.existingBackgroundPath,
            s.isGlassBackgroundMask,
            s.backgroundImageBlur,
          ),
        );

    // 未启用、未选择图片或文件已不存在时不绘制任何内容
    if (path == null) {
      return const SizedBox.shrink();
    }

    // 按当前显示器物理宽度限制解码上限，避免 4K/8K 背景图撑爆 ImageCache
    // 同时与窗口拖拽解耦，避免调整窗口大小时每帧重新解码图片
    final displayWidth = View.of(context).display.size.width.round();
    final int targetCacheWidth = (isGlass && blur >= 3.0)
        ? (displayWidth > 0 ? displayWidth.clamp(480, 960) : 960)
        : (displayWidth > 0 ? displayWidth.clamp(960, 1920) : 1920);

    final image = Image.file(
      File(path),
      fit: BoxFit.cover,
      cacheWidth: targetCacheWidth,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stackTrace) =>
          const SizedBox.expand(child: ColoredBox(color: Colors.transparent)),
    );

    if (isGlass && blur > 0) {
      return RepaintBoundary(
        child: ClipRect(
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(
              sigmaX: blur,
              sigmaY: blur,
              // clamp 四周不会发灰
              tileMode: TileMode.clamp,
            ),
            child: image,
          ),
        ),
      );
    }

    return RepaintBoundary(child: image);
  }
}

class CustomBackgroundMaskLayer extends StatelessWidget {
  const CustomBackgroundMaskLayer({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (enabled, maskStyle, maskOpacity) = context
        .select<SettingsProvider, (bool, BackgroundMaskStyle, double)>(
          (s) => (
            s.hasCustomBackgroundImage,
            s.backgroundMaskStyle,
            s.backgroundMaskOpacity,
          ),
        );
    final double baseAlpha = enabled
        ? switch (maskStyle) {
            BackgroundMaskStyle.none => 0.0,
            BackgroundMaskStyle.solid ||
            BackgroundMaskStyle.glass => maskOpacity,
          }
        : 1.0;
    final double bottomBoost = enabled && maskStyle != BackgroundMaskStyle.none
        ? _maskGradientBoost
        : 0.0;

    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colorScheme.surface.withValues(alpha: baseAlpha),
              colorScheme.surface.withValues(
                alpha: (baseAlpha + bottomBoost).clamp(0.0, 1.0),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 底部额外增加遮罩量
  static const double _maskGradientBoost = 0.12;
}

class CustomBackgroundSurfaces {
  const CustomBackgroundSurfaces._();

  static Color transparentWhenEnabled(
    SettingsProvider settings,
    Color fallback,
  ) {
    return settings.hasCustomBackgroundImage ? Colors.transparent : fallback;
  }

  static Color railColor(SettingsProvider settings, Color fallback) {
    if (!settings.hasCustomBackgroundImage) return fallback;
    return _applyOpacity(fallback, settings.railSurfaceOpacity);
  }

  static Color panelColor(SettingsProvider settings, Color fallback) {
    if (!settings.hasCustomBackgroundImage) return fallback;
    return _applyOpacity(fallback, settings.panelSurfaceOpacity);
  }

  static Color _applyOpacity(Color fallback, double opacity) {
    if (opacity >= 1.0) return fallback;
    if (opacity <= 0.0) return Colors.transparent;
    return fallback.withValues(alpha: opacity);
  }

  static double cardElevationOverBackground(SettingsProvider settings) {
    return settings.hasCustomBackgroundImage
        ? CardElevation.flattened
        : CardElevation.materialDefault;
  }

  static Color? materialColor(SettingsProvider settings) {
    return settings.hasCustomBackgroundImage ? Colors.transparent : null;
  }
}

class CardElevation {
  const CardElevation._();

  static const double materialDefault = 1.0;

  static const double flattened = 0.0;
}
