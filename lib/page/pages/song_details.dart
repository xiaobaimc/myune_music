import 'package:flutter/material.dart';
import 'package:flutter_web_scroll/flutter_web_scroll.dart';
import '../song_details/song_details_page.dart';
import '../../widgets/single_line_lyrics.dart';

class SongDetails extends StatefulWidget {
  const SongDetails({super.key});

  @override
  State<SongDetails> createState() => _SongDetailsState();
}

class _SongDetailsState extends State<SongDetails> {
  late final ScrollController scrollController;

  @override
  void initState() {
    super.initState();
    scrollController = ScrollController();
  }

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }

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
      body: Column(
        children: [
          const Divider(height: 1, thickness: 1),
          Expanded(
            child: SmoothScrollWeb(
              controller: scrollController,
              config: SmoothScrollConfig.lenis(),
              child: SingleChildScrollView(
                controller: scrollController,
                child: const SongDetailsPage(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
