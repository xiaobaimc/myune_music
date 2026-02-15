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

// 音量和进度控制
class VolumeUpIntent extends Intent {
  const VolumeUpIntent();
}

class VolumeDownIntent extends Intent {
  const VolumeDownIntent();
}

class SeekForwardIntent extends Intent {
  const SeekForwardIntent();
}

class SeekBackwardIntent extends Intent {
  const SeekBackwardIntent();
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
        // --- 播放/暂停 上/下一首 ---
        SingleActivator(LogicalKeyboardKey.space): PlayPauseIntent(),
        SingleActivator(LogicalKeyboardKey.arrowRight, control: true):
            NextTrackIntent(),
        SingleActivator(LogicalKeyboardKey.arrowLeft, control: true):
            PreviousTrackIntent(),

        // --- 全屏和退出全屏 ---
        SingleActivator(LogicalKeyboardKey.f11): ToggleFullscreenIntent(),
        SingleActivator(LogicalKeyboardKey.escape): ExitFullscreenIntent(),

        // --- 音量和进度控制 ---
        SingleActivator(LogicalKeyboardKey.arrowRight): SeekForwardIntent(),
        SingleActivator(LogicalKeyboardKey.arrowLeft): SeekBackwardIntent(),
        SingleActivator(LogicalKeyboardKey.arrowUp): VolumeUpIntent(),
        SingleActivator(LogicalKeyboardKey.arrowDown): VolumeDownIntent(),
        SingleActivator(LogicalKeyboardKey.numpad8): VolumeUpIntent(),
        SingleActivator(LogicalKeyboardKey.numpad2): VolumeDownIntent(),
        SingleActivator(LogicalKeyboardKey.numpad4): SeekBackwardIntent(),
        SingleActivator(LogicalKeyboardKey.numpad6): SeekForwardIntent(),
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
        SeekForwardIntent: CallbackAction<SeekForwardIntent>(
          onInvoke: (intent) async {
            final currentPosition = notifier.currentPosition;
            final newPosition = currentPosition + const Duration(seconds: 5);

            await notifier.mediaPlayer.seek(newPosition);
            return null;
          },
        ),
        SeekBackwardIntent: CallbackAction<SeekBackwardIntent>(
          onInvoke: (intent) async {
            final currentPosition = notifier.currentPosition;
            final newPosition = currentPosition - const Duration(seconds: 5);

            await notifier.mediaPlayer.seek(newPosition);
            return null;
          },
        ),
        VolumeUpIntent: CallbackAction<VolumeUpIntent>(
          onInvoke: (intent) {
            double newVolume = notifier.volume + 3;
            if (newVolume > 100) {
              newVolume = 100;
            }
            notifier.setVolume(newVolume);
            return null;
          },
        ),
        VolumeDownIntent: CallbackAction<VolumeDownIntent>(
          onInvoke: (intent) {
            double newVolume = notifier.volume - 3;
            if (newVolume < 0) {
              newVolume = 0;
            }
            notifier.setVolume(newVolume);
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
