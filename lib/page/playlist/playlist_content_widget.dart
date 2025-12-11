import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';

import 'playlist_content_notifier.dart';
import 'playlist_models.dart';
import '../../widgets/sort_dialog.dart';
import '../setting/settings_provider.dart';

enum ManagementMode { manual, folder }

class PlaylistContentWidget extends StatelessWidget {
  const PlaylistContentWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // 获取窗口宽高比
    final aspectRatio = MediaQuery.of(context).size.aspectRatio;
    final isPortrait = aspectRatio <= 1.0; // 竖屏判断

    return Container(
      color: colorScheme.surface,
      child: Row(
        children: [
          // 竖屏时隐藏歌单列表
          if (!isPortrait) ...[
            const SizedBox(width: 150, child: PlaylistListWidget()),
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: colorScheme.outlineVariant,
              indent: 0,
              endIndent: 0,
            ),
          ],
          const Expanded(child: HeadSongListWidget()),
        ],
      ),
    );
  }
}

class PlaylistListWidget extends StatelessWidget {
  const PlaylistListWidget({super.key});

  void _showAddPlaylistDialog(
    BuildContext context,
    PlaylistContentNotifier notifier,
  ) {
    showDialog(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        final List<String> selectedFolders = [];
        ManagementMode selectedMode = ManagementMode.manual; // 默认为手动管理

        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('添加新歌单'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Focus(
                      onFocusChange: (hasFocus) {
                        final notifier = context
                            .read<PlaylistContentNotifier>();
                        notifier.setDisableHotKeys(hasFocus);
                      },
                      child: TextField(
                        controller: controller,
                        decoration: const InputDecoration(hintText: '输入歌单名称'),
                        autofocus: true,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('选择管理模式：'),
                    RadioGroup<ManagementMode>(
                      groupValue: selectedMode,
                      onChanged: (value) {
                        setState(() {
                          selectedMode = value!;
                        });
                      },
                      child: const Column(
                        children: [
                          // 手动管理模式单选按钮
                          RadioListTile<ManagementMode>(
                            contentPadding: EdgeInsets.zero,
                            title: Text('手动管理歌单歌曲'),
                            value: ManagementMode.manual,
                          ),
                          // 文件夹管理模式单选按钮
                          RadioListTile<ManagementMode>(
                            contentPadding: EdgeInsets.zero,
                            title: Text('使用文件夹管理歌单'),
                            value: ManagementMode.folder,
                          ),
                        ],
                      ),
                    ),
                    if (selectedMode == ManagementMode.folder) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: () async {
                              final folder = await FilePicker.platform
                                  .getDirectoryPath(
                                    dialogTitle: '请选择文件夹',
                                    lockParentWindow: true,
                                  );
                              if (folder != null) {
                                setState(() {
                                  if (!selectedFolders.contains(folder)) {
                                    selectedFolders.add(folder);
                                  }
                                });
                              }
                            },
                            icon: const Icon(Icons.folder_open),
                            label: const Text('添加文件夹'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: () async {
                              final controller = TextEditingController();
                              final folder = await showDialog<String>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('输入文件夹路径'),
                                  content: TextField(
                                    controller: controller,
                                    decoration: const InputDecoration(
                                      labelText: '文件夹路径',
                                      hintText: '请输入绝对路径',
                                      border: OutlineInputBorder(),
                                    ),
                                    autofocus: true,
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('取消'),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        if (controller.text.isNotEmpty) {
                                          Navigator.pop(
                                            context,
                                            controller.text,
                                          );
                                        }
                                      },
                                      child: const Text('确定'),
                                    ),
                                  ],
                                ),
                              );

                              if (folder != null && folder.isNotEmpty) {
                                setState(() {
                                  if (!selectedFolders.contains(folder)) {
                                    selectedFolders.add(folder);
                                  }
                                });
                              }
                            },
                            icon: const Icon(Icons.input),
                            label: const Text('输入路径'),
                          ),
                        ],
                      ),
                      if (selectedFolders.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 100,
                          child: Scrollbar(
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: List.generate(
                                  selectedFolders.length,
                                  (index) => ListTile(
                                    title: Text(
                                      selectedFolders[index],
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    dense: true,
                                    trailing: IconButton(
                                      icon: const Icon(Icons.delete, size: 18),
                                      onPressed: () {
                                        setState(() {
                                          selectedFolders.removeAt(index);
                                        });
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final notifier = context.read<PlaylistContentNotifier>();

                    if (selectedMode == ManagementMode.folder &&
                        selectedFolders.isEmpty) {
                      // 选择了文件夹管理模式但未选择文件夹
                      notifier.postInfo('请选择至少一个文件夹');
                      return;
                    }

                    if (selectedMode == ManagementMode.folder) {
                      // 创建基于文件夹的播放列表
                      if (notifier.addPlaylist(
                        controller.text,
                        folderPaths: selectedFolders,
                      )) {
                        Navigator.of(context).pop();
                      }
                    } else {
                      // 创建普通播放列表（手动管理）
                      if (notifier.addPlaylist(controller.text)) {
                        Navigator.of(context).pop();
                      }
                    }
                  },
                  child: const Text('添加'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showContextMenu(
    Offset position,
    int? index,
    BuildContext context,
  ) async {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final playlistNotifier = Provider.of<PlaylistContentNotifier>(
      context,
      listen: false,
    );

    final List<PopupMenuItem<String>> menuItems = [];
    if (index == null) {
      menuItems.add(
        const PopupMenuItem<String>(value: 'add', child: Text('添加歌单')),
      );
    } else {
      menuItems.add(
        const PopupMenuItem<String>(value: 'edit', child: Text('编辑歌单')),
      );
      // 只有非默认歌单才能删除
      if (!playlistNotifier.playlists[index].isDefault) {
        menuItems.add(
          const PopupMenuItem<String>(value: 'delete', child: Text('删除歌单')),
        );
      }
      // 如果是基于文件夹的播放列表，添加编辑文件夹选项
      if (playlistNotifier.playlists[index].isFolderBased) {
        menuItems.add(
          const PopupMenuItem<String>(
            value: 'editFolders',
            child: Text('编辑文件夹'),
          ),
        );
      }
    }

    final result = await showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        overlay.size.width - position.dx,
        overlay.size.height - position.dy,
      ),
      items: menuItems,
    );

    if (result == 'add') {
      if (context.mounted) {
        _showAddPlaylistDialog(context, playlistNotifier);
      }
    } else if (result == 'delete' && index != null) {
      final bool deleted = await playlistNotifier.deletePlaylist(index);
      if (!deleted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('默认歌单不可删除')),
        ); // 这里不改了，因为这句话可能用户永远都看不到
      }
    } else if (result == 'edit' && index != null) {
      if (context.mounted) {
        _showEditPlaylistDialog(context, index, playlistNotifier);
      }
    } else if (result == 'editFolders' && index != null) {
      if (context.mounted) {
        _showEditFoldersDialog(context, index, playlistNotifier);
      }
    }
  }

  void _showEditPlaylistDialog(
    BuildContext context,
    int index,
    PlaylistContentNotifier notifier,
  ) {
    final controller = TextEditingController(
      text: notifier.playlists[index].name,
    );
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('编辑歌单名称'),
          content: Focus(
            onFocusChange: (hasFocus) {
              final notifier = context.read<PlaylistContentNotifier>();
              notifier.setDisableHotKeys(hasFocus);
            },
            child: TextField(
              controller: controller,
              decoration: const InputDecoration(hintText: '输入新的歌单名称'),
              autofocus: true,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () {
                final newName = controller.text.trim();
                final notifier = context.read<PlaylistContentNotifier>();

                if (notifier.editPlaylistName(index, newName)) {
                  // 仅在操作成功时关闭对话框
                  Navigator.of(context).pop();
                }
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.read<PlaylistContentNotifier>();

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8.0),
          child: ElevatedButton.icon(
            onPressed: () => _showAddPlaylistDialog(context, notifier),
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('添加歌单'),
          ),
        ),
        Expanded(
          // 使用 Selector 精确订阅歌单列表和选中索引的变化
          child: Selector<PlaylistContentNotifier, (List<Playlist>, int)>(
            selector: (_, n) => (n.playlists, n.selectedIndex),
            builder: (context, data, _) {
              final (playlists, selectedIndex) = data;

              return ListView.builder(
                itemCount: playlists.length,
                itemBuilder: (context, index) {
                  final playlist = playlists[index];
                  return PlaylistTileWidget(
                    key: ValueKey(playlist.name), // 使用唯一Key
                    index: index,
                    name: playlist.name,
                    isDefault: playlist.isDefault,
                    isSelected: selectedIndex == index,
                    isFolderBased: playlist.isFolderBased,
                    onSecondaryTap: (position) {
                      _showContextMenu(position, index, context);
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _showEditFoldersDialog(
    BuildContext context,
    int index,
    PlaylistContentNotifier notifier,
  ) {
    final playlist = notifier.playlists[index];
    // 创建一个副本以避免直接修改原始列表
    final List<String> selectedFolders = List<String>.from(
      playlist.folderPaths,
    );

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('编辑文件夹'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () async {
                        final folder = await FilePicker.platform
                            .getDirectoryPath(
                              dialogTitle: '请选择文件夹',
                              lockParentWindow: true,
                            );
                        if (folder != null) {
                          setState(() {
                            if (!selectedFolders.contains(folder)) {
                              selectedFolders.add(folder);
                            }
                          });
                        }
                      },
                      icon: const Icon(Icons.folder_open),
                      label: const Text('添加文件夹'),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: () async {
                        final controller = TextEditingController();
                        final folder = await showDialog<String>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('输入文件夹路径'),
                            content: TextField(
                              controller: controller,
                              decoration: const InputDecoration(
                                labelText: '文件夹路径',
                                hintText: '请输入绝对路径',
                                border: OutlineInputBorder(),
                              ),
                              autofocus: true,
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('取消'),
                              ),
                              TextButton(
                                onPressed: () {
                                  if (controller.text.isNotEmpty) {
                                    Navigator.pop(context, controller.text);
                                  }
                                },
                                child: const Text('确定'),
                              ),
                            ],
                          ),
                        );

                        if (folder != null && folder.isNotEmpty) {
                          setState(() {
                            if (!selectedFolders.contains(folder)) {
                              selectedFolders.add(folder);
                            }
                          });
                        }
                      },
                      icon: const Icon(Icons.input),
                      label: const Text('输入路径'),
                    ),
                    if (selectedFolders.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 150,
                        child: Scrollbar(
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: List.generate(
                                selectedFolders.length,
                                (index) => ListTile(
                                  title: Text(
                                    selectedFolders[index],
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  dense: true,
                                  trailing: IconButton(
                                    icon: const Icon(Icons.delete, size: 18),
                                    onPressed: () {
                                      setState(() {
                                        selectedFolders.removeAt(index);
                                      });
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                ElevatedButton(
                  onPressed: () {
                    // 更新播放列表的文件夹路径
                    notifier.updatePlaylistFolders(index, selectedFolders);
                    Navigator.of(context).pop();
                  },
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class PlaylistTileWidget extends StatefulWidget {
  final int index;
  final String name;
  final bool isDefault;
  final bool isSelected;
  final void Function(Offset position) onSecondaryTap;
  final bool isFolderBased;

  const PlaylistTileWidget({
    super.key,
    required this.index,
    required this.name,
    required this.isDefault,
    required this.isSelected,
    required this.onSecondaryTap,
    this.isFolderBased = false,
  });

  @override
  State<PlaylistTileWidget> createState() => _PlaylistTileWidgetState();
}

class _PlaylistTileWidgetState extends State<PlaylistTileWidget> {
  bool _isHovered = false; // 在内部管理自己的悬停状态

  @override
  Widget build(BuildContext context) {
    final notifier = context.read<PlaylistContentNotifier>();
    final colorScheme = Theme.of(context).colorScheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: Material(
        color: widget.isSelected
            ? colorScheme.primary.withValues(alpha: 0.1)
            : _isHovered
            ? Colors.grey.withValues(alpha: 0.1)
            : Colors.transparent,
        child: InkWell(
          onTap: () => notifier.setSelectedIndex(widget.index),
          onSecondaryTapDown: (details) {
            widget.onSecondaryTap(details.globalPosition);
          },
          child: ListTile(
            title: Row(
              children: [
                Expanded(
                  child: AnimatedScale(
                    duration: const Duration(milliseconds: 200),
                    scale: widget.isSelected ? 1.05 : 1.0,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      widget.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: widget.isSelected ? colorScheme.primary : null,
                      ),
                    ),
                  ),
                ),
                if (widget.isFolderBased)
                  const Icon(Icons.folder, size: 16, color: Colors.grey),
              ],
            ),
            selected: widget.isSelected,
          ),
        ),
      ),
    );
  }
}

class HeadSongListWidget extends StatelessWidget {
  const HeadSongListWidget({super.key});

  void _showSortDialog(BuildContext context) async {
    final notifier = context.read<PlaylistContentNotifier>();
    // 如果没有选中歌单或歌单为空，则不显示对话框
    if (notifier.selectedIndex < 0 || notifier.currentPlaylistSongs.isEmpty) {
      notifier.postError('歌单为空或未选中，无法排序');
      return;
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const SortDialog(),
    );

    if (result != null && context.mounted) {
      await notifier.sortCurrentPlaylist(
        criterion: result['criterion'] as SortCriterion,
        descending: result['descending'] as bool,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<PlaylistContentNotifier>();
    final isSearching = notifier.isSearching;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: isSearching
                // --- 搜索状态下显示的UI ---
                ? TextField(
                    key: const ValueKey('search_field_playlist'),
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: '在当前歌单中搜索歌曲名、歌手名...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: notifier.stopSearch, // 点击关闭按钮，退出搜索
                      ),
                    ),
                    onChanged: (keyword) => notifier.search(keyword),
                  )
                // --- 正常状态下显示的UI ---
                : Selector<PlaylistContentNotifier, (String, bool, bool)>(
                    key: const ValueKey('title_bar_playlist'),
                    selector: (_, notifier) {
                      if (notifier.selectedIndex == -1 ||
                          notifier.selectedIndex >= notifier.playlists.length) {
                        return ('无选中歌单', false, notifier.isMultiSelectMode);
                      }
                      return (
                        notifier.playlists[notifier.selectedIndex].name,
                        true,
                        notifier.isMultiSelectMode,
                      );
                    },
                    builder: (context, data, _) {
                      final (
                        playlistName,
                        isPlaylistSelected,
                        isMultiSelectMode,
                      ) = data;
                      return Row(
                        children: [
                          if (isMultiSelectMode) ...[
                            Text(
                              '已选择 ${notifier.selectedSongs.length} 首歌曲',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(width: 16),
                            // 全选/取消全选按钮
                            IconButton(
                              icon: Icon(
                                notifier.selectedSongs.length ==
                                        notifier.currentPlaylistSongs.length
                                    ? Icons.deselect
                                    : Icons.select_all,
                              ),
                              tooltip:
                                  notifier.selectedSongs.length ==
                                      notifier.currentPlaylistSongs.length
                                  ? '取消全选'
                                  : '全选',
                              onPressed: () {
                                if (notifier.selectedSongs.length ==
                                    notifier.currentPlaylistSongs.length) {
                                  notifier.deselectAllSongs();
                                } else {
                                  notifier.selectAllSongs();
                                }
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.playlist_add),
                              tooltip: '添加到歌单',
                              onPressed: () =>
                                  _showAddToPlaylistDialog(context),
                            ),
                            // 只有不是基于文件夹的歌单才显示删除按钮
                            if (!notifier
                                .playlists[notifier.selectedIndex]
                                .isFolderBased)
                              IconButton(
                                icon: const Icon(Icons.delete),
                                tooltip: '删除选中歌曲',
                                onPressed: () =>
                                    _showDeleteConfirmationDialog(context),
                              ),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.close),
                              tooltip: '取消多选',
                              onPressed: notifier.exitMultiSelectMode,
                            ),
                          ] else ...[
                            Text(
                              playlistName,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(width: 16),
                            // 显示当前歌单歌曲总数
                            if (isPlaylistSelected &&
                                notifier.currentPlaylistSongs.isNotEmpty)
                              Text(
                                '共 ${notifier.currentPlaylistSongs.length} 首',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            const Spacer(),
                            if (isPlaylistSelected &&
                                !notifier
                                    .playlists[notifier.selectedIndex]
                                    .isFolderBased)
                              ElevatedButton.icon(
                                onPressed: () => context
                                    .read<PlaylistContentNotifier>()
                                    .pickAndAddSongs(),
                                icon: const Icon(Icons.add_circle_outline),
                                label: const Text('添加歌曲'),
                              ),
                            if (isPlaylistSelected)
                              IconButton(
                                icon: const Icon(Icons.sort),
                                tooltip: '排序歌曲',
                                onPressed: () => _showSortDialog(context),
                              ),
                            // 多选按钮
                            if (isPlaylistSelected)
                              IconButton(
                                icon: const Icon(Icons.check_circle_outline),
                                tooltip: '多选歌曲',
                                onPressed: notifier.enterMultiSelectMode,
                              ),
                            // 新增：搜索按钮
                            if (isPlaylistSelected)
                              IconButton(
                                icon: const Icon(Icons.search),
                                tooltip: '搜索歌曲',
                                onPressed: notifier.startSearch, // 点击触发搜索
                              ),
                            // 为基于文件夹的播放列表添加刷新按钮
                            if (isPlaylistSelected &&
                                notifier
                                    .playlists[notifier.selectedIndex]
                                    .isFolderBased)
                              IconButton(
                                icon: const Icon(Icons.refresh),
                                tooltip: '刷新文件夹内容',
                                onPressed: () =>
                                    notifier.refreshFolderPlaylist(),
                              ),
                          ],
                        ],
                      );
                    },
                  ),
          ),
          const SizedBox(height: 8),
          // 只在列表本身变化时才重建
          Expanded(
            child:
                Selector<
                  PlaylistContentNotifier,
                  (bool, List<Song>, bool, Set<String>)
                >(
                  selector: (_, notifier) {
                    // 根据是否在搜索，决定使用哪个列表
                    final listToShow = notifier.isSearching
                        ? notifier.filteredSongs
                        : notifier.currentPlaylistSongs;

                    return (
                      notifier.isLoadingSongs,
                      listToShow,
                      notifier.isMultiSelectMode,
                      notifier.selectedSongPaths,
                    );
                  },
                  // shouldRebuild: (previous, next) => previous != next,
                  // Selector 默认的比较已经足够
                  builder: (context, data, _) {
                    final (
                      isLoading,
                      songs,
                      isMultiSelectMode,
                      selectedSongPaths,
                    ) = data; // `selectedIndex` 不再需要

                    if (isLoading) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (notifier.selectedIndex == -1) {
                      return const Center(child: Text('请选择一个歌单'));
                    }
                    if (songs.isEmpty) {
                      // 根据是否在搜索显示不同的提示
                      return Center(
                        child: Text(isSearching ? '未找到匹配的歌曲' : '此歌单暂无歌曲'),
                      );
                    }

                    // 列表本身
                    return ReorderableListView.builder(
                      proxyDecorator: (child, index, animation) => Material(
                        elevation: 4,
                        borderRadius: BorderRadius.circular(12),
                        clipBehavior: Clip.antiAlias,
                        child: child,
                      ),
                      buildDefaultDragHandles: false,
                      itemCount: songs.length,
                      itemBuilder: (context, index) {
                        final song = songs[index];
                        final currentPlaylist =
                            notifier.playlists[notifier.selectedIndex];

                        // 播放和排序时，需要找到它在原始列表中的索引
                        final originalIndex = notifier.currentPlaylistSongs
                            .indexOf(song);
                        return SongTileWidget(
                          key: ValueKey(song.filePath),
                          song: song,
                          index: index,
                          contextPlaylist: currentPlaylist,
                          onTap: () {
                            if (isMultiSelectMode) {
                              notifier.toggleSongSelection(song);
                            } else {
                              if (originalIndex != -1) {
                                notifier.playSongAtIndex(
                                  originalIndex,
                                ); // 使用原始索引播放
                              }
                            }
                          },
                          enableContextMenu: !isMultiSelectMode, // 多选模式下禁用右键菜单
                        );
                      },
                      // 在搜索时禁用拖拽排序功能
                      onReorder: (oldIndex, newIndex) {
                        final isSearching = context
                            .read<PlaylistContentNotifier>()
                            .isSearching;
                        final isMultiSelectMode = context
                            .read<PlaylistContentNotifier>()
                            .isMultiSelectMode;

                        // 如果正在搜索或多选模式，则不做任何事，直接返回
                        if (isSearching || isMultiSelectMode) {
                          return;
                        }

                        // 如果不在搜索状态，UI显示的列表就是完整的 currentPlaylistSongs
                        // 此时的 oldIndex 和 newIndex 是准确的，可以直接使用
                        context.read<PlaylistContentNotifier>().reorderSong(
                          oldIndex,
                          newIndex,
                        );
                      },
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmationDialog(BuildContext context) {
    final notifier = context.read<PlaylistContentNotifier>();
    if (notifier.selectedSongs.isEmpty) {
      notifier.postInfo('未选择任何歌曲');
      return;
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('确认删除'),
          content: Text('确定要删除选中的 ${notifier.selectedSongs.length} 首歌曲吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () {
                notifier.removeSelectedSongs();
                Navigator.of(context).pop();
              },
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
  }

  void _showAddToPlaylistDialog(BuildContext context) {
    final notifier = context.read<PlaylistContentNotifier>();
    if (notifier.selectedSongs.isEmpty) {
      notifier.postInfo('未选择任何歌曲');
      return;
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('添加到歌单'),
          content: Selector<PlaylistContentNotifier, List<Playlist>>(
            selector: (context, notifier) => notifier.playlists,
            builder: (context, playlists, _) {
              final scrollController = ScrollController();
              final currentPlaylistIndex = notifier.selectedIndex;
              final currentPlaylist = currentPlaylistIndex >= 0
                  ? playlists[currentPlaylistIndex]
                  : null;

              final targetPlaylists = playlists.where((playlist) {
                // 排除当前歌单和基于文件夹的歌单
                return playlist != currentPlaylist && !playlist.isFolderBased;
              }).toList();

              if (targetPlaylists.isEmpty) {
                return const Text('没有可添加的歌单');
              }

              return Container(
                width: 300,
                constraints: const BoxConstraints(maxHeight: 300),
                child: Scrollbar(
                  controller: scrollController,
                  child: ListView.builder(
                    shrinkWrap: true,
                    controller: scrollController,
                    itemCount: targetPlaylists.length,
                    itemBuilder: (context, index) {
                      final playlist = targetPlaylists[index];
                      return ListTile(
                        title: Text(playlist.name),
                        onTap: () async {
                          // 添加歌曲到选中的歌单
                          final selectedSongs = notifier.selectedSongs;
                          final playlistIndex = playlists.indexOf(playlist);

                          if (playlistIndex != -1) {
                            await notifier.addSongsToPlaylist(
                              playlistIndex,
                              selectedSongs.map((s) => s.filePath).toList(),
                            );

                            if (context.mounted) {
                              Navigator.of(context).pop();
                              notifier.exitMultiSelectMode();
                            }
                          }
                        },
                      );
                    },
                  ),
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
          ],
        );
      },
    );
  }
}

class SongTileWidget extends StatefulWidget {
  final Song song;
  final int index;
  final VoidCallback? onTap;
  final Playlist contextPlaylist;
  // 控制右键菜单是否显示
  final bool enableContextMenu;

  const SongTileWidget({
    super.key,
    required this.song,
    required this.index,
    this.onTap,
    required this.contextPlaylist,
    this.enableContextMenu = true,
  });

  @override
  State<SongTileWidget> createState() => _SongTileWidgetState();
}

class _SongTileWidgetState extends State<SongTileWidget> {
  bool _isHovered = false;

  void _showSongContextMenu(
    Offset position,
    PlaylistContentNotifier playlistNotifier,
  ) async {
    final notifier = context.read<PlaylistContentNotifier>();

    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    // 检查是否是基于文件夹的播放列表
    final isFolderBasedPlaylist =
        notifier.playlists[notifier.selectedIndex].isFolderBased;

    final result = await showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        overlay.size.width - position.dx,
        overlay.size.height - position.dy,
      ),
      items: <PopupMenuItem<String>>[
        const PopupMenuItem<String>(value: 'moveToTop', child: Text('置于顶部')),
        // 只有非基于文件夹的播放列表才允许删除歌曲
        if (!isFolderBasedPlaylist)
          const PopupMenuItem<String>(value: 'deleteSong', child: Text('删除歌曲')),
      ],
    );

    if (!mounted || result == null) return;

    if (result == 'moveToTop') {
      final isAllSongsContext =
          widget.contextPlaylist.id == notifier.allSongsVirtualPlaylist.id;
      // 根据页面判断调用哪个方法
      if (isAllSongsContext) {
        await notifier.moveSongToTopInAllSongs(widget.index);
      } else {
        await notifier.moveSongToTop(widget.index);
      }
    } else if (result == 'deleteSong') {
      // 判断当前 widget 是在哪个上下文中
      final isAllSongsContext =
          widget.contextPlaylist.id == notifier.allSongsVirtualPlaylist.id;

      if (isAllSongsContext) {
        // 如果在全部歌曲页面，就从所有歌单中删除
        await notifier.removeSongFromAllPlaylists(
          widget.song.filePath,
          songTitle: widget.song.title,
        );
      } else {
        // 如果在具体的歌单页面，只从当前歌单删除
        // 检查是否在搜索模式下
        if (notifier.isSearching) {
          // 在搜索模式下，需要根据歌曲路径找到它在原始列表中的索引
          final actualIndex = notifier.currentPlaylistSongs.indexWhere(
            (song) => song.filePath == widget.song.filePath,
          );
          if (actualIndex != -1) {
            await notifier.removeSongFromCurrentPlaylist(actualIndex);
          }
        } else {
          // 非搜索模式下，直接使用widget.index
          await notifier.removeSongFromCurrentPlaylist(widget.index);
        }
      }

      // messenger.showSnackBar(SnackBar(content: Text('已删除歌曲：$songTitle')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final notifier = context.read<PlaylistContentNotifier>();
    final settings = context.watch<SettingsProvider>();

    // 监听多选模式和选中歌曲的变化
    final isMultiSelectMode = context.select<PlaylistContentNotifier, bool>(
      (n) => n.isMultiSelectMode,
    );
    final isSelected = context.select<PlaylistContentNotifier, bool>(
      (n) => n.selectedSongPaths.contains(widget.song.filePath),
    );

    final isPlaying = context.select<PlaylistContentNotifier, bool>((n) {
      // 条件1：播放器必须有正在播放的歌曲和上下文
      if (n.currentSong == null || n.playingPlaylist == null) {
        return false;
      }

      // 条件2：正在播放的歌曲，必须是当前这个 SongTileWidget 代表的歌曲 (通过路径判断)
      final bool isThisSong = n.currentSong!.filePath == widget.song.filePath;

      // 条件3：正在播放的歌曲的上下文，必须和当前 SongTileWidget 所在的上下文一致 (通过ID判断)
      final bool isThisContext =
          n.playingPlaylist!.id == widget.contextPlaylist.id;

      // 必须同时满足歌曲匹配和上下文匹配
      return isThisSong && isThisContext;
    });

    return Material(
      color: Colors.transparent,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: ReorderableDragStartListener(
          index: widget.index,
          child: InkWell(
            onTap: widget.onTap,
            onSecondaryTapDown: (details) {
              // 根据 enableContextMenu 参数决定是否显示右键菜单
              if (widget.enableContextMenu) {
                _showSongContextMenu(details.globalPosition, notifier);
              }
            },
            borderRadius: BorderRadius.circular(8),

            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                color: _isHovered
                    ? colorScheme.onSurface.withValues(alpha: 0.1)
                    : isPlaying
                    ? colorScheme.primary.withValues(alpha: 0.1)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListTile(
                leading: SizedBox(
                  width: 50,
                  height: 50,
                  child: widget.song.albumArt != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.memory(
                            widget.song.albumArt!,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                          ),
                        )
                      : const Icon(
                          Icons.music_note,
                          size: 40,
                          color: Colors.grey,
                        ),
                ),
                title: Text(
                  widget.song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  settings.showAlbumName
                      ? '${widget.song.artist} - ${widget.song.album}'
                      : widget.song.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isMultiSelectMode) ...[
                      Theme(
                        data: Theme.of(context).copyWith(
                          unselectedWidgetColor: Theme.of(
                            context,
                          ).primaryColor.withValues(alpha: 0.5),
                        ),
                        child: Checkbox(
                          value: isSelected,
                          onChanged: null, // 由onTap统一处理
                          activeColor: colorScheme.primary,
                          checkColor: Theme.of(context).colorScheme.onPrimary,
                        ),
                      ),
                    ] else ...[
                      if (widget.song.duration != null)
                        Text(
                          '${widget.song.duration!.inMinutes}:${(widget.song.duration!.inSeconds % 60).toString().padLeft(2, '0')}',
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
