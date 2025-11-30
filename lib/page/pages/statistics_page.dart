import 'package:flutter/material.dart';
import '../statistics_page/statistics.dart';
import '../../widgets/single_line_lyrics.dart';

class StatisticsPage extends StatelessWidget {
  const StatisticsPage({super.key});

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
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: 4),
              child: SingleChildScrollView(child: Statistics()),
            ),
          ),
        ],
      ),
    );
  }
}
