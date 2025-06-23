import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'playlist_content_notifier.dart';

class PlaylistContentWidget extends StatelessWidget {
  const PlaylistContentWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      color: colorScheme.surface,
      child: Row(
        children: [
          const SizedBox(width: 150, child: PlaylistListWidget()),
          VerticalDivider(
            width: 1,
            thickness: 1,
            color: colorScheme.outlineVariant,
            indent: 0,
            endIndent: 0,
          ),
          const Expanded(child: SongListWidget()),
        ],
      ),
    );
  }
}

class PlaylistListWidget extends StatefulWidget {
  const PlaylistListWidget({super.key});

  @override
  State<PlaylistListWidget> createState() => _PlaylistListWidgetState();
}

class _PlaylistListWidgetState extends State<PlaylistListWidget> {
  int _hoveredIndex = -1; // 仅用于当前组件的UI状态

  void _showAddPlaylistDialog(
    BuildContext context,
    PlaylistContentNotifier notifier,
  ) {
    showDialog(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('添加新歌单'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: '输入歌单名称'),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () {
                if (controller.text.isNotEmpty) {
                  if (!notifier.addPlaylist(controller.text.trim())) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('歌单名称已存在')));
                  }
                  Navigator.of(context).pop();
                }
              },
              child: const Text('添加'),
            ),
          ],
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
      final deleted = playlistNotifier.deletePlaylist(index);
      if (!deleted && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('默认歌单不可删除')));
      }
    } else if (result == 'edit' && index != null) {
      if (context.mounted) {
        _showEditPlaylistDialog(context, index, playlistNotifier);
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
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: '输入新的歌单名称'),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () {
                final newName = controller.text.trim();
                if (notifier.editPlaylistName(index, newName)) {
                  Navigator.of(context).pop();
                } else {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('歌单名称已存在或为空')));
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
    final colorScheme = Theme.of(context).colorScheme;

    // 使用 Consumer 来监听 PlaylistContentNotifier 的变化
    return Consumer<PlaylistContentNotifier>(
      builder: (context, playlistNotifier, child) {
        return Column(
          children: [
            Container(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: () =>
                        _showAddPlaylistDialog(context, playlistNotifier),
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text('添加歌单'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: GestureDetector(
                onSecondaryTapDown: (details) {
                  _showContextMenu(details.globalPosition, null, context);
                },
                child: ListView.builder(
                  itemCount: playlistNotifier.playlists.length,
                  itemBuilder: (context, index) {
                    final isSelected = playlistNotifier.selectedIndex == index;
                    return MouseRegion(
                      cursor: SystemMouseCursors.click,
                      onEnter: (_) => setState(() => _hoveredIndex = index),
                      onExit: (_) => setState(() => _hoveredIndex = -1),
                      child: Material(
                        color: isSelected
                            ? colorScheme.primary.withValues(alpha: 0.1)
                            : (_hoveredIndex == index
                                  ? Colors.grey.withValues(alpha: 0.1)
                                  : Colors.transparent),
                        child: InkWell(
                          onTap: () => playlistNotifier.setSelectedIndex(index),
                          onSecondaryTapDown: (details) => _showContextMenu(
                            details.globalPosition,
                            index,
                            context,
                          ),
                          child: ListTile(
                            title: Text(playlistNotifier.playlists[index].name),
                            selected: isSelected,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class SongListWidget extends StatefulWidget {
  const SongListWidget({super.key});

  @override
  State<SongListWidget> createState() => _SongListWidgetState();
}

class _SongListWidgetState extends State<SongListWidget> {
  int _hoveredIndex = -1;

  @override
  void initState() {
    super.initState();
    final playlistNotifier = Provider.of<PlaylistContentNotifier>(
      context,
      listen: false,
    );
    playlistNotifier.errorStream.listen((errorMessage) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage)));
      }
    });
  }

  void _showSongContextMenu(
    Offset position,
    int songIndex,
    BuildContext context,
    PlaylistContentNotifier playlistNotifier,
  ) async {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

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
        const PopupMenuItem<String>(value: 'deleteSong', child: Text('删除歌曲')),
      ],
    );
    if (result == 'moveToTop') {
      final songTitle = playlistNotifier.currentPlaylistSongs[songIndex].title;
      await playlistNotifier.moveSongToTop(songIndex);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已将歌曲“$songTitle”置于顶部')));
      }
    } else if (result == 'deleteSong') {
      final songTitle = playlistNotifier.currentPlaylistSongs
          .elementAt(songIndex)
          .title;
      await playlistNotifier.removeSongAtIndex(songIndex);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已删除歌曲：$songTitle')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Consumer<PlaylistContentNotifier>(
      builder: (context, playlistNotifier, child) {
        final currentPlaylistName = playlistNotifier.selectedIndex != -1
            ? playlistNotifier.playlists.length > playlistNotifier.selectedIndex
                  ? playlistNotifier.playlists
                        .elementAt(playlistNotifier.selectedIndex)
                        .name
                  : '歌单数据错误'
            : '无选中歌单';

        return Container(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    currentPlaylistName,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (playlistNotifier.selectedIndex != -1 &&
                      playlistNotifier.playlists.isNotEmpty &&
                      playlistNotifier.selectedIndex <
                          playlistNotifier.playlists.length)
                    ElevatedButton.icon(
                      onPressed: () async {
                        try {
                          final added = await playlistNotifier
                              .pickAndAddSongs();
                          if (!context.mounted) return;

                          if (added) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('添加成功')),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('未添加任何新歌曲')),
                            );
                          }
                        } catch (e) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('添加失败：${e.toString()}')),
                          );
                        }
                      },
                      icon: const Icon(Icons.add_circle_outline),
                      label: const Text('添加歌曲'),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: playlistNotifier.isLoadingSongs
                    ? const Center(child: CircularProgressIndicator())
                    : playlistNotifier.selectedIndex == -1 ||
                          playlistNotifier.playlists.isEmpty ||
                          playlistNotifier.selectedIndex >=
                              playlistNotifier.playlists.length
                    ? Center(
                        child: Text(
                          '请选择一个歌单或右键添加新歌单',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: colorScheme.onSurface.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                        ),
                      )
                    : playlistNotifier.currentPlaylistSongs.isEmpty
                    ? Center(
                        child: Text(
                          '此歌单暂无歌曲，点击“添加歌曲”按钮添加',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: colorScheme.onSurface.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                        ),
                      )
                    : ReorderableListView.builder(
                        proxyDecorator: (child, index, animation) {
                          return Material(
                            elevation: 4,
                            borderRadius: BorderRadius.circular(12),
                            clipBehavior: Clip.antiAlias,
                            child: child,
                          );
                        },
                        buildDefaultDragHandles: false,
                        itemCount: playlistNotifier.currentPlaylistSongs.length,
                        itemBuilder: (context, index) {
                          final song = playlistNotifier.currentPlaylistSongs
                              .elementAt(index);
                          // 检查当前歌曲是否是正在播放或暂停的歌曲，并且播放器处于播放中或暂停状态
                          final isPlaying =
                              playlistNotifier.currentSongIndex == index &&
                              (playlistNotifier.playerState ==
                                      PlayerState.playing ||
                                  playlistNotifier.playerState ==
                                      PlayerState.paused);
                          return MouseRegion(
                            key: ValueKey(song.filePath), // 确保每个项有唯一键
                            onEnter: (_) =>
                                setState(() => _hoveredIndex = index),
                            onExit: (_) => setState(() => _hoveredIndex = -1),
                            child: ReorderableDragStartListener(
                              index: index,
                              child: InkWell(
                                onTap: () {
                                  playlistNotifier.playSongAtIndex(index);
                                },
                                onSecondaryTapDown: (details) {
                                  _showSongContextMenu(
                                    details.globalPosition,
                                    index,
                                    context,
                                    playlistNotifier,
                                  );
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 100),
                                  curve: Curves.easeInOut,
                                  decoration: BoxDecoration(
                                    color: _hoveredIndex == index
                                        ? Colors.grey.withValues(alpha: 0.2)
                                        : isPlaying
                                        ? colorScheme.primary.withValues(
                                            alpha: 0.1,
                                          )
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: ListTile(
                                    leading: SizedBox(
                                      width: 50,
                                      height: 50,
                                      child: song.albumArt != null
                                          ? ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              child: Image.memory(
                                                song.albumArt!,
                                                fit: BoxFit.cover,
                                                width: 50,
                                                height: 50,
                                                errorBuilder:
                                                    (
                                                      context,
                                                      error,
                                                      stackTrace,
                                                    ) {
                                                      return const Icon(
                                                        Icons.music_note,
                                                        size: 40,
                                                        color: Colors.grey,
                                                      );
                                                    },
                                              ),
                                            )
                                          : const Icon(
                                              Icons.music_note,
                                              size: 40,
                                              color: Colors.grey,
                                            ),
                                    ),
                                    title: Text(
                                      song.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      song.artist,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: Text('${index + 1}.'),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                        onReorder: (oldIndex, newIndex) {
                          playlistNotifier.reorderSong(oldIndex, newIndex);
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
