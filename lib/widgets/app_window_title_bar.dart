import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:provider/provider.dart';

import '../page/setting/settings_provider.dart';

class AppWindowTitleBar extends StatelessWidget {
  const AppWindowTitleBar({super.key});

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final Color titleBarBackgroundColor = colorScheme.surface;
    return Container(
      height: 31.0,
      color: titleBarBackgroundColor,
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                ColorFiltered(
                  colorFilter: ColorFilter.mode(
                    Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : Colors.black,
                    BlendMode.srcIn,
                  ),
                  child: Image.asset(
                    'assets/images/icon/icon.png',
                    width: 21,
                    height: 21,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  "MyuneMusic",
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          Expanded(
            child: DragToMoveArea(
              // 这里的Container是为了保证这个区域可以拖动
              child: Container(),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _WindowButton(
                  icon: Icons.remove,
                  onPressed: () {
                    final settings = Provider.of<SettingsProvider>(
                      context,
                      listen: false,
                    );
                    if (settings.minimizeToTray) {
                      windowManager.hide();
                    } else {
                      windowManager.minimize();
                    }
                  },
                  hoverColor: const Color.fromRGBO(144, 202, 249, 1),
                ),
                const SizedBox(width: 2),
                _WindowButton(
                  icon: Icons.close,
                  onPressed: () => windowManager.close(),
                  hoverColor: const Color.fromRGBO(239, 154, 154, 1),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WindowButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final Color hoverColor;
  final Color hoverBackgroundColor;

  const _WindowButton({
    required this.icon,
    required this.onPressed,
    this.hoverColor = const Color(0xFF404040),
    // ignore: unused_element_parameter
    this.hoverBackgroundColor = Colors.transparent,
  });

  @override
  _WindowButtonState createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    final Color defaultIconColor = brightness == Brightness.dark
        ? Colors.white
        : Colors.black;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (event) {
        setState(() {
          _isHovering = true;
        });
      },
      onExit: (event) {
        setState(() {
          _isHovering = false;
        });
      },
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          width: 46,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _isHovering
                ? (widget.hoverBackgroundColor)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10.0),
          ),
          child: Icon(
            widget.icon,
            color: _isHovering ? widget.hoverColor : defaultIconColor,
            size: 20,
          ),
        ),
        onTapDown: (_) {}, // 空的回调，用于确保GestureDetector在某些情况下能正确响应
      ),
    );
  }
}
