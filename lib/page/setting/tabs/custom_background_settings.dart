import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:colorgram/colorgram.dart';
import 'package:provider/provider.dart';

import '../../../services/notification_service.dart';
import '../../../theme/theme_provider.dart';
import '../settings_provider.dart';
import 'info_icon.dart';

class CustomBackgroundSettings extends StatefulWidget {
  const CustomBackgroundSettings({super.key});

  @override
  State<CustomBackgroundSettings> createState() =>
      _CustomBackgroundSettingsState();
}

class _CustomBackgroundSettingsState extends State<CustomBackgroundSettings> {
  bool _picking = false;
  bool _applyingThemeColor = false;

  Future<void> _applyBackgroundThemeColor() async {
    if (_applyingThemeColor) return;

    // 统一使用项目的 NotificationService（而非 SnackBar）
    final notification = context.read<NotificationService>();
    final path = context.read<SettingsProvider>().existingBackgroundPath;
    if (path == null) {
      notification.error('请先选择背景图片');
      return;
    }

    setState(() => _applyingThemeColor = true);
    try {
      final colors = await extractColor(FileImage(File(path)), 1);
      if (!mounted) return;

      if (colors.isEmpty) {
        notification.error('未能从该背景图中提取到主色调');
        return;
      }

      final dominant = colors.first;
      final color = Color.fromRGBO(dominant.r, dominant.g, dominant.b, 1.0);

      // 动态主题配色会持续用歌曲封面覆盖种子色，先关闭它
      final settings = context.read<SettingsProvider>();
      if (settings.useDynamicColor) {
        settings.setUseDynamicColor(false);
      }

      await context.read<ThemeProvider>().setSeedColor(color, isManual: true);

      if (!mounted) return;
      notification.info('已根据背景图应用主题配色');
    } catch (e) {
      if (!mounted) return;
      notification.error('提取背景图主色调失败：$e');
    } finally {
      if (mounted) setState(() => _applyingThemeColor = false);
    }
  }

