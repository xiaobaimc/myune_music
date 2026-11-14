import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_window.dart';

const String kSingleInstancePrefsKey = 'singleInstance';

class SingleInstance {
  SingleInstance._();

  static const String _mutexName = r'Local\MyuneMusic-SingleInstance';
  static const int _errorAlreadyExists = 183;

  // 持有互斥量句柄，保证进程存活期间命名互斥量一直存在
  static int _mutexHandle = 0;

  static Future<void> enforceIfEnabled() async {
    if (!Platform.isWindows) return;

    var enabled = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      enabled = prefs.getBool(kSingleInstancePrefsKey) ?? false;
    } catch (_) {
      return;
    }
    if (!enabled) return;

    try {
      if (_claimMutex()) return;
    } catch (_) {
      // 无法判断时按首个实例继续
      return;
    }

    try {
      _focusExistingWindow();
    } catch (_) {
      // 聚焦失败也直接退出
    }
    exit(0);
  }

  // 在设置中开启单实例时调用
  static void claim() {
    if (!Platform.isWindows || _mutexHandle != 0) return;
    try {
      _claimMutex();
    } catch (_) {
      //
    }
  }

  // 尝试创建命名互斥量
  // 返回 true 表示当前进程是首个实例
  static bool _claimMutex() {
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final createMutex = kernel32
        .lookupFunction<
          IntPtr Function(Pointer<Void>, Int32, Pointer<Utf16>),
          int Function(Pointer<Void>, int, Pointer<Utf16>)
        >('CreateMutexW');
    final getLastError = kernel32
        .lookupFunction<Uint32 Function(), int Function()>('GetLastError');

    final name = _mutexName.toNativeUtf16();
    try {
      final handle = createMutex(nullptr, 0, name);
      final alreadyExists = getLastError() == _errorAlreadyExists;
      if (handle == 0) {
        // 创建失败就按首个实例继续
        return true;
      }
      _mutexHandle = handle;
      return !alreadyExists;
    } finally {
      calloc.free(name);
    }
  }

  // 找到另一个实例的主窗口并恢复显示
  static void _focusExistingWindow() {
    final user32 = DynamicLibrary.open('user32.dll');
    final kernel32 = DynamicLibrary.open('kernel32.dll');

    final findWindowEx = user32
        .lookupFunction<
          IntPtr Function(IntPtr, IntPtr, Pointer<Utf16>, Pointer<Utf16>),
          int Function(int, int, Pointer<Utf16>, Pointer<Utf16>)
        >('FindWindowExW');
    final getWindowThreadProcessId = user32
        .lookupFunction<
          Uint32 Function(IntPtr, Pointer<Uint32>),
          int Function(int, Pointer<Uint32>)
        >('GetWindowThreadProcessId');
    final isIconic = user32
        .lookupFunction<Int32 Function(IntPtr), int Function(int)>('IsIconic');
    final showWindow = user32
        .lookupFunction<Int32 Function(IntPtr, Int32), int Function(int, int)>(
          'ShowWindow',
        );
    final setForegroundWindow = user32
        .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
          'SetForegroundWindow',
        );
    final getCurrentProcessId = kernel32
        .lookupFunction<Uint32 Function(), int Function()>(
          'GetCurrentProcessId',
        );

    const win32WindowClass = 'FLUTTER_RUNNER_WIN32_WINDOW';
    // SW_RESTORE = 9, SW_SHOW = 5
    const swRestore = 9;
    const swShow = 5;

    final className = win32WindowClass.toNativeUtf16();
    final title = kAppWindowTitle.toNativeUtf16();
    final pidPointer = calloc<Uint32>();
    try {
      final currentPid = getCurrentProcessId();
      var childAfter = 0;
      while (true) {
        final hwnd = findWindowEx(0, childAfter, className, title);
        if (hwnd == 0) break;

        getWindowThreadProcessId(hwnd, pidPointer);
        if (pidPointer.value != currentPid) {
          showWindow(hwnd, isIconic(hwnd) != 0 ? swRestore : swShow);
          setForegroundWindow(hwnd);
          break;
        }
        childAfter = hwnd;
      }
    } finally {
      calloc.free(className);
      calloc.free(title);
      calloc.free(pidPointer);
    }
  }
}
