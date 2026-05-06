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

bool _isTextInputFocused() {
  final primary = FocusManager.instance.primaryFocus;
  if (primary == null || primary.context == null) return false;

  bool isInput = false;
  try {
    final label = primary.debugLabel?.toLowerCase() ?? '';
    if (label.contains('editable') ||
        label.contains('textfield') ||
        label.contains('input')) {
      return true;
    }

    final currentWidget = primary.context!.widget;
    if (currentWidget is TextField ||
        currentWidget is TextFormField ||
        currentWidget is EditableText) {
      return true;
    }

    primary.context!.visitAncestorElements((element) {
      final widget = element.widget;
      if (widget is TextField ||
          widget is TextFormField ||
          widget is EditableText) {
        isInput = true;
        return false;
      }
      // 避免把整棵树遍历完
      if (widget is Dialog || widget is Scaffold || widget is AlertDialog) {
        return false;
      }
      return true;
    });
  } catch (e) {
    //
  }

  return isInput;
}

class PlayerHotkeyAction<T extends Intent> extends Action<T> {
  final void Function() onInvokeCallback;

  PlayerHotkeyAction(this.onInvokeCallback);

  @override
  bool isEnabled(T intent) {
    return !_isTextInputFocused();
  }

  @override
  Object? invoke(T intent) {
    onInvokeCallback();
    return null;
  }
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

    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.space): PlayPauseIntent(),
        SingleActivator(LogicalKeyboardKey.arrowRight, control: true):
            NextTrackIntent(),
        SingleActivator(LogicalKeyboardKey.arrowLeft, control: true):
            PreviousTrackIntent(),

        SingleActivator(LogicalKeyboardKey.f11): ToggleFullscreenIntent(),
        SingleActivator(LogicalKeyboardKey.escape): ExitFullscreenIntent(),

        SingleActivator(LogicalKeyboardKey.arrowRight): SeekForwardIntent(),
        SingleActivator(LogicalKeyboardKey.arrowLeft): SeekBackwardIntent(),
        SingleActivator(LogicalKeyboardKey.arrowUp): VolumeUpIntent(),
        SingleActivator(LogicalKeyboardKey.arrowDown): VolumeDownIntent(),
        SingleActivator(LogicalKeyboardKey.numpad8): VolumeUpIntent(),
        SingleActivator(LogicalKeyboardKey.numpad2): VolumeDownIntent(),
        SingleActivator(LogicalKeyboardKey.numpad4): SeekBackwardIntent(),
        SingleActivator(LogicalKeyboardKey.numpad6): SeekForwardIntent(),
      },
      child: Actions(
        actions: {
          PlayPauseIntent: PlayerHotkeyAction<PlayPauseIntent>(() {
            notifier.isPlaying ? notifier.pause() : notifier.play();
          }),
          NextTrackIntent: PlayerHotkeyAction<NextTrackIntent>(() {
            notifier.playNext();
          }),
          PreviousTrackIntent: PlayerHotkeyAction<PreviousTrackIntent>(() {
            notifier.playPrevious();
          }),
          SeekForwardIntent: PlayerHotkeyAction<SeekForwardIntent>(() {
            notifier.mediaPlayer.seek(
              notifier.currentPosition + const Duration(seconds: 5),
            );
          }),
          SeekBackwardIntent: PlayerHotkeyAction<SeekBackwardIntent>(() {
            notifier.mediaPlayer.seek(
              notifier.currentPosition - const Duration(seconds: 5),
            );
          }),
          VolumeUpIntent: PlayerHotkeyAction<VolumeUpIntent>(() {
            notifier.setVolume((notifier.volume + 3).clamp(0.0, 100.0));
          }),
          VolumeDownIntent: PlayerHotkeyAction<VolumeDownIntent>(() {
            notifier.setVolume((notifier.volume - 3).clamp(0.0, 100.0));
          }),
          ToggleFullscreenIntent: PlayerHotkeyAction<ToggleFullscreenIntent>(
            () async {
              final isFullScreen = await windowManager.isFullScreen();
              await windowManager.setFullScreen(!isFullScreen);
            },
          ),
          ExitFullscreenIntent: PlayerHotkeyAction<ExitFullscreenIntent>(
            () async {
              if (await windowManager.isFullScreen()) {
                await windowManager.setFullScreen(false);
              }
            },
          ),
        },
        child: child,
      ),
    );
  }
}
