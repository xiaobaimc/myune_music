import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'playlist_content_notifier.dart';
import 'playlist_models.dart';

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
}

class PlaylistTileWidget extends StatefulWidget {
  final int index;
  final String name;
  final bool isDefault;
  final bool isSelected;
  final void Function(Offset position) onSecondaryTap;

  const PlaylistTileWidget({
    super.key,
    required this.index,
    required this.name,
    required this.isDefault,
    required this.isSelected,
    required this.onSecondaryTap,
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
            title: Text(widget.name, overflow: TextOverflow.ellipsis),
            selected: widget.isSelected,
          ),
        ),
      ),
    );
  }
}

class HeadSongListWidget extends StatelessWidget {
  const HeadSongListWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 监听歌单名称和选中状态
          Selector<PlaylistContentNotifier, (String, bool)>(
            selector: (_, notifier) {
              if (notifier.selectedIndex == -1 ||
                  notifier.selectedIndex >= notifier.playlists.length) {
                return ('无选中歌单', false);
              }
              return (notifier.playlists[notifier.selectedIndex].name, true);
            },
            builder: (context, data, _) {
              final (playlistName, isPlaylistSelected) = data;
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    playlistName,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (isPlaylistSelected)
                    ElevatedButton.icon(
                      onPressed: () => context
                          .read<PlaylistContentNotifier>()
                          .pickAndAddSongs(),
                      icon: const Icon(Icons.add_circle_outline),
                      label: const Text('添加歌曲'),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          // 只在列表本身变化时才重建
          Expanded(
            child: Selector<PlaylistContentNotifier, (bool, List<Song>, int)>(
              selector: (_, notifier) => (
                notifier.isLoadingSongs,
                notifier.currentPlaylistSongs,
                notifier.selectedIndex,
              ),
              shouldRebuild: (previous, next) => previous != next,
              builder: (context, data, _) {
                final (isLoading, songs, selectedIndex) = data;

                if (isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (selectedIndex == -1) {
                  return const Center(child: Text('请选择一个歌单'));
                }
                if (songs.isEmpty) {
                  return const Center(child: Text('此歌单暂无歌曲, 点击 "添加歌曲"'));
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
                    final currentPlaylist = context
                        .read<PlaylistContentNotifier>()
                        .playlists[selectedIndex];
                    // 使用拆分出的 SongTileWidget
                    return SongTileWidget(
                      key: ValueKey(song.filePath), // Key是必须的
                      song: song,
                      index: index,
                      contextPlaylist: currentPlaylist,
                      onTap: () => context
                          .read<PlaylistContentNotifier>()
                          .playSongAtIndex(index),
                    );
                  },
                  onReorder: (oldIndex, newIndex) {
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
}

class SongTileWidget extends StatefulWidget {
  final Song song;
  final int index;
  final VoidCallback? onTap;
  final Playlist contextPlaylist;

  const SongTileWidget({
    super.key,
    required this.song,
    required this.index,
    this.onTap,
    required this.contextPlaylist,
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
    // 在异步操作前，如果需要使用 context，可以直接使用 State 的 context 属性
    if (!mounted) return;

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

    if (!mounted) return;

    if (result == 'moveToTop') {
      final songTitle =
          playlistNotifier.currentPlaylistSongs[widget.index].title;
      await playlistNotifier.moveSongToTop(widget.index);

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已将歌曲“$songTitle”置于顶部')));
    } else if (result == 'deleteSong') {
      final songTitle = playlistNotifier.currentPlaylistSongs
          .elementAt(widget.index)
          .title;
      await playlistNotifier.removeSongAtIndex(widget.index);

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已删除歌曲：$songTitle')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final notifier = context.read<PlaylistContentNotifier>();

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

      // 必须同时满足歌曲匹配和上下文匹配，并且播放器处于活动状态
      return isThisSong &&
          isThisContext &&
          (n.playerState == PlayerState.playing ||
              n.playerState == PlayerState.paused);
    });

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: ReorderableDragStartListener(
        index: widget.index,
        child: InkWell(
          onTap: widget.onTap,
          onSecondaryTapDown: (details) {
            _showSongContextMenu(details.globalPosition, notifier);
          },
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
                widget.song.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Text('${widget.index + 1}.'),
            ),
          ),
        ),
      ),
    );
  }
}
