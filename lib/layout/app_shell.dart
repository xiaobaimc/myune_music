import 'dart:async';
import 'package:flutter/material.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:provider/provider.dart';

import '../page/playlist/playlist_content_notifier.dart';
import '../widgets/app_window_title_bar.dart';
import 'main_view.dart';
import '../widgets/playbar.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  StreamSubscription<String>? _errorSubscription;
  StreamSubscription<String>? _infoSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final notifier = context.read<PlaylistContentNotifier>();
      _errorSubscription = notifier.errorStream.listen((errorMessage) {
        if (mounted) {
          // 现在错误将在这里提示，有时间把其他的提示也整合在一起（也许大概已完成）
          // 比如置于顶部的提示
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Container(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Row(
                  children: [
                    const Icon(Icons.error, color: Colors.white),
                    const SizedBox(width: 8),
                    Expanded(child: Text(errorMessage)),
                  ],
                ),
              ),
              backgroundColor: Theme.of(context).colorScheme.error,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 3),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              margin: const EdgeInsets.only(bottom: 80, left: 12, right: 12),
            ),
          );
        }
      });
      // 普通提示
      _infoSubscription = notifier.infoStream.listen((infoMessage) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Container(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Row(
                  children: [
                    const Icon(Icons.info, color: Colors.white),
                    const SizedBox(width: 8),
                    Expanded(child: Text(infoMessage)),
                  ],
                ),
              ),
              backgroundColor: Theme.of(context).colorScheme.primary,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 3),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              margin: const EdgeInsets.only(bottom: 80, left: 12, right: 12),
            ),
          );
        }
      });
    });
  }

  @override
  void dispose() {
    _errorSubscription?.cancel(); // 在销毁时取消订阅
    _infoSubscription?.cancel(); // 在销毁时取消订阅
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: WindowBorder(
        color: Colors.transparent,
        width: 0,
        child: const Material(
          color: Colors.transparent,
          child: Column(
            children: [
              AppWindowTitleBar(),
              Expanded(child: MainView()),
              Playbar(),
            ],
          ),
        ),
      ),
    );
  }
}
