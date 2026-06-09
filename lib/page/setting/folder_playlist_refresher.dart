import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../playlist/playlist_content_notifier.dart';
import '../playlist/playlist_models.dart';

class FolderPlaylistRefresher extends StatefulWidget {
  final PlaylistContentNotifier notifier;

  const FolderPlaylistRefresher({super.key, required this.notifier});

  @override
  State<FolderPlaylistRefresher> createState() =>
      _FolderPlaylistRefresherState();
}

class _FolderPlaylistRefresherState extends State<FolderPlaylistRefresher> {
  bool _isRefreshing = false;

  Future<void> _showRefreshDialog() async {
    final folderPlaylists = widget.notifier.playlists
        .where((p) => p.isFolderBased)
        .toList();

    if (folderPlaylists.isEmpty) {
      if (mounted) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('提示'),
            content: const Text('没有文件夹歌单'),
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

    await showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return _FolderSelectionDialog(
          playlists: folderPlaylists,
          onStartRefresh: (selectedIds) {
            Navigator.of(dialogContext).pop();
            _startRefresh(selectedIds);
          },
        );
      },
    );
  }

  Future<void> _startRefresh(Set<String> playlistIds) async {
    setState(() => _isRefreshing = true);

    final folderPlaylists = widget.notifier.playlists
        .where((p) => p.isFolderBased && playlistIds.contains(p.id))
        .toList();

    final changes = <String, ({List<String> added, List<String> removed})>{};
    for (final playlist in folderPlaylists) {
      final result = await widget.notifier.refreshFolderPlaylistById(
        playlist.id,
      );
      if (!mounted) return;
      if (result.added.isNotEmpty || result.removed.isNotEmpty) {
        changes[playlist.name] = result;
      }
    }

    setState(() => _isRefreshing = false);

    if (!mounted) return;

    if (changes.isEmpty) {
      await showDialog(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('刷新完成'),
          content: const Text('所有文件夹歌单无变化'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(c).pop(),
              child: const Text('确定'),
            ),
          ],
        ),
      );
    } else {
      await showDialog(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('文件夹歌单刷新完成'),
          content: SizedBox(
            width: 500,
            height: MediaQuery.of(c).size.height * 0.6,
            child: ClipRect(
              child: Scrollbar(
                thumbVisibility: true,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: _buildChangeContent(changes),
                ),
              ),
            ),
          ),
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

  Widget _buildChangeContent(
    Map<String, ({List<String> added, List<String> removed})> changes,
  ) {
    final children = <Widget>[];
    for (final entry in changes.entries) {
      final name = entry.key;
      final added = entry.value.added;
      final removed = entry.value.removed;
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '歌单 "$name"',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              if (removed.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 4),
                  child: Text(
                    '移除 ${removed.length} 首:',
                    style: TextStyle(color: Colors.red.shade700, fontSize: 15),
                  ),
                ),
                ...removed.map(
                  (path) => Padding(
                    padding: const EdgeInsets.only(left: 24),
                    child: Text(
                      '• ${p.basename(path)}',
                      style: TextStyle(
                        color: Colors.red.shade700,
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
              if (added.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 4),
                  child: Text(
                    '新增 ${added.length} 首:',
                    style: TextStyle(
                      color: Colors.green.shade700,
                      fontSize: 15,
                    ),
                  ),
                ),
                ...added.map(
                  (path) => Padding(
                    padding: const EdgeInsets.only(left: 24),
                    child: Text(
                      '• ${p.basename(path)}',
                      style: TextStyle(
                        color: Colors.green.shade700,
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('刷新所有文件夹歌单', style: Theme.of(context).textTheme.titleMedium),
        ElevatedButton.icon(
          onPressed: _isRefreshing ? null : _showRefreshDialog,
          icon: _isRefreshing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.sync, size: 20),
          label: const Text('开始刷新'),
        ),
      ],
    );
  }
}

/// 文件夹歌单选择对话框
class _FolderSelectionDialog extends StatefulWidget {
  final List<Playlist> playlists;
  final void Function(Set<String> selectedIds) onStartRefresh;

  const _FolderSelectionDialog({
    required this.playlists,
    required this.onStartRefresh,
  });

  @override
  State<_FolderSelectionDialog> createState() => _FolderSelectionDialogState();
}

class _FolderSelectionDialogState extends State<_FolderSelectionDialog> {
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
      title: const Text('选择文件夹歌单'),
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
                    title: Row(
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: Icon(Icons.folder, size: 16),
                        ),
                        Flexible(
                          child: Text(
                            playlist.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    subtitle: Text('${playlist.songFilePaths.length} 首歌曲'),
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
              : () => widget.onStartRefresh(_selectedIds),
          child: const Text('开始刷新'),
        ),
      ],
    );
  }
}
