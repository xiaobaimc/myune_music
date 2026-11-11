import 'package:flutter/material.dart';

import '../../services/network/google_drive_client.dart';
import '../../services/network/remote_entry.dart';
import '../../services/network/remote_source.dart';

/// 一次「选择默认文件夹」的结果。
class GoogleDriveFolderPick {
  const GoogleDriveFolderPick({
    required this.id,
    required this.name,
    required this.breadcrumb,
  });

  /// 空字符串代表「整个我的云端硬盘」，与 [RemoteSource.rootFolderId] 一致。
  final String id;
  final String name;
  final List<String> breadcrumb;

  String get pathLabel => breadcrumb.join(' / ');
}

/// 打开图形化文件夹选择器：面包屑导航 + 子文件夹列表 + 新建文件夹。
///
/// 全程走 Drive API v3，只需要 [source] 里已经有可用的 refresh_token；
/// 没有任何网页跳转，也不依赖外部浏览器。
Future<GoogleDriveFolderPick?> showGoogleDriveFolderPicker(
  BuildContext context, {
  required RemoteSource source,
  String initialFolderId = '',
}) {
  return showDialog<GoogleDriveFolderPick>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _GoogleDriveFolderPicker(
      source: source,
      initialFolderId: initialFolderId,
    ),
  );
}

class _Crumb {
  const _Crumb(this.id, this.name);

  final String id;
  final String name;
}

class _GoogleDriveFolderPicker extends StatefulWidget {
  const _GoogleDriveFolderPicker({
    required this.source,
    required this.initialFolderId,
  });

  final RemoteSource source;
  final String initialFolderId;

  @override
  State<_GoogleDriveFolderPicker> createState() =>
      _GoogleDriveFolderPickerState();
}

class _GoogleDriveFolderPickerState
    extends State<_GoogleDriveFolderPicker> {
  late final GoogleDriveClient _client;
  late List<_Crumb> _crumbs;
  List<RemoteEntry> _folders = <RemoteEntry>[];
  bool _loading = true;
  String? _error;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _client = GoogleDriveClient(widget.source);
    final initial = widget.initialFolderId.trim();
    _crumbs = <_Crumb>[
      const _Crumb('root', '我的云端硬盘'),
      if (initial.isNotEmpty && initial != 'root')
        _Crumb(initial, '当前默认文件夹'),
    ];
    _load();
  }

  String get _currentId => _crumbs.last.id;
  String get _currentName => _crumbs.last.name;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final folders = await _client.listFolders(_currentId);
      if (!mounted) return;
      setState(() {
        _folders = folders;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _folders = <RemoteEntry>[];
        _loading = false;
        _error = '$error';
      });
    }
  }

  void _open(RemoteEntry entry) {
    setState(() {
      _crumbs = <_Crumb>[
        ..._crumbs,
        _Crumb(GoogleDriveClient.fileIdOf(entry.path), entry.name),
      ];
    });
    _load();
  }

  void _goToCrumb(int index) {
    if (index >= _crumbs.length - 1) return;
    setState(() => _crumbs = _crumbs.sublist(0, index + 1));
    _load();
  }

  Future<void> _createFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('新建文件夹'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '文件夹名称',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value.trim()),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || !mounted) return;
    setState(() => _creating = true);
    try {
      await _client.createFolder(_currentId, name);
      if (!mounted) return;
      setState(() => _creating = false);
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _creating = false;
        _error = '新建失败：$error';
      });
    }
  }

  void _confirm() {
    Navigator.of(context).pop(
      GoogleDriveFolderPick(
        id: _currentId == 'root' ? '' : _currentId,
        name: _currentName,
        breadcrumb: _crumbs.map((c) => c.name).toList(growable: false),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('选择默认读取的文件夹'),
      content: SizedBox(
        width: 560,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              '选中一个文件夹后点「使用此文件夹」；留空（我的云端硬盘）则浏览整个 Drive。',
              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Wrap(
                spacing: 2,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  for (var i = 0; i < _crumbs.length; i++) ...<Widget>[
                    if (i > 0)
                      Icon(
                        Icons.chevron_right,
                        size: 14,
                        color: scheme.onSurfaceVariant,
                      ),
                    InkWell(
                      onTap: () => _goToCrumb(i),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        child: Text(
                          _crumbs[i].name,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: i == _crumbs.length - 1
                                ? scheme.primary
                                : scheme.onSurfaceVariant,
                            fontWeight: i == _crumbs.length - 1
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _buildList(scheme),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton.icon(
          onPressed: _creating ? null : _createFolder,
          icon: _creating
              ? const SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.create_new_folder_outlined, size: 16),
          label: const Text('新建文件夹'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _confirm,
          child: const Text('使用此文件夹'),
        ),
      ],
    );
  }

  Widget _buildList(ColorScheme scheme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.error_outline, size: 30, color: scheme.error),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11.5, height: 1.5),
              ),
              const SizedBox(height: 10),
              FilledButton.tonalIcon(
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    if (_folders.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.folder_open_outlined,
              size: 34,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            Text(
              '这个文件夹里没有子文件夹',
              style: TextStyle(
                fontSize: 11.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      itemCount: _folders.length,
      itemBuilder: (context, index) {
        final folder = _folders[index];
        return ListTile(
          dense: true,
          leading: Icon(
            Icons.folder_outlined,
            size: 18,
            color: scheme.primary,
          ),
          title: Text(folder.name, style: const TextStyle(fontSize: 12.5)),
          trailing: const Icon(Icons.chevron_right, size: 18),
          onTap: () => _open(folder),
        );
      },
    );
  }
}
