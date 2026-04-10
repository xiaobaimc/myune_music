import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../playlist/playlist_content_notifier.dart';

class PlaylistCleaner extends StatefulWidget {
  final PlaylistContentNotifier notifier;

  const PlaylistCleaner({super.key, required this.notifier});

  @override
  State<PlaylistCleaner> createState() => _PlaylistCleanerState();
}

class _PlaylistCleanerState extends State<PlaylistCleaner> {
  bool _isScanning = false;
  bool _isCleaning = false;
  bool _hasScanned = false;
  Map<String, List<String>>? _invalidFiles;
  String? _error;

  Future<void> _showCleanDialog() async {
    // 重置状态
    setState(() {
      _isScanning = false;
      _isCleaning = false;
      _hasScanned = false;
      _invalidFiles = null;
      _error = null;
    });

    await showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext dialogContext, StateSetter setDialogState) {
            if (!_hasScanned && !_isScanning && !_isCleaning) {
              _startScan(setDialogState);
            }

            return AlertDialog(
              title: Text(
                _isScanning
                    ? '正在扫描...'
                    : _isCleaning
                    ? '正在清理...'
                    : '清理歌单',
              ),
              content: _buildDialogContent(setDialogState),
              actions: _isScanning || _isCleaning
                  ? []
                  : [
                      TextButton(
                        onPressed: () {
                          Navigator.of(dialogContext).pop();
                        },
                        child: const Text('取消'),
                      ),
                      if (_invalidFiles != null && _invalidFiles!.isNotEmpty)
                        TextButton(
                          onPressed: () {
                            _startClean(setDialogState);
                          },
                          child: const Text('清理'),
                        ),
                    ],
            );
          },
        );
      },
    );
  }

  Future<void> _startScan(StateSetter setDialogState) async {
    setDialogState(() {
      _isScanning = true;
      _hasScanned = true;
    });

    try {
      final invalidFiles = await widget.notifier.findInvalidFiles();
      setDialogState(() {
        _invalidFiles = invalidFiles;
        _isScanning = false;
        _error = null;
      });
    } catch (e) {
      setDialogState(() {
        _isScanning = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _startClean(StateSetter setDialogState) async {
    setDialogState(() {
      _isCleaning = true;
    });

    try {
      final cleanedCount = await widget.notifier.cleanInvalidFiles();

      if (!mounted) return;
      Navigator.of(context).pop();

      if (mounted) {
        await showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('清理完成'),
              content: Text('已清理 $cleanedCount 个不存在的文件'),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: const Text('确定'),
                ),
              ],
            );
          },
        );
      }
    } catch (e) {
      setDialogState(() {
        _isCleaning = false;
      });

      if (mounted) {
        await showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('清理失败'),
              content: Text('清理过程中发生错误: $e'),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: const Text('确定'),
                ),
              ],
            );
          },
        );
      }
    }
  }

  Widget _buildDialogContent(StateSetter setDialogState) {
    if (_isScanning) {
      return const SizedBox(
        width: 400,
        height: 100,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在扫描...'),
          ],
        ),
      );
    }

    if (_isCleaning) {
      return const SizedBox(
        width: 400,
        height: 100,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在清理无效文件...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Text('扫描错误: $_error');
    }

    if (_invalidFiles == null) {
      return const Text('正在准备扫描...');
    }

    if (_invalidFiles!.isEmpty) {
      return const Text('没有发现不存在的文件');
    }

    final List<Widget> fileWidgets = [];
    int totalCount = 0;

    _invalidFiles!.forEach((playlistName, filePaths) {
      fileWidgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Text('歌单 "$playlistName" (${filePaths.length} 个文件):'),
        ),
      );

      for (final filePath in filePaths) {
        fileWidgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Text(
              '• ${p.basename(filePath)}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      }

      totalCount += filePaths.length;
    });

    return SizedBox(
      width: 500,
      height: 400,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('发现 $totalCount 个不存在的文件：'),
            const SizedBox(height: 16),
            ...fileWidgets,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('清理无效文件', style: Theme.of(context).textTheme.titleMedium),
        ElevatedButton.icon(
          onPressed: () {
            _showCleanDialog();
          },
          icon: const Icon(Icons.cleaning_services, size: 20),
          label: const Text('开始扫描'),
        ),
      ],
    );
  }
}
