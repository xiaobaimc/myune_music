import 'package:flutter/material.dart';

class LocatePlayingSongButton extends StatelessWidget {
  const LocatePlayingSongButton({
    super.key,
    required this.visible,
    required this.onPressed,
    this.tooltip = '定位到当前播放歌曲',
  });

  // 是否显示
  final bool visible;

  // 点击回调
  final VoidCallback onPressed;

  // 悬停提示文案
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedScale(
        scale: visible ? 1.0 : 0.5,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          opacity: visible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 150),
          child: FloatingActionButton.small(
            heroTag: null,
            tooltip: tooltip,
            onPressed: onPressed,
            child: const Icon(Icons.my_location, size: 20),
          ),
        ),
      ),
    );
  }
}

// 用于通知目标歌曲条目播放一次高亮动画
class LocatePulseNotifier extends ChangeNotifier {
  String? _songPath;
  String? get songPath => _songPath;

  void pulse(String filePath) {
    _songPath = filePath;
    notifyListeners();
  }
}
