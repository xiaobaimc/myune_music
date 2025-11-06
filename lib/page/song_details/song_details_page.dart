import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:io';

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
                                borderRadius: BorderRadius.circular(6),
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
                            trailing: IconButton(
                              icon: const Icon(Icons.open_in_new, size: 18),
                              onPressed: () {
                                _openFileLocation(details.filePath, notifier);
                              },
                              tooltip: '打开文件所在位置',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              splashRadius: 18,
                              iconSize: 18,
                            ),
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

  void _openFileLocation(
    String filePath,
    PlaylistContentNotifier notifier,
  ) async {
    try {
      final directory = File(filePath).parent.path;

      if (Platform.isWindows) {
        await Process.run('explorer', ['/select,', filePath]);
      } else if (Platform.isMacOS) {
        // 对于MacOS的支持
        await Process.run('open', ['-R', filePath]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [directory]);
      }
    } catch (e) {
      notifier.postError('打开文件位置失败');
    }
  }

  Widget _infoCard({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String value,
    bool selectable = false,
    Widget? trailing,
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
            Icon(
              icon,
              size: 20,
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.8),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: SelectableText(
                          label,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ),
                      if (trailing != null) ...[
                        const SizedBox(width: 4),
                        SizedBox(height: 18, width: 18, child: trailing),
                      ],
                    ],
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
