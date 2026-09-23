import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../page/setting/settings_provider.dart';

class CustomBackgroundImageLayer extends StatelessWidget {
  const CustomBackgroundImageLayer({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final path = settings.existingBackgroundPath;

    // 未启用、未选择图片或文件已不存在时不绘制任何内容
    if (path == null) {
      return const SizedBox.shrink();
    }

    final image = Image.file(
      File(path),
      fit: BoxFit.cover,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stackTrace) =>
          const SizedBox.expand(child: ColoredBox(color: Colors.transparent)),
    );

    if (settings.isGlassBackgroundMask) {
      return ClipRect(
        child: ImageFiltered(
          imageFilter: ui.ImageFilter.blur(
            sigmaX: settings.backgroundImageBlur,
            sigmaY: settings.backgroundImageBlur,
            // clamp 四周不会发灰
            tileMode: TileMode.clamp,
          ),
          child: image,
        ),
      );
    }

    return image;
  }
}

class CustomBackgroundMaskLayer extends StatelessWidget {
  const CustomBackgroundMaskLayer({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsProvider>();
    final enabled = settings.hasCustomBackgroundImage;
    final double baseAlpha = enabled
        ? switch (settings.backgroundMaskStyle) {
            BackgroundMaskStyle.none => 0.0,
            BackgroundMaskStyle.solid ||
            BackgroundMaskStyle.glass => settings.backgroundMaskOpacity,
          }
        : 1.0;
    final double bottomBoost =
        enabled && settings.backgroundMaskStyle != BackgroundMaskStyle.none
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
