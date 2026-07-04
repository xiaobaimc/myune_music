import 'package:flutter/material.dart';
import 'package:silky_scroll/silky_scroll.dart';
import '../../theme/scroll_config.dart';
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
            child: SilkyScroll(
              controller: scrollController,
              silkyScrollDuration: ScrollConfig.duration,
              scrollSpeed: ScrollConfig.speed,
              animationCurve: ScrollConfig.curve,
              builder: (context, controller, physics, _) => SingleChildScrollView(
                controller: controller,
                physics: physics,
                child: const SongDetailsPage(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
