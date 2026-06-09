import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../playlist/playlist_content_notifier.dart';
import '../playlist/playlist_models.dart';

class PlaylistCleaner extends StatefulWidget {
  final PlaylistContentNotifier notifier;

  const PlaylistCleaner({super.key, required this.notifier});

  @override
  State<PlaylistCleaner> createState() => _PlaylistCleanerState();
}

class _PlaylistCleanerState extends State<PlaylistCleaner> {
  bool _isScanning = false;
  bool _isApplying = false;
  Map<String, MapEntry<String, List<String>>>? _invalidFiles;
  String? _error;

  Future<void> _showCleanDialog() async {
    // 仅显示普通歌单
    final playlists = widget.notifier.playlists
        .where((p) => !p.isFolderBased)
        .toList();

    if (playlists.isEmpty) {
      if (mounted) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('提示'),
            content: const Text('没有可扫描的普通歌单'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      }
      return;
    }

    setState(() {
      _isScanning = false;
      _isApplying = false;
      _invalidFiles = null;
      _error = null;
    });

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return _PlaylistSelectionDialog(
          playlists: playlists,
          onStartScan: (selectedIds) {
            Navigator.of(dialogContext).pop();
            _startScanAndShowResults(selectedIds);
          },
        );
      },
    );
  }

  Future<void> _startScanAndShowResults(Set<String> playlistIds) async {
    setState(() {
      _isScanning = true;
      _invalidFiles = null;
      _error = null;
    });

    if (!mounted) return;
    bool hasStarted = false;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            if (!hasStarted) {
              hasStarted = true;
              _runScan(ctx, setDialogState, playlistIds);
            }
            return _buildProgressDialog(ctx, setDialogState);
          },
        );
      },
    );
  }

  Future<void> _runScan(
    BuildContext dialogContext,
    StateSetter setDialogState,
    Set<String> playlistIds,
  ) async {
    try {
      final idList = playlistIds.toList();
      final invalidFiles =
          await widget.notifier.findInvalidFiles(playlistIds: idList);

      if (!dialogContext.mounted) return;
      setDialogState(() {
        _invalidFiles = invalidFiles;
        _isScanning = false;
        _error = null;
      });
    } catch (e) {
      if (!dialogContext.mounted) return;
      setDialogState(() {
        _isScanning = false;
        _error = e.toString();
      });
    }
  }

  Widget _buildProgressDialog(BuildContext ctx, StateSetter setDialogState) {
    if (_isScanning) {
      return const AlertDialog(
        title: Text('正在扫描...'),
        content: SizedBox(
          width: 300,
          height: 100,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在扫描歌单文件...'),
            ],
          ),
        ),
      );
    }

    if (_isApplying) {
      return const AlertDialog(
        title: Text('正在清理...'),
        content: SizedBox(
          width: 300,
          height: 100,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在清理普通歌单无效文件...'),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return AlertDialog(
        title: const Text('扫描错误'),
        content: Text('扫描过程中发生错误: $_error'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('确定'),
          ),
        ],
      );
    }

    final invalidCount = _invalidFiles?.values.fold<int>(
            0, (sum, e) => sum + e.value.length) ??
        0;

    if (invalidCount == 0) {
      return AlertDialog(
        title: const Text('扫描完成'),
        content: const Text('没有发现无效文件'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('确定'),
          ),
        ],
      );
    }

    return _ResultDialog(
      invalidFiles: _invalidFiles,
      onApply: (checkedInvalidPaths) async {
        setDialogState(() {
          _isApplying = true;
        });
        final navigator = Navigator.of(ctx);
        try {
          final removeMap = <String, Set<String>>{};
          if (_invalidFiles != null) {
            for (final entry in _invalidFiles!.entries) {
              final playlistId = entry.key;
              final paths = entry.value.value;
              final checked = paths
                  .where((fp) => checkedInvalidPaths.contains(fp))
                  .toSet();
              if (checked.isNotEmpty) {
                removeMap[playlistId] = checked;
              }
            }
          }
          final cleaned =
              await widget.notifier.cleanInvalidFiles(filesToRemove: removeMap);

          if (!mounted || !ctx.mounted) return;
          navigator.pop();
          if (mounted) {
            await showDialog(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('清理完成'),
                content: Text('已清理 $cleaned 个无效文件'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(c).pop(),
                    child: const Text('确定'),
                  ),
                ],
              ),
            );
          }
        } catch (e) {
          setDialogState(() {
            _isApplying = false;
          });
          if (mounted) {
            await showDialog(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('操作失败'),
                content: Text('清理过程中发生错误: $e'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(c).pop(),
                    child: const Text('确定'),
                  ),
                ],
              ),
            );
          }
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('清理普通歌单无效文件', style: Theme.of(context).textTheme.titleMedium),
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

/// 第一步：歌单选择对话框
class _PlaylistSelectionDialog extends StatefulWidget {
  final List<Playlist> playlists;
  final void Function(Set<String> selectedIds) onStartScan;

  const _PlaylistSelectionDialog({
    required this.playlists,
    required this.onStartScan,
  });

  @override
  State<_PlaylistSelectionDialog> createState() =>
      _PlaylistSelectionDialogState();
}

