import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/library/duplicate_cleanup.dart';
import '../../services/library/duplicate_resolver.dart';
import '../playlist/playlist_content_notifier.dart';

enum _DuplicateMode { auto, manual, remove }

/// 打开去重对话框，返回 true 表示用户应用了改动。
Future<bool?> showDuplicateDialog(
  BuildContext context, {
  required List<DuplicateGroup> groups,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => DuplicateDialog(groups: groups),
  );
}

class DuplicateDialog extends StatefulWidget {
  const DuplicateDialog({super.key, required this.groups});

  final List<DuplicateGroup> groups;

  @override
  State<DuplicateDialog> createState() => _DuplicateDialogState();
}

class _DuplicateDialogState extends State<DuplicateDialog> {
  /// 手动模式里选中值为 -1 表示「保留整组、不隐藏任何副本」。
  static const int _keepAll = -1;

  late _DuplicateMode _mode;
  late Map<String, int> _selected;

  /// 「勾选并删除」模式：被勾选的 filePath。只可能来自重复组的候选。
  final Set<String> _checked = <String>{};
  bool _deleteSourceFiles = false;
  bool _applying = false;
  DuplicateCleanupResult? _result;
  String _error = '';

  @override
  void initState() {
    super.initState();
    final overrides = context.read<PlaylistContentNotifier>().dedupeOverrides;
    _mode = overrides.isEmpty ? _DuplicateMode.auto : _DuplicateMode.manual;
    _selected = <String, int>{
      for (final group in widget.groups)
        group.key: _initialSelection(group, overrides[group.key]),
    };
  }

  int _initialSelection(DuplicateGroup group, String? path) {
    if (path != null && path.isNotEmpty) {
      for (var i = 0; i < group.candidates.length; i++) {
        if (group.candidates[i].song.filePath == path) return i;
      }
    }
    // 需人工确认的组默认跟自动模式一致：整组保留，不替用户猜。
    return group.needsReview ? _keepAll : group.recommendedIndex;
  }

  void _useAllRecommendations() {
    setState(() {
      _selected = <String, int>{
        for (final group in widget.groups)
          group.key: group.needsReview ? _keepAll : group.recommendedIndex,
      };
    });
  }

  /// 按分组顺序收集被勾选的曲目，顺便做一次路径去重。
  List<DuplicateCleanupItem> _checkedItems() {
    final items = <DuplicateCleanupItem>[];
    final seen = <String>{};
    for (final group in widget.groups) {
      for (final candidate in group.candidates) {
        final path = candidate.song.filePath;
        if (_checked.contains(path) && seen.add(path)) {
          items.add(
            DuplicateCleanupItem(
              filePath: path,
              title: candidate.song.title,
            ),
          );
        }
      }
    }
    return items;
  }

  void _selectAllInferior() {
    setState(() {
      _checked.clear();
      for (final group in widget.groups) {
        for (var i = 0; i < group.candidates.length; i++) {
          if (i != group.recommendedIndex) {
            _checked.add(group.candidates[i].song.filePath);
          }
        }
      }
      _error = '';
    });
  }

  void _clearChecked() {
    setState(() {
      _checked.clear();
      _error = '';
    });
  }

