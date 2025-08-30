import 'package:flutter/material.dart';
import '../page/playlist/playlist_content_notifier.dart';

class PlayModeButton extends StatefulWidget {
  final PlayMode playMode;
  final VoidCallback onPressed;
  final Color color;
  final Color activeColor;

  const PlayModeButton({
    super.key,
    required this.playMode,
    required this.onPressed,
    required this.color,
    required this.activeColor,
  });

  @override
  State<PlayModeButton> createState() => _PlayModeButtonState();
}

class _PlayModeButtonState extends State<PlayModeButton> {
  @override
  Widget build(BuildContext context) {
    IconData icon;
    String tooltip;
    Color iconColor = widget.color;

    if (widget.playMode == PlayMode.shuffle) {
      icon = Icons.shuffle;
      tooltip = '随机播放';
      iconColor = widget.activeColor;
    } else if (widget.playMode == PlayMode.repeatOne) {
      icon = Icons.repeat_one;
      tooltip = '单曲循环';
      iconColor = widget.activeColor;
    } else {
      icon = Icons.repeat;
      tooltip = '列表循环';
    }

    return IconButton(
      tooltip: tooltip,
      iconSize: 24,
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        switchInCurve: Curves.easeOutBack,
        switchOutCurve: Curves.easeInBack,
        transitionBuilder: (child, animation) {
          // 只对进入的组件应用动画
          return RotationTransition(
            turns: Tween(begin: 0.5, end: 0.0).animate(animation),
            child: ScaleTransition(
              scale: Tween(begin: 0.8, end: 1.0).animate(animation),
              child: FadeTransition(opacity: animation, child: child),
            ),
          );
        },
        layoutBuilder: (currentChild, previousChildren) {
          return Stack(
            alignment: Alignment.center,
            children: <Widget>[
              // 先显示之前的组件
              ...previousChildren,
              // 再显示当前组件（会在上层）
              if (currentChild != null) currentChild,
            ],
          );
        },
        child: Icon(icon, key: ValueKey(widget.playMode), color: iconColor),
      ),
      onPressed: widget.onPressed,
    );
  }
}
