import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/notification_service.dart';

// 参考: https://github.com/libnativeapi/nativeapi/issues/29
//
// 更新 window_manager 之后，打开资源管理器对话框后，flutter 大约会经历 20~30 秒的假死
// 这里暂时先不使用 file_picker 的窗口冻结 (lockParentWindow: true) 临时先在 flutter 层冻结
// （能跑就不要动.jpg）
//
// TODO: 修复这里需要等发新版 且需要更新 flutter 到 3.50+
const bool kNativeParentWindowLock = false;

const WindowsOptions kWindowsPickerOptions = WindowsOptions(
  lockParentWindow: kNativeParentWindowLock,
);

// 系统文件对话框打开期间，把应用界面冻结
class AppFreeze {
  AppFreeze._();

  static const String blockedTapMessage = '请先在文件选择窗口中完成操作';

  static final ValueNotifier<bool> active = ValueNotifier<bool>(false);

  static Future<T> during<T>(Future<T> Function() task) async {
    // 系统模态已经生效时不需要再冻一层
    if (kNativeParentWindowLock || !Platform.isWindows || active.value) {
      return task();
    }
    active.value = true;
    try {
      await Future.any<void>([
        WidgetsBinding.instance.endOfFrame,
        Future<void>.delayed(const Duration(milliseconds: 32)),
      ]);
      return await task();
    } finally {
      active.value = false;
    }
  }
}

class AppFreezeGate extends StatefulWidget {
  const AppFreezeGate({super.key, required this.child});

  final Widget child;

  @override
  State<AppFreezeGate> createState() => _AppFreezeGateState();
}

class _AppFreezeGateState extends State<AppFreezeGate> {
  late bool _frozen = AppFreeze.active.value;

  @override
  void initState() {
    super.initState();
    AppFreeze.active.addListener(_sync);
  }

  @override
  void dispose() {
    AppFreeze.active.removeListener(_sync);
    super.dispose();
  }

  void _sync() {
    if (!mounted || _frozen == AppFreeze.active.value) return;
    setState(() => _frozen = AppFreeze.active.value);
  }

  // 冻结期间点击主窗口时给个反馈
  void _notifyBlockedTap() {
    try {
      context.read<NotificationService>().info('请先在文件选择窗口中完成操作');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 吃掉全部指针事件，并让内容无法再获得焦点
        ExcludeFocus(
          excluding: _frozen,
          child: AbsorbPointer(absorbing: _frozen, child: widget.child),
        ),
        if (_frozen) _FreezeCover(onBlockedTap: _notifyBlockedTap),
      ],
    );
  }
}

class _FreezeCover extends StatelessWidget {
  const _FreezeCover({required this.onBlockedTap});

  final VoidCallback onBlockedTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onBlockedTap,
      child: const ColoredBox(
        color: Color(0x33000000),
        child: Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      ),
    );
  }
}
