import 'package:flutter/foundation.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import '../page/playlist/playlist_content_notifier.dart';
import '../page/setting/settings_provider.dart';

class GlobalHotkeyManager {
  static final GlobalHotkeyManager _instance = GlobalHotkeyManager._internal();
  factory GlobalHotkeyManager() => _instance;
  GlobalHotkeyManager._internal();

  bool _isInitialized = false;

  Future<void> init(PlaylistContentNotifier notifier, SettingsProvider settings) async {
    if (_isInitialized) {
      await unregisterAll();
    }
    _isInitialized = true;
    if (settings.enableGlobalHotkeys) {
      await registerAll(notifier, settings);
    }
  }

  Future<void> unregisterAll() async {
    try {
      await hotKeyManager.unregisterAll();
    } catch (e) {
      debugPrint('Error unregistering all hotkeys: $e');
    }
  }

  Future<void> registerAll(PlaylistContentNotifier notifier, SettingsProvider settings) async {
    if (!settings.enableGlobalHotkeys) return;

    if (settings.playPauseHotKey != null) {
      await _registerSafe(settings.playPauseHotKey!, () {
        notifier.isPlaying ? notifier.pause() : notifier.play();
      });
    }
    if (settings.nextTrackHotKey != null) {
      await _registerSafe(settings.nextTrackHotKey!, () {
        notifier.playNext();
      });
    }
    if (settings.prevTrackHotKey != null) {
      await _registerSafe(settings.prevTrackHotKey!, () {
        notifier.playPrevious();
      });
    }
    if (settings.volumeUpHotKey != null) {
      await _registerSafe(settings.volumeUpHotKey!, () {
        notifier.setVolume((notifier.volume + 3).clamp(0.0, 100.0));
      });
    }
    if (settings.volumeDownHotKey != null) {
      await _registerSafe(settings.volumeDownHotKey!, () {
        notifier.setVolume((notifier.volume - 3).clamp(0.0, 100.0));
      });
    }
  }

  Future<void> _registerSafe(HotKey hotKey, VoidCallback callback) async {
    try {
      await hotKeyManager.register(
        hotKey,
        keyDownHandler: (hk) {
          callback();
        },
      );
    } catch (e) {
      debugPrint('Failed to register hotkey: ${hotKey.toJson()}, error: $e');
    }
  }

  Future<void> updateHotKey(
    String type,
    HotKey? oldHotKey,
    HotKey? newHotKey,
    PlaylistContentNotifier notifier,
    SettingsProvider settings,
  ) async {
    if (oldHotKey != null) {
      try {
        await hotKeyManager.unregister(oldHotKey);
      } catch (e) {
        debugPrint('Failed to unregister hotkey: ${oldHotKey.toJson()}, error: $e');
      }
    }

    if (settings.enableGlobalHotkeys && newHotKey != null) {
      VoidCallback? callback;
      switch (type) {
        case 'play_pause':
          callback = () => notifier.isPlaying ? notifier.pause() : notifier.play();
          break;
        case 'next_track':
          callback = () => notifier.playNext();
          break;
        case 'prev_track':
          callback = () => notifier.playPrevious();
          break;
        case 'volume_up':
          callback = () => notifier.setVolume((notifier.volume + 3).clamp(0.0, 100.0));
          break;
        case 'volume_down':
          callback = () => notifier.setVolume((notifier.volume - 3).clamp(0.0, 100.0));
          break;
      }
      if (callback != null) {
        await _registerSafe(newHotKey, callback);
      }
    }
  }
}