  Future<void> _pickBackgroundImage() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'bmp', 'gif', 'jfif'],
        allowMultiple: false,
        dialogTitle: '选择背景图片',
        lockParentWindow: true,
      );

      final path = result?.files.single.path;
      if (path == null || !mounted) return;

      final notification = context.read<NotificationService>();
      if (!File(path).existsSync()) {
        notification.error('选择的图片文件不存在');
        return;
      }

      context.read<SettingsProvider>().setCustomBackgroundPath(path);
    } catch (e) {
      if (!mounted) return;
      context.read<NotificationService>().error('选择背景图片失败：$e');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _clearBackgroundImage() {
    context.read<SettingsProvider>().setCustomBackgroundPath(null);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final path = settings.customBackgroundPath;
    final hasImage = path != null && path.isNotEmpty;
    // 图片可能被删除或移动，此时界面会自动回退为默认外观
    final fileMissing = hasImage && !File(path).existsSync();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 总开关
        SwitchListTile(
          title: Row(
            children: [
              Text('启用自定义背景图', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(width: 4),
              const InfoIcon('对于大多数图片来说，深色模式的视觉效果会显著优于浅色模式'),
            ],
          ),
          value: settings.enableCustomBackground,
          onChanged: (value) {
            context.read<SettingsProvider>().setEnableCustomBackground(value);
          },
        ),

        // 背景图片
        _buildRow(
          label: '背景图片',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasImage) ...[
                TextButton(
                  onPressed: _clearBackgroundImage,
                  child: const Text('清除'),
                ),
                const SizedBox(width: 8),
              ],
              ElevatedButton.icon(
                onPressed: _picking ? null : _pickBackgroundImage,
                icon: const Icon(Icons.image_outlined, size: 20),
                label: Text(_picking ? '选择中...' : (hasImage ? '更换图片' : '选择图片')),
              ),
            ],
          ),
        ),
        // 当前背景图路径/失效提示
        if (hasImage)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              fileMissing ? '图片已失效或被移动，请重新选择' : path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: fileMissing ? Theme.of(context).colorScheme.error : null,
              ),
            ),
          ),

        // 从背景图提取主色调作为主题配色
        _buildRow(
          label: '提取主题配色',
          info: '从选择的图片中提取一个主要颜色作为主题配色\n使用后会关闭"动态主题配色"',
          trailing: ElevatedButton.icon(
            onPressed: (hasImage && !fileMissing && !_applyingThemeColor)
                ? _applyBackgroundThemeColor
                : null,
            icon: const Icon(Icons.palette_outlined, size: 20),
            label: Text(_applyingThemeColor ? '提取中...' : '提取配色'),
          ),
        ),

        // 遮罩样式
        _buildRow(
          label: '背景遮罩样式',
          info:
              '无遮罩：不加任何覆盖，背景图以原始色彩显示\n'
              '普通遮罩：用主题底色半透明覆盖背景图，风格与主题一致\n'
              '毛玻璃遮罩：先把背景图整体模糊，再用更薄的遮罩覆盖',

          trailing: SegmentedButton<BackgroundMaskStyle>(
            style: const ButtonStyle(
              padding: WidgetStatePropertyAll(EdgeInsets.zero),
              visualDensity: VisualDensity.compact,
              minimumSize: WidgetStatePropertyAll(Size(0, 0)),
            ),
            segments: const [
              ButtonSegment(value: BackgroundMaskStyle.none, label: Text('无')),
              ButtonSegment(
                value: BackgroundMaskStyle.solid,
                label: Text('普通'),
              ),
              ButtonSegment(
                value: BackgroundMaskStyle.glass,
                label: Text('毛玻璃'),
              ),
            ],
            selected: {settings.backgroundMaskStyle},
            showSelectedIcon: false,
            onSelectionChanged: (selection) {
              if (selection.isEmpty) return;
              context.read<SettingsProvider>().setBackgroundMaskStyle(
                selection.first,
              );
            },
          ),
        ),

        if (settings.backgroundMaskStyle != BackgroundMaskStyle.none)
          _buildOpacitySlider(context, settings),

        if (settings.isGlassBackgroundMask) _buildBlurSlider(context, settings),

        // 以下两个不透明度交给用户自行调节
        // 适合的数值差异很大，很难用一个固定值满足所有图片
        if (settings.hasCustomBackgroundImage) ...[
          const Divider(height: 16),
          _buildOpacityTile(
            title: '侧边栏不透明度',
            info: '左侧导航栏背景的不透明度',
            value: settings.railSurfaceOpacity,
            onChanged: (v) {
              context.read<SettingsProvider>().setRailSurfaceOpacity(v);
            },
          ),
          _buildOpacityTile(
            title: '卡片不透明度',
            info: '专辑卡片、统计卡片等背景的不透明度',
            value: settings.panelSurfaceOpacity,
            onChanged: (v) {
              context.read<SettingsProvider>().setPanelSurfaceOpacity(v);
            },
          ),
        ],
      ],
    );
  }

  Widget _buildRow({
    required String label,
    String? info,
    bool infoAfter = false,
    required Widget trailing,
  }) {
    final Widget? infoIcon = info == null ? null : InfoIcon(info);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // 标题一侧占满剩余空间，从而把控件稳定推到最右侧
          Expanded(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (infoIcon != null && !infoAfter) ...[
                  const SizedBox(width: 4),
                  infoIcon,
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          trailing,
          if (infoIcon != null && infoAfter) ...[
            const SizedBox(width: 4),
            infoIcon,
          ],
        ],
      ),
    );
  }

  /// 0~1 的不透明度滑块（侧边栏 / 卡片共用）
  Widget _buildOpacityTile({
    required String title,
    required String info,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    final double clamped = value.clamp(0.0, 1.0);
    return ListTile(
      title: Row(
        children: [Text(title), const SizedBox(width: 4), InfoIcon(info)],
      ),
      subtitle: Row(
        children: [
          Expanded(
            child: Slider(
              min: 0.0,
              max: 1.0,
              divisions: 100,
              value: clamped,
              label: clamped.toStringAsFixed(2),
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(clamped.toStringAsFixed(2), textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }

  Widget _buildOpacitySlider(BuildContext context, SettingsProvider settings) {
    // 普通遮罩与毛玻璃遮罩共用同一个取值范围：遮罩强度与遮罩样式无关
    // 毛玻璃只负责额外模糊背景图
    const double min = SettingsProvider.minBackgroundMaskOpacity;
    const double max = 1.0;
    final double value = settings.backgroundMaskOpacity.clamp(min, max);

    return ListTile(
      title: const Row(
        children: [
          Text('背景遮罩不透明度'),
          SizedBox(width: 4),
          InfoIcon('数值越高，背景图越淡、文字越清晰；数值越低，背景图越明显\n该数值对普通遮罩与毛玻璃遮罩的含义完全相同'),
        ],
      ),
      subtitle: Row(
        children: [
          Expanded(
            child: Slider(
              min: min,
              max: max,
              divisions: ((max - min) * 100).round(),
              value: value,
              label: value.toStringAsFixed(2),
              onChanged: (v) {
                context.read<SettingsProvider>().setBackgroundMaskOpacity(v);
              },
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(value.toStringAsFixed(2), textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }

  Widget _buildBlurSlider(BuildContext context, SettingsProvider settings) {
    final value = settings.backgroundImageBlur;

    return ListTile(
      title: const Row(
        children: [
          Text('毛玻璃模糊强度'),
          SizedBox(width: 4),
          InfoIcon('数值越高，背景图越模糊；数值为 0 时等同普通遮罩'),
        ],
      ),
      subtitle: Row(
        children: [
          Expanded(
            child: Slider(
              min: 0.0,
              max: 60.0,
              divisions: 60,
              value: value.clamp(0.0, 60.0),
              label: value.toStringAsFixed(0),
              onChanged: (v) {
                context.read<SettingsProvider>().setBackgroundImageBlur(v);
              },
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(value.toStringAsFixed(0), textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}
