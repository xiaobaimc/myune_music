import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:audioplayers/audioplayers.dart';
import '../page/playlist/playlist_content_notifier.dart';

// 定义三种意图：播放/暂停、下一首、上一首
class PlayPauseIntent extends Intent {
  const PlayPauseIntent();
}

class NextTrackIntent extends Intent {
  const NextTrackIntent();
}

class PreviousTrackIntent extends Intent {
  const PreviousTrackIntent();
}

class PlaybackAction extends Action<Intent> {
  final PlaylistContentNotifier notifier;

  PlaybackAction(this.notifier);

  @override
  // 能想出这种方案的，家里请啥都没用了
  // 当某个地方获得焦点时 禁用快捷键
  bool isEnabled(Intent intent) {
    final primaryFocus = FocusManager.instance.primaryFocus;

    // 如果当前焦点是FocusScopeNode，他可能不在输入框 启用快捷键
    // 如果是其他任何类型的node，那么他就可能在输入框 禁用快捷键
    if (primaryFocus is FocusScopeNode) {
      return true;
    } else {
      return false;
    }
  }

  @override
  // 响应快捷键对应的行为
  Object? invoke(Intent intent) {
    if (intent is PlayPauseIntent) {
      if (notifier.playerState == PlayerState.playing) {
        notifier.pause();
      } else {
        notifier.play();
      }
    } else if (intent is NextTrackIntent) {
      notifier.playNext();
    } else if (intent is PreviousTrackIntent) {
      notifier.playPrevious();
    }
    return null;
  }
}

class Hotkeys extends StatelessWidget {
  final Widget child;

  const Hotkeys({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final notifier = context.read<PlaylistContentNotifier>();

    return Shortcuts(
      // 绑定快捷键
      shortcuts: const <SingleActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.space): PlayPauseIntent(),
        SingleActivator(LogicalKeyboardKey.arrowRight): NextTrackIntent(),
        SingleActivator(LogicalKeyboardKey.arrowLeft): PreviousTrackIntent(),
      },
      child: Actions(
        // 绑定意图
        actions: <Type, Action<Intent>>{
          PlayPauseIntent: PlaybackAction(notifier),
          NextTrackIntent: PlaybackAction(notifier),
          PreviousTrackIntent: PlaybackAction(notifier),
        },
        child: Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            // 拦截Tab键，避免焦点被移动导致快捷键失效
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.tab) {
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: child,
        ),
      ),
    );
  }
}