  Future<void> _apply() async {
    if (_mode == _DuplicateMode.remove) {
      await _applyRemoval();
      return;
    }
    setState(() => _applying = true);
    final notifier = context.read<PlaylistContentNotifier>();
    try {
      if (_mode == _DuplicateMode.auto) {
        await notifier.applyDuplicateSelection(autoMode: true);
      } else {
        final overrides = <String, String>{};
        for (final group in widget.groups) {
          final index = _selected[group.key] ?? _keepAll;
          // 选了「保留全部副本」的组不写 override，让它回退到自动判定，
          // 自动判定在音质相同 / 歌手不一致时本来就会保留整组。
          if (index == _keepAll) continue;
          overrides[group.key] = group.candidates[index].song.filePath;
        }
        await notifier.applyDuplicateSelection(
          autoMode: false,
          overrides: overrides,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) setState(() => _applying = false);
    }
  }

  Future<void> _applyRemoval() async {
    final items = _checkedItems();
    if (items.isEmpty) {
      setState(() => _error = '请先勾选要删除的重复曲目');
      return;
    }
    final notifier = context.read<PlaylistContentNotifier>();
    setState(() {
      _applying = true;
      _error = '';
    });

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmDeleteDialog(
        items: items,
        deleteSourceFiles: _deleteSourceFiles,
      ),
    );
    if (confirmed != true) {
      if (mounted) setState(() => _applying = false);
      return;
    }

    try {
      final result = await DuplicateCleanup.run(
        items: items,
        deleteSourceFiles: _deleteSourceFiles,
      );
      // 删除失败的条目会留在音乐库里，避免源文件还在却从软件里消失。
      await notifier.removeSongsFromLibrary(result.pathsToRemove);
      if (!mounted) return;
      setState(() {
        _applying = false;
        _result = result;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _applying = false;
          _error = '删除失败：$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_result != null) return _resultDialog(theme);

    final autoRemovable = widget.groups.fold<int>(
      0,
      (sum, group) => sum + group.autoRemovableCount,
    );
    final manualRemovable = widget.groups.fold<int>(
      0,
      (sum, group) => sum + group.removableCount,
    );
    final reviewGroups = widget.groups
        .where((group) => group.needsReview)
        .toList(growable: false);
    final artistReview = reviewGroups
        .where((group) => group.reviewReason == '歌手不一致')
        .length;
    final tieReview = reviewGroups.length - artistReview;
    final checkedCount = _checkedItems().length;

    return AlertDialog(
      title: const Text('音乐去重'),
      content: SizedBox(
        width: 660,
        height: 470,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              switch (_mode) {
                _DuplicateMode.auto => '发现 ${widget.groups.length} 组重复，'
                    '自动模式可隐藏 $autoRemovable 首音质明确更差的副本。',
                _DuplicateMode.manual => '发现 ${widget.groups.length} 组重复，'
                    '手动模式最多可隐藏 $manualRemovable 首副本。',
                _DuplicateMode.remove => '发现 ${widget.groups.length} 组重复。'
                    '勾选要删除的副本，可选择只移出音乐库或同时删除源文件。',
              },
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Text(
              _mode == _DuplicateMode.remove
                  ? '删除范围只限下面重复组里的曲目，不会碰到其他歌曲；执行前会再次确认。'
                  : '按标题 + 专辑判定，忽略后缀；这两种模式只影响「全部歌曲」列表，'
                      '歌单、播放队列与磁盘文件都不会被删除。',
              style: theme.textTheme.bodySmall,
            ),
            if (reviewGroups.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '其中 ${reviewGroups.length} 组需人工确认'
                  '${artistReview > 0 ? '（$artistReview 组歌手不一致，可能是翻唱）' : ''}'
                  '${tieReview > 0 ? '（$tieReview 组音质相同，无法判定）' : ''}'
                  '。自动 / 手动模式保留整组；勾选删除时请自行确认。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.tertiary,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: SegmentedButton<_DuplicateMode>(
                    segments: const <ButtonSegment<_DuplicateMode>>[
                      ButtonSegment<_DuplicateMode>(
                        value: _DuplicateMode.auto,
                        label: Text('自动保留最佳'),
                        icon: Icon(Icons.auto_awesome, size: 16),
                      ),
                      ButtonSegment<_DuplicateMode>(
                        value: _DuplicateMode.manual,
                        label: Text('手动选择'),
                        icon: Icon(Icons.touch_app, size: 16),
                      ),
                      ButtonSegment<_DuplicateMode>(
                        value: _DuplicateMode.remove,
                        label: Text('勾选并删除'),
                        icon: Icon(Icons.delete_outline, size: 16),
                      ),
                    ],
                    selected: <_DuplicateMode>{_mode},
                    onSelectionChanged: (selection) {
                      if (selection.isNotEmpty && !_applying) {
                        setState(() {
                          _mode = selection.first;
                          _error = '';
                        });
                      }
                    },
                  ),
                ),
                if (_mode != _DuplicateMode.remove) ...<Widget>[
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: '全部采用推荐版本',
                    onPressed: _applying ? null : _useAllRecommendations,
                    icon: const Icon(Icons.done_all, size: 20),
                  ),
                ],
              ],
            ),
            if (_mode == _DuplicateMode.remove)
              _removeToolbar(checkedCount, theme),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.separated(
                itemCount: widget.groups.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final group = widget.groups[index];
                  return _mode == _DuplicateMode.remove
                      ? _removeGroupCard(group, theme)
                      : _groupCard(group, theme);
                },
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _applying ? null : () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          style: _mode == _DuplicateMode.remove
              ? FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                )
              : null,
          onPressed: _applying ? null : _apply,
          child: _applying
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_mode == _DuplicateMode.remove ? '删除所选' : '应用'),
        ),
      ],
    );
  }

  Widget _removeToolbar(int checkedCount, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                '已勾选 $checkedCount 首待删除',
                style: theme.textTheme.bodyMedium,
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _applying ? null : _selectAllInferior,
                icon: const Icon(Icons.playlist_add_check, size: 16),
                label: const Text('全选非推荐版本'),
              ),
              TextButton(
                onPressed: _applying ? null : _clearChecked,
                child: const Text('清空'),
              ),
            ],
          ),
          SwitchListTile(
            value: _deleteSourceFiles,
            onChanged: _applying
                ? null
                : (value) => setState(() => _deleteSourceFiles = value),
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('同时删除源文件'),
            subtitle: Text(
              _deleteSourceFiles
                  ? '本地 → Windows 回收站（失败则移到应用回收站）；'
                      'Google Drive → Drive 回收站；'
                      'WebDAV / FTP 暂不支持，只移出音乐库。'
                  : '默认关闭：只把勾选曲目从所有歌单移除，'
                      '磁盘与云端文件完全保留。',
              style: theme.textTheme.bodySmall,
            ),
          ),
          if (_error.isNotEmpty)
            Text(
              _error,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
        ],
      ),
    );
  }

  Widget _groupHeader(DuplicateGroup group, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                group.displayTitle,
                style: theme.textTheme.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (group.needsReview)
              Text(
                '需人工确认 · ${group.reviewReason}',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.tertiary,
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          '专辑：${group.displayAlbum} · ${group.candidates.length} 个版本',
          style: theme.textTheme.bodySmall,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _groupCard(DuplicateGroup group, ThemeData theme) {
    final selected = _selected[group.key] ?? group.recommendedIndex;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _groupHeader(group, theme),
            const SizedBox(height: 2),
            if (group.needsReview) _keepAllTile(group, selected, theme),
            for (var i = 0; i < group.candidates.length; i++)
              _candidateTile(group, i, selected, theme),
          ],
        ),
      ),
    );
  }

  Widget _removeGroupCard(DuplicateGroup group, ThemeData theme) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _groupHeader(group, theme),
            const SizedBox(height: 2),
            for (var i = 0; i < group.candidates.length; i++)
              _checkTile(group, i, theme),
          ],
        ),
      ),
    );
  }

  /// 自动模式下「需人工确认」的组没有副本会被隐藏，所以这里也给出
  /// 一个可见的选中项，避免整组 radio 都没有选中态让人以为界面坏了。
  Widget _keepAllTile(DuplicateGroup group, int selected, ThemeData theme) {
    final autoLocked = _mode == _DuplicateMode.auto;
    return RadioListTile<int>(
      value: _keepAll,
      groupValue: autoLocked ? _keepAll : selected,
      onChanged: autoLocked
          ? null
          : (value) {
              if (value != null) {
                setState(() => _selected[group.key] = value);
              }
            },
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(
        '保留全部副本（不隐藏）',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.tertiary,
        ),
      ),
    );
  }

  Widget _candidateTile(
    DuplicateGroup group,
    int index,
    int selected,
    ThemeData theme,
  ) {
    final candidate = group.candidates[index];
    final recommended = index == group.recommendedIndex;
    final path = candidate.song.filePath;
    final shortPath = path.length > 110 ? '${path.substring(0, 110)}…' : path;
    final autoLocked = _mode == _DuplicateMode.auto;

    return RadioListTile<int>(
      value: index,
      groupValue: autoLocked
          ? (group.needsReview ? _keepAll : group.recommendedIndex)
          : selected,
      onChanged: autoLocked
          ? null
          : (value) {
              if (value != null) {
                setState(() => _selected[group.key] = value);
              }
            },
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: _candidateTitle(candidate.qualityLabel, recommended, theme),
      subtitle: Text(
        '${candidate.sourceLabel} · $shortPath',
        style: theme.textTheme.bodySmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _checkTile(DuplicateGroup group, int index, ThemeData theme) {
    final candidate = group.candidates[index];
    final path = candidate.song.filePath;
    final checked = _checked.contains(path);
    final recommended = index == group.recommendedIndex;
    final shortPath = path.length > 100 ? '${path.substring(0, 100)}…' : path;

    return CheckboxListTile(
      value: checked,
      onChanged: _applying
          ? null
          : (value) {
              setState(() {
                if (value == true) {
                  _checked.add(path);
                } else {
                  _checked.remove(path);
                }
                _error = '';
              });
            },
      dense: true,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: _candidateTitle(candidate.qualityLabel, recommended, theme),
      subtitle: Text(
        '${candidate.sourceLabel} · $shortPath',
        style: theme.textTheme.bodySmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _candidateTitle(String label, bool recommended, ThemeData theme) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (recommended)
          Text(
            '推荐',
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.primary,
            ),
          ),
      ],
    );
  }

  /// 删除完成后不关闭对话框，直接在原窗口展示逐条结果，方便核对哪些
  /// 源文件没有删掉、去了哪个回收站。
  Widget _resultDialog(ThemeData theme) {
    final result = _result!;
    return AlertDialog(
      title: const Text('删除结果'),
      content: SizedBox(
        width: 660,
        height: 470,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '已从音乐库移除 ${result.pathsToRemove.length} 首；'
              '源文件移入回收站 ${result.recycledCount} 首，'
              '不支持删除源文件 ${result.unsupportedCount} 首，'
              '失败 ${result.failedCount} 首。',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Text(
              '删除失败的那几首仍保留在音乐库中，源文件也还在；'
              '所有删除都进回收站，可恢复，没有永久删除。',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.separated(
                itemCount: result.details.length,
                separatorBuilder: (_, __) => const SizedBox(height: 4),
                itemBuilder: (context, index) =>
                    _detailTile(result.details[index], theme),
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('完成'),
        ),
      ],
    );
  }

  Widget _detailTile(DuplicateCleanupDetail detail, ThemeData theme) {
    final color = switch (detail.action) {
      SourceFileAction.failed => theme.colorScheme.error,
      SourceFileAction.unsupported => theme.colorScheme.tertiary,
      _ => theme.colorScheme.onSurface,
    };
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        detail.action == SourceFileAction.failed
            ? Icons.error_outline
            : detail.recycled
                ? Icons.delete_sweep_outlined
                : Icons.check_circle_outline,
        size: 18,
        color: color,
      ),
      title: Text(
        detail.title,
        style: theme.textTheme.bodyMedium?.copyWith(color: color),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${detail.message}\n${detail.filePath}',
        style: theme.textTheme.bodySmall,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// 删除前的二次确认：逐条列出标题与完整路径，并明确说明会不会动源文件。
class _ConfirmDeleteDialog extends StatelessWidget {
  const _ConfirmDeleteDialog({
    required this.items,
    required this.deleteSourceFiles,
  });

  final List<DuplicateCleanupItem> items;
  final bool deleteSourceFiles;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('确认删除'),
      content: SizedBox(
        width: 620,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              deleteSourceFiles
                  ? '即将把下面 ${items.length} 首曲目移出音乐库，并把源文件移入回收站。'
                  : '即将把下面 ${items.length} 首曲目移出音乐库，源文件完全保留。',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Text(
              deleteSourceFiles
                  ? '不是永久删除：本地进 Windows / 应用回收站，'
                      'Google Drive 进 Drive 回收站；WebDAV / FTP 只移出音乐库。'
                  : '此操作只改歌单里的引用，磁盘与云端文件不会被删除。',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.audiotrack_outlined, size: 18),
                    title: Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      item.filePath,
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('确认删除'),
        ),
      ],
    );
  }
}
