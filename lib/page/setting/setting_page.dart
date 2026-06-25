import 'package:flutter/material.dart';

import 'tabs/general_tab.dart';
import 'tabs/personalization_tab.dart';
import 'tabs/playback_page_tab.dart';
import 'tabs/playback_settings_tab.dart';
import 'tabs/hotkeys_tab.dart';
import 'tabs/advanced_tab.dart';

// 定义应用版本号常量
const String appVersion = '0.9.1';

class SettingPage extends StatefulWidget {
  const SettingPage({super.key});

  @override
  State<SettingPage> createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // 左侧导航栏
        Container(
          width: 150,
          color: Colors.transparent,
          child: Column(
            children: [
              _SettingNavItem(
                index: 0,
                title: '常规',
                icon: Icons.settings_outlined,
                isSelected: _selectedIndex == 0,
                onTap: () => setState(() => _selectedIndex = 0),
              ),
              _SettingNavItem(
                index: 1,
                title: '个性化',
                icon: Icons.palette_outlined,
                isSelected: _selectedIndex == 1,
                onTap: () => setState(() => _selectedIndex = 1),
              ),
              _SettingNavItem(
                index: 2,
                title: '播放页',
                icon: Icons.play_circle_outline,
                isSelected: _selectedIndex == 2,
                onTap: () => setState(() => _selectedIndex = 2),
              ),
              _SettingNavItem(
                index: 3,
                title: '播放设置',
                icon: Icons.volume_up_outlined,
                isSelected: _selectedIndex == 3,
                onTap: () => setState(() => _selectedIndex = 3),
              ),
              _SettingNavItem(
                index: 4,
                title: '快捷键',
                icon: Icons.keyboard_outlined,
                isSelected: _selectedIndex == 4,
                onTap: () => setState(() => _selectedIndex = 4),
              ),
              _SettingNavItem(
                index: 5,
                title: '高级',
                icon: Icons.construction_outlined,
                isSelected: _selectedIndex == 5,
                onTap: () => setState(() => _selectedIndex = 5),
              ),
            ],
          ),
        ),
        // 垂直分割线
        VerticalDivider(
          width: 1,
          thickness: 1,
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        // 右侧实际设置项
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 80),
            transitionBuilder: (Widget child, Animation<double> animation) {
              return FadeTransition(opacity: animation, child: child);
            },
            child: () {
              switch (_selectedIndex) {
                case 0:
                  return const GeneralTab(key: ValueKey('general'));
                case 1:
                  return const PersonalizationTab(key: ValueKey('personalization'));
                case 2:
                  return const PlaybackPageTab(key: ValueKey('playback'));
                case 3:
                  return const PlaybackSettingsTab(key: ValueKey('playback_settings'));
                case 4:
                  return const HotkeysTab(key: ValueKey('hotkeys'));
                case 5:
                  return const AdvancedTab(key: ValueKey('advanced'));
                default:
                  return const SizedBox.shrink();
              }
            }(),
          ),
        ),
      ],
    );
  }
}

class _SettingNavItem extends StatefulWidget {
  final int index;
  final String title;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _SettingNavItem({
    required this.index,
    required this.title,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_SettingNavItem> createState() => _SettingNavItemState();
}

class _SettingNavItemState extends State<_SettingNavItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: Material(
        color: widget.isSelected
            ? colorScheme.primary.withValues(alpha: 0.1)
            : _isHovered
            ? Colors.grey.withValues(alpha: 0.1)
            : Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          child: ListTile(
            horizontalTitleGap: 8,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            leading: Icon(
              widget.icon,
              size: 20,
              color: widget.isSelected
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
            title: AnimatedScale(
              duration: const Duration(milliseconds: 200),
              scale: widget.isSelected ? 1.05 : 1.0,
              alignment: Alignment.centerLeft,
              child: Text(
                widget.title,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: widget.isSelected ? colorScheme.primary : null,
                ),
              ),
            ),
            selected: widget.isSelected,
          ),
        ),
      ),
    );
  }
}