class _PlaylistSelectionDialogState extends State<_PlaylistSelectionDialog> {
  late Set<String> _selectedIds;

  @override
  void initState() {
    super.initState();
    _selectedIds = widget.playlists.map((p) => p.id).toSet();
  }

  bool get _isAllSelected => _selectedIds.length == widget.playlists.length;

  void _toggleAll() {
    setState(() {
      if (_isAllSelected) {
        _selectedIds.clear();
      } else {
        _selectedIds = widget.playlists.map((p) => p.id).toSet();
      }
    });
  }

  void _togglePlaylist(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('选择歌单'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CheckboxListTile(
              value: _isAllSelected,
              onChanged: (_) => _toggleAll(),
              title: Text(_isAllSelected ? '取消全选' : '全选'),
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.playlists.length,
                itemBuilder: (context, index) {
                  final playlist = widget.playlists[index];
                  return CheckboxListTile(
                    value: _selectedIds.contains(playlist.id),
                    onChanged: (_) => _togglePlaylist(playlist.id),
                    title: Text(
                      playlist.name,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${playlist.songFilePaths.length} 首歌曲',
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _selectedIds.isEmpty
              ? null
              : () => widget.onStartScan(_selectedIds),
          child: const Text('开始扫描'),
        ),
      ],
    );
  }
}

/// 第二步：扫描结果对话框，带勾选功能
class _ResultDialog extends StatefulWidget {
  final Map<String, MapEntry<String, List<String>>>? invalidFiles;
  final Future<void> Function(Set<String> checkedInvalidPaths) onApply;

  const _ResultDialog({
    required this.invalidFiles,
    required this.onApply,
  });

  @override
  State<_ResultDialog> createState() => _ResultDialogState();
}

class _ResultDialogState extends State<_ResultDialog> {
  late Set<String> _checkedInvalidPaths;

  @override
  void initState() {
    super.initState();
    _checkedInvalidPaths = {};
    // 默认全选所有无效文件
    if (widget.invalidFiles != null) {
      for (final entry in widget.invalidFiles!.values) {
        _checkedInvalidPaths.addAll(entry.value);
      }
    }
  }

  bool get _isAllInvalidSelected {
    if (widget.invalidFiles == null || widget.invalidFiles!.isEmpty) return false;
    return _invalidTotal > 0 && _invalidTotal == _checkedInvalidPaths.length;
  }

  int get _invalidTotal =>
      widget.invalidFiles?.values.fold<int>(
          0, (sum, e) => sum + e.value.length) ??
      0;

  void _toggleAllInvalid() {
    final files = widget.invalidFiles;
    if (files == null) return;
    setState(() {
      if (_isAllInvalidSelected) {
        for (final entry in files.values) {
          _checkedInvalidPaths.removeAll(entry.value);
        }
      } else {
        for (final entry in files.values) {
          _checkedInvalidPaths.addAll(entry.value);
        }
      }
    });
  }

  void _toggleInvalidPath(String path) {
    setState(() {
      if (_checkedInvalidPaths.contains(path)) {
        _checkedInvalidPaths.remove(path);
      } else {
        _checkedInvalidPaths.add(path);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final invalidCount = _invalidTotal;

    final List<Widget> contentWidgets = [];

    // 无效文件部分
    if (widget.invalidFiles != null && widget.invalidFiles!.isNotEmpty) {
      contentWidgets.add(
        CheckboxListTile(
          value: _isAllInvalidSelected,
          onChanged: (_) => _toggleAllInvalid(),
          title: Text(_isAllInvalidSelected
              ? '取消全选无效文件'
              : '全选无效文件 ($invalidCount)'),
          controlAffinity: ListTileControlAffinity.leading,
          dense: true,
        ),
      );
      contentWidgets.add(const Divider(height: 1));

      for (final entry in widget.invalidFiles!.entries) {
        final playlistName = entry.value.key;
        final paths = entry.value.value;
        contentWidgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 8),
            child: Text(
              '歌单 "$playlistName" (${paths.length} 个文件):',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        );
        for (final path in paths) {
          contentWidgets.add(
            CheckboxListTile(
              value: _checkedInvalidPaths.contains(path),
              onChanged: (_) => _toggleInvalidPath(path),
              title: Text(
                p.basename(path),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15),
              ),
              subtitle: path.length > 60
                  ? Text(
                      path,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    )
                  : null,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
            ),
          );
        }
      }
    }

    final actions = <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('关闭'),
      ),
      ElevatedButton(
        onPressed: _checkedInvalidPaths.isEmpty
            ? null
            : () => widget.onApply(_checkedInvalidPaths),
        child: Text('清理 (${_checkedInvalidPaths.length})'),
      ),
    ];

    return AlertDialog(
      title: Text('扫描结果 (无效: $invalidCount)'),
      content: SizedBox(
        width: 500,
        height: MediaQuery.of(context).size.height * 0.6,
        child: ClipRect(
          child: Scrollbar(
            thumbVisibility: true,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: contentWidgets,
              ),
            ),
          ),
        ),
      ),
      actions: actions,
    );
  }
}
