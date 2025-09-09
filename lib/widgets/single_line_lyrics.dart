import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../page/playlist/playlist_models.dart';
import '../page/playlist/playlist_content_notifier.dart';
import '../page/setting/settings_provider.dart';

class SingleLineLyricWidget extends StatelessWidget {
  final List<LyricLine> lyrics;
  final int currentIndex;
  final int maxLinesPerLyric;
  final double fontSize;
  final TextAlign textAlign;
  final Alignment alignment;

  const SingleLineLyricWidget({
    super.key,
    required this.lyrics,
    required this.currentIndex,
    this.maxLinesPerLyric = 1,
    this.fontSize = 17,
    this.textAlign = TextAlign.center,
    this.alignment = Alignment.center,
  });

  CrossAxisAlignment _getCrossAxisAlignment(TextAlign align) {
    switch (align) {
      case TextAlign.left:
        return CrossAxisAlignment.start;
      case TextAlign.right:
        return CrossAxisAlignment.end;
      default:
        return CrossAxisAlignment.center;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    if (lyrics.isEmpty || currentIndex < 0 || currentIndex >= lyrics.length) {
      return Text(
        '暂未获取到歌词',
        textAlign: textAlign,
        style: TextStyle(
          fontSize: fontSize,
          height: 1.6,
          color: colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      );
    }

    final LyricLine currentLine = lyrics[currentIndex];
    final visibleTexts = currentLine.texts.take(maxLinesPerLyric);

    final List<Widget> textWidgets = visibleTexts.map((text) {
      return Text(
        text,
        textAlign: textAlign,
        style: TextStyle(
          fontSize: fontSize,
          height: 1.6,
          color: colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      );
    }).toList();

    return Align(
      alignment: alignment,
      child: IntrinsicWidth(
        child: Column(
          crossAxisAlignment: _getCrossAxisAlignment(textAlign),
          children: textWidgets,
        ),
      ),
    );
  }
}

class SingleLineLyricView extends StatelessWidget {
  final int maxLinesPerLyric;
  final double fontSize;
  final TextAlign textAlign;
  final Alignment alignment;

  const SingleLineLyricView({
    super.key,
    this.maxLinesPerLyric = 1,
    this.fontSize = 17,
    this.textAlign = TextAlign.center,
    this.alignment = Alignment.center,
  });

  @override
  Widget build(BuildContext context) {
    final playlistNotifier = Provider.of<PlaylistContentNotifier>(
      context,
      listen: true,
    );

    final settings = Provider.of<SettingsProvider>(context, listen: true);

    return StreamBuilder<int>(
      stream: playlistNotifier.lyricLineIndexStream, // 监听歌词行索引流
      initialData: playlistNotifier.currentLyricLineIndex, // 初始索引
      builder: (context, snapshot) {
        final currentLyricLineIndex = snapshot.data ?? -1;
        final currentLyrics = playlistNotifier.currentLyrics;

        return SingleLineLyricWidget(
          lyrics: currentLyrics,
          currentIndex: currentLyricLineIndex,
          maxLinesPerLyric: settings.forceSingleLineLyric
              ? 1
              : maxLinesPerLyric,
          fontSize: fontSize,
          textAlign: textAlign,
          alignment: alignment,
        );
      },
    );
  }
}
