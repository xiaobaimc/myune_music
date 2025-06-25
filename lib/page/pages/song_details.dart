import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../playlist/playlist_content_notifier.dart';
import '../playlist/playlist_models.dart';

class SongDetailsTestPage extends StatelessWidget {
  const SongDetailsTestPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('测试歌曲详情')),
      // 当 notifier.currentSong 发生变化时，才会重建内部的 FutureBuilder
      body: Selector<PlaylistContentNotifier, Song?>(
        selector: (context, notifier) => notifier.currentSong,
        builder: (context, currentSong, child) {
          final notifier = Provider.of<PlaylistContentNotifier>(
            context,
            listen: false,
          );

          return FutureBuilder<SongDetails?>(
            key: ValueKey(currentSong?.filePath ?? 'no_song'),
            future: notifier.getCurrentSongDetails(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('获取详情失败: ${snapshot.error}'));
              }
              final details = snapshot.data;
              if (details == null) {
                return const Center(child: Text('没有当前歌曲'));
              }
              return SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDetailRow('标题', details.title ?? '未知'),
                    _buildDetailRow('艺术家', details.artist ?? '未知'),
                    _buildDetailRow('专辑', details.album ?? '未知'),
                    _buildDetailRow('时长', _formatDuration(details.duration)),
                    _buildDetailRow(
                      '比特率',
                      details.bitrate != null ? '${details.bitrate} bps' : '未知',
                    ),
                    _buildDetailRow(
                      '采样率',
                      details.sampleRate != null
                          ? '${details.sampleRate} Hz'
                          : '未知',
                    ),
                    _buildDetailRow('文件路径', (details.filePath)),
                    const SizedBox(height: 16),
                    const Text('封面图片:'),
                    const SizedBox(height: 8),
                    details.albumArt != null
                        ? Image.memory(
                            details.albumArt!,
                            width: 200,
                            height: 200,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const Text('无法加载封面'),
                          )
                        : const Text('无封面图片'),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  // 构建详情行
  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label: '),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  // 格式化时长
  String _formatDuration(Duration? duration) {
    if (duration == null) return '未知';
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
