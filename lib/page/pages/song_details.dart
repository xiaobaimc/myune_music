import 'package:flutter/material.dart';
import '../song_details/song_details_page.dart';
import '../../widgets/single_line_lyrics.dart';

class SongDetails extends StatelessWidget {
  const SongDetails({super.key});

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
          Expanded(child: SingleChildScrollView(child: SongDetailsPage())),
        ],
      ),
    );
  }
}
