import 'package:flutter/material.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import '../widgets/app_window_title_bar.dart';
import 'main_view.dart';
import '../widgets/playbar.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    return WindowBorder(
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
    );
  }
}
