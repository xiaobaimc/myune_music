import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import '../page/playlist/playlist_content_notifier.dart';

// 播放/暂停、下一首、上一首
class PlayPauseIntent extends Intent {
  const PlayPauseIntent();
}

class NextTrackIntent extends Intent {
  const NextTrackIntent();
}

class PreviousTrackIntent extends Intent {
  const PreviousTrackIntent();
}

// 全屏和退出全屏
class ToggleFullscreenIntent extends Intent {
  const ToggleFullscreenIntent();
}

class ExitFullscreenIntent extends Intent {
  const ExitFullscreenIntent();
}

class Hotkeys extends StatelessWidget {
  final Widget child;

  const Hotkeys({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<PlaylistContentNotifier>();

    // 如果正在搜索，则直接返回子组件，不应用任何快捷键
    if (notifier.isSearching || notifier.disableHotKeys) {
      return child;
    }

    return FocusableActionDetector(
      // 绑定快捷键
      shortcuts: const <SingleActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.space): PlayPauseIntent(),
        SingleActivator(LogicalKeyboardKey.arrowRight, control: true):
            NextTrackIntent(),
        SingleActivator(LogicalKeyboardKey.arrowLeft, control: true):
            PreviousTrackIntent(),
        SingleActivator(LogicalKeyboardKey.f11): ToggleFullscreenIntent(),
        SingleActivator(LogicalKeyboardKey.escape): ExitFullscreenIntent(),
      },
      actions: {
        // 绑定意图
        PlayPauseIntent: CallbackAction<PlayPauseIntent>(
          onInvoke: (intent) {
            if (notifier.isPlaying) {
              notifier.pause();
            } else {
              notifier.play();
            }
            return null;
          },
        ),
        NextTrackIntent: CallbackAction<NextTrackIntent>(
          onInvoke: (intent) {
            notifier.playNext();
            return null;
          },
        ),
        PreviousTrackIntent: CallbackAction<PreviousTrackIntent>(
          onInvoke: (intent) {
            notifier.playPrevious();
            return null;
          },
        ),
        ToggleFullscreenIntent: CallbackAction<ToggleFullscreenIntent>(
          onInvoke: (intent) async {
            final bool isFullScreen = await windowManager.isFullScreen();
            await windowManager.setFullScreen(!isFullScreen);
            return null;
          },
        ),
        ExitFullscreenIntent: CallbackAction<ExitFullscreenIntent>(
          onInvoke: (intent) async {
            final bool isFullScreen = await windowManager.isFullScreen();
            if (isFullScreen) {
              await windowManager.setFullScreen(false);
            }
            return null;
          },
        ),
      },
      autofocus: true,
      child: child,
    );
  }
}
