import 'package:flutter/material.dart';
import '../all_songs/all_songs_page.dart';
import '../../widgets/single_line_lyrics.dart';

class AllSongs extends StatelessWidget {
  const AllSongs({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const SingleLineLyricView(
          maxLinesPerLyric: 2,
          textAlign: TextAlign.left,
          alignment: Alignment.topLeft,
        ),
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: const Column(
        children: [
          Divider(height: 1, thickness: 1),
          Expanded(child: AllSongsPage()),
        ],
      ),
    );
  }
}
