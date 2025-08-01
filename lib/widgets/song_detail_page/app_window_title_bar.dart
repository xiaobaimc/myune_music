import 'package:flutter/material.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';

class AppWindowTitleBar extends StatelessWidget {
  const AppWindowTitleBar({super.key});

  @override
  Widget build(BuildContext context) {
    return WindowTitleBarBox(
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.transparent, // 透明背景以显示模糊效果
        ),
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      Icons.arrow_back,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    tooltip: '返回',
                  ),
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
            Expanded(child: MoveWindow()),
            Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _WindowButton(
                    icon: Icons.remove,
                    onPressed: () => appWindow.minimize(),
                    hoverColor: const Color.fromRGBO(144, 202, 249, 1),
                  ),
                  const SizedBox(width: 2),
                  _WindowButton(
                    icon: Icons.close,
                    onPressed: () => appWindow.close(),
                    hoverColor: const Color.fromRGBO(239, 154, 154, 1),
                  ),
                ],
              ),
            ),
          ],
        ),
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
