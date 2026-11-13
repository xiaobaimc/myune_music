import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../services/network/network_media_service.dart';
import '../../services/network/remote_entry.dart';
import '../../services/network/remote_source.dart';
import '../playlist/playlist_content_notifier.dart';

enum _ScanOrigin { local, remote }

/// 打开「自动扫描目录」对话框：选一个目录（本地 / 云端），自动递归找出
/// 其中所有音频并导入「全部歌曲」。
Future<void> showAutoScanImportDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (_) => const AutoScanImportDialog(),
  );
}

class AutoScanImportDialog extends StatefulWidget {
  const AutoScanImportDialog({super.key});

  @override
  State<AutoScanImportDialog> createState() => _AutoScanImportDialogState();
}

class _AutoScanImportDialogState extends State<AutoScanImportDialog> {
  _ScanOrigin _origin = _ScanOrigin.local;
  String _localFolder = '';
  List<RemoteSource> _sources = <RemoteSource>[];
  RemoteSource? _source;
  String _remotePath = '';
  String _remoteLabel = '';
  bool _busy = false;
  bool _cancel = false;
  int _found = 0;
  int _dirs = 0;
  int _added = 0;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _loadSources();
  }

  Future<void> _loadSources() async {
    await RemoteSourceStore.instance.load();
    if (!mounted) return;
    setState(() {
      _sources = RemoteSourceStore.instance.sources;
      if (_sources.isNotEmpty) _source = _sources.first;
    });
  }

  Future<void> _pickLocalFolder() async {
    final folder = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择要自动扫描的音乐文件夹',
    );
    if (folder == null || !mounted) return;
    setState(() {
      _localFolder = folder;
      _status = '';
      _found = 0;
      _added = 0;
    });
  }

  Future<void> _pickRemoteDirectory() async {
    final source = _source;
    if (source == null) return;
    final picked = await _showRemoteDirectoryPicker(context, source: source);
    if (picked == null || !mounted) return;
    setState(() {
      _remotePath = picked.path;
      _remoteLabel = picked.label;
      _status = '';
      _found = 0;
      _added = 0;
    });
  }

  void _setStatus(String text) {
    if (mounted) setState(() => _status = text);
  }

  Future<void> _start() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _cancel = false;
      _found = 0;
      _dirs = 0;
      _added = 0;
      _status = '准备扫描…';
    });
    final notifier = context.read<PlaylistContentNotifier>();
    try {
      if (_origin == _ScanOrigin.local) {
        await _scanLocal(notifier);
      } else {
        await _scanRemote(notifier);
      }
    } catch (error) {
      _setStatus('扫描失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scanLocal(PlaylistContentNotifier notifier) async {
    if (_localFolder.isEmpty) {
      _setStatus('请先选择一个本地文件夹');
      return;
    }
    final directory = Directory(_localFolder);
    if (!await directory.exists()) {
      _setStatus('文件夹不存在或无法访问');
      return;
    }
    _setStatus('正在递归扫描本地文件夹…');
    final paths = <String>[];
    await for (final entity in directory
        .list(recursive: true, followLinks: false)
        .handleError((_) {})) {
      if (_cancel) break;
      if (entity is File && RemoteEntry.isAudioName(entity.path)) {
        paths.add(p.normalize(entity.path));
        if (paths.length % 40 == 0) {
          _setStatus('已找到 ${paths.length} 首音频…');
        }
      }
    }
    if (!mounted) return;
    if (_cancel) {
      _setStatus('已取消扫描（找到 ${paths.length} 首，未导入）');
      return;
    }
    setState(() => _found = paths.length);
    if (paths.isEmpty) {
      _setStatus('这个文件夹及其子目录里没有找到音频文件');
      return;
    }
    _setStatus('共找到 ${paths.length} 首，正在导入「全部歌曲」…');
    final added = await notifier.addLocalSongsToAllSongs(paths);
    if (!mounted) return;
    setState(() {
      _added = added;
      _status = '完成：扫描到 ${paths.length} 首，新增 $added 首到「全部歌曲」'
          '（已存在的不会重复添加）';
    });
  }

  Future<void> _scanRemote(PlaylistContentNotifier notifier) async {
    final source = _source;
    if (source == null) {
      _setStatus('请先在「网络媒体」里添加一个网络源');
      return;
    }
    _setStatus('正在连接本机流代理…');
    if (!await NetworkMediaService.ensureProxy()) {
      _setStatus('本机流代理未启动（端口 18765-18774 可能被占用），请重启应用后再试');
      return;
    }
    _setStatus('正在递归扫描云端目录…');
    final result = await NetworkMediaService.scanDirectory(
      source,
      _remotePath,
      onProgress: (found, dirs) {
        if (!mounted) return;
        setState(() {
          _found = found;
          _dirs = dirs;
          _status = '已扫描 $dirs 个目录，找到 $found 首音频…';
        });
      },
      isCancelled: () => _cancel,
    );
    if (!mounted) return;
    if (result.cancelled) {
      _setStatus('已取消扫描');
      return;
    }
    setState(() => _dirs = result.directories);
    if (result.entries.isEmpty) {
      _setStatus('该目录及其子目录里没有找到音频文件');
      return;
    }
    _setStatus('共找到 ${result.entries.length} 首，正在导入「全部歌曲」…');
    final album = _remoteLabel.isEmpty
        ? '${source.name} · 自动扫描'
        : '${source.name} · $_remoteLabel（含子目录）';
    final paths = result.entries
        .map(
          (entry) => NetworkMediaService.nasSong(
            source: source,
            entry: entry,
            album: album,
          ).filePath,
        )
        .toList();
    final added = await notifier.addNetworkSongsToAllSongs(paths);
    if (!mounted) return;
    setState(() {
      _added = added;
      _status = '完成：扫描 ${result.directories} 个目录、找到 '
          '${result.entries.length} 首，新增 $added 首到「全部歌曲」'
          '${result.truncated ? '（已达扫描上限，结果可能不完整）' : ''}';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('自动扫描目录并导入'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '选一个目录，自动递归找出里面所有音频并加入「全部歌曲」。'
              '已存在的歌曲不会重复添加。',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            SegmentedButton<_ScanOrigin>(
              segments: const <ButtonSegment<_ScanOrigin>>[
                ButtonSegment<_ScanOrigin>(
                  value: _ScanOrigin.local,
                  label: Text('本地文件夹'),
                  icon: Icon(Icons.folder_open, size: 16),
                ),
                ButtonSegment<_ScanOrigin>(
                  value: _ScanOrigin.remote,
                  label: Text('云端目录'),
                  icon: Icon(Icons.cloud_outlined, size: 16),
                ),
              ],
              selected: <_ScanOrigin>{_origin},
              onSelectionChanged: (selection) {
                if (selection.isNotEmpty && !_busy) {
                  setState(() {
                    _origin = selection.first;
                    _status = '';
                  });
                }
              },
            ),
            const SizedBox(height: 12),
            if (_origin == _ScanOrigin.local)
              _localPane(theme)
            else
              _remotePane(theme),
            const SizedBox(height: 14),
            if (_busy)
              const LinearProgressIndicator()
            else
              const SizedBox(height: 4),
            const SizedBox(height: 8),
            Text(
              _status.isEmpty ? '尚未开始扫描' : _status,
              style: theme.textTheme.bodySmall,
            ),
            if (_found > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '找到 $_found 首'
                  '${_dirs > 0 ? ' · 扫描 $_dirs 个目录' : ''}'
                  '${_added > 0 ? ' · 新增 $_added 首' : ''}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        if (_busy)
          TextButton(
            onPressed: () => setState(() => _cancel = true),
            child: const Text('取消扫描'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
        FilledButton(
          onPressed: _busy ? null : _start,
          child: const Text('开始扫描并导入'),
        ),
      ],
    );
  }

  Widget _localPane(ThemeData theme) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            _localFolder.isEmpty ? '未选择文件夹' : _localFolder,
            style: theme.textTheme.bodyMedium,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: _busy ? null : _pickLocalFolder,
          icon: const Icon(Icons.folder_open, size: 16),
          label: const Text('选择文件夹'),
        ),
      ],
    );
  }

  Widget _remotePane(ThemeData theme) {
    if (_sources.isEmpty) {
      return Text(
        '还没有保存的网络源。请先到「网络媒体」页添加 WebDAV / FTP / Google Drive。',
        style: theme.textTheme.bodySmall,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text('网络源：', style: theme.textTheme.bodyMedium),
            Expanded(
              child: DropdownButton<String>(
                value: _source?.id,
                isExpanded: true,
                items: <DropdownMenuItem<String>>[
                  for (final source in _sources)
                    DropdownMenuItem<String>(
                      value: source.id,
                      child: Text(
                        source.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() {
                          _source = _sources.firstWhere((s) => s.id == value);
                          _remotePath = '';
                          _remoteLabel = '';
                          _status = '';
                        });
                      },
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                _remoteLabel.isEmpty
                    ? '未选择目录（将扫描该网络源的根目录）'
                    : '目录：$_remoteLabel',
                style: theme.textTheme.bodyMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : _pickRemoteDirectory,
              icon: const Icon(Icons.account_tree_outlined, size: 16),
              label: const Text('浏览目录'),
            ),
          ],
        ),
      ],
    );
  }
}

