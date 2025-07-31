import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../playlist/playlist_content_notifier.dart';
import '../playlist/playlist_models.dart';

class SongDetailsPage extends StatelessWidget {
  const SongDetailsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<PlaylistContentNotifier, Song?>(
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
              return const Center(child: Text('无法加载歌曲详情，请稍后重试'));
            }

            final details = snapshot.data;
            if (details == null) {
              return const Center(child: Text('没有当前歌曲'));
            }

            return LayoutBuilder(
              builder: (context, constraints) {
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 32,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (details.albumArt != null)
                            Container(
                              width: 160,
                              height: 160,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                image: DecorationImage(
                                  image: MemoryImage(details.albumArt!),
                                  fit: BoxFit.cover,
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black12,
                                    blurRadius: 10,
                                    offset: Offset(0, 4),
                                  ),
                                ],
                              ),
                            )
                          else
                            const Text('无封面图片'),
                          const SizedBox(height: 20),
                          SelectableText(
                            details.title ?? '未知',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w500),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 2),
                          SelectableText(
                            '${details.artist ?? "未知"} / ${details.album ?? "未知"}',
                            style: Theme.of(context).textTheme.bodyMedium,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          const Divider(),
                          _infoCard(
                            context: context,
                            icon: Icons.access_time,
                            label: '时长',
                            value: _formatDuration(details.duration),
                          ),
                          _infoCard(
                            context: context,
                            icon: Icons.graphic_eq,
                            label: '比特率',
                            value: details.bitrate != null
                                ? '${details.bitrate! / 1000} kbps'
                                : '未知',
                          ),
                          _infoCard(
                            context: context,
                            icon: Icons.audiotrack,
                            label: '采样率',
                            value: details.sampleRate != null
                                ? '${details.sampleRate! / 1000} kHz'
                                : '未知',
                          ),
                          _infoCard(
                            context: context,
                            icon: Icons.folder,
                            label: '文件路径',
                            value: details.filePath,
                            selectable: true,
                          ),
                          _infoCard(
                            context: context,
                            icon: Icons.create,
                            label: '创建日期',
                            value: _formatDate(details.created),
                          ),
                          _infoCard(
                            context: context,
                            icon: Icons.update,
                            label: '修改日期',
                            value: _formatDate(details.modified),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return '未知';
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '未知';

    final y = date.year;
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    final h = date.hour.toString().padLeft(2, '0');
    final min = date.minute.toString().padLeft(2, '0');
    final s = date.second.toString().padLeft(2, '0');

    return '$y-$m-$d $h:$min:$s';
  }

  Widget _infoCard({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String value,
    bool selectable = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(value),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
