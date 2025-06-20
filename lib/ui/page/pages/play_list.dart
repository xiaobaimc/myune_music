import 'package:flutter/material.dart';
import '../playlist/playlist_content_widget.dart';

class Playlist extends StatelessWidget {
  const Playlist({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("歌单"),
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: const Column(
        children: [
          Divider(height: 1),
          Expanded(child: PlaylistContentWidget()),
        ],
      ),
    );
  }
}