/// 云端目录选择结果。
class _RemoteDirectoryPick {
  const _RemoteDirectoryPick({required this.path, required this.label});

  final String path;
  final String label;
}

Future<_RemoteDirectoryPick?> _showRemoteDirectoryPicker(
  BuildContext context, {
  required RemoteSource source,
}) {
  return showDialog<_RemoteDirectoryPick>(
    context: context,
    builder: (_) => RemoteDirectoryPicker(source: source),
  );
}

/// 通用云端目录树：只列子文件夹，支持面包屑回退，对 WebDAV / FTP /
/// Google Drive 三种源都走同一个 listDirectory 接口。
class RemoteDirectoryPicker extends StatefulWidget {
  const RemoteDirectoryPicker({super.key, required this.source});

  final RemoteSource source;

  @override
  State<RemoteDirectoryPicker> createState() => _RemoteDirectoryPickerState();
}

class _RemoteDirectoryPickerState extends State<RemoteDirectoryPicker> {
  late String _current;
  final List<String> _crumbLabels = <String>[];
  final List<String> _crumbPaths = <String>[];
  List<RemoteEntry> _folders = <RemoteEntry>[];
  bool _loading = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _current = NetworkMediaService.rootOf(widget.source);
    _crumbLabels.add('根目录');
    _crumbPaths.add(_current);
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = '';
      });
    }
    try {
      final entries = await NetworkMediaService.listDirectory(
        widget.source,
        _current,
      );
      final folders = entries.where((entry) => entry.isDirectory).toList();
      if (!mounted) return;
      setState(() {
        _folders = folders;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '读取目录失败：$error';
      });
    }
  }

  void _enter(RemoteEntry folder) {
    setState(() {
      _current = folder.path;
      _crumbLabels.add(folder.name);
      _crumbPaths.add(folder.path);
      _folders = <RemoteEntry>[];
    });
    _load();
  }

  void _jump(int index) {
    setState(() {
      _current = _crumbPaths[index];
      _crumbLabels.removeRange(index + 1, _crumbLabels.length);
      _crumbPaths.removeRange(index + 1, _crumbPaths.length);
      _folders = <RemoteEntry>[];
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('选择云端目录'),
      content: SizedBox(
        width: 520,
        height: 380,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Wrap(
              spacing: 2,
              children: <Widget>[
                for (var i = 0; i < _crumbLabels.length; i++)
                  TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: i == _crumbLabels.length - 1
                        ? null
                        : () => _jump(i),
                    child: Text(i == 0 ? _crumbLabels[i] : '/ ${_crumbLabels[i]}'),
                  ),
              ],
            ),
            const Divider(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error.isNotEmpty
                      ? Center(child: Text(_error, style: theme.textTheme.bodySmall))
                      : _folders.isEmpty
                          ? Center(
                              child: Text(
                                '这个目录里没有子文件夹',
                                style: theme.textTheme.bodySmall,
                              ),
                            )
                          : ListView.builder(
                              itemCount: _folders.length,
                              itemBuilder: (context, index) {
                                final folder = _folders[index];
                                return ListTile(
                                  dense: true,
                                  leading: const Icon(Icons.folder_outlined, size: 20),
                                  title: Text(
                                    folder.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onTap: () => _enter(folder),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            _RemoteDirectoryPick(
              path: _current,
              label: _crumbLabels.length > 1 ? _crumbLabels.last : '',
            ),
          ),
          child: const Text('使用此文件夹'),
        ),
      ],
    );
  }
}
