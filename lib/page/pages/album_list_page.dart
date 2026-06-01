import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../song_list/album_list.dart';
import '../../widgets/single_line_lyrics.dart';
import '../playlist/playlist_content_notifier.dart';

class AlbumListPage extends StatelessWidget {
  const AlbumListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<PlaylistContentNotifier>(
      builder: (context, notifier, child) {
        final bool showAppBar =
            notifier.currentDetailViewContext != DetailViewContext.album;

        return Scaffold(
          appBar: showAppBar
              ? AppBar(
                  title: const SingleLineLyricView(
                    maxLinesPerLyric: 2,
                    textAlign: TextAlign.left,
                    alignment: Alignment.topLeft,
                  ),
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  surfaceTintColor: Colors.transparent,
                )
              : null,
          body: Column(
            children: [
              if (showAppBar) const Divider(height: 1, thickness: 1),
              const Expanded(child: AlbumList()),
            ],
          ),
        );
      },
    );
  }
}
