import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:window_manager/window_manager.dart';

const String kAppWindowTitle = 'MyuneMusic';

const String _kWin32WindowClass = 'FLUTTER_RUNNER_WIN32_WINDOW';

class AppWindow {
  AppWindow._();

  static Window? _window;

  // 应用主窗口；极端情况下返回 null
  static Window? get instance => _window ??= _resolve();

  static Window? _resolve() {
    final current = WindowManager.instance.getCurrent();
    if (current != null) {
      return current;
    }

    // Linux 的 GetCurrent 有已 realize 但未显示的窗口兜底，无需额外处理
    if (!Platform.isWindows) {
      return null;
    }

    final handle = _findRunnerWindow();
    if (handle == null || handle == 0) {
      return null;
    }
    return Window.createWithNativeWindow(Pointer<Void>.fromAddress(handle));
  }

  // 用 user32!FindWindowW 找到 runner 的顶层窗口，隐藏状态下也能找到
  static int? _findRunnerWindow() {
    try {
      final user32 = DynamicLibrary.open('user32.dll');
      final findWindow = user32
          .lookupFunction<
            IntPtr Function(Pointer<Utf16>, Pointer<Utf16>),
            int Function(Pointer<Utf16>, Pointer<Utf16>)
          >('FindWindowW');

      final className = _kWin32WindowClass.toNativeUtf16();
      final title = kAppWindowTitle.toNativeUtf16();
      try {
        return findWindow(className, title);
      } finally {
        calloc.free(className);
        calloc.free(title);
      }
    } catch (error) {
      return null;
    }
  }
}
