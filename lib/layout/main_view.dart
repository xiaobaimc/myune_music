import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../page/pages/play_list.dart';
import '../page/pages/setting.dart';
import '../page/pages/song_details.dart';
import '../page/pages/all_songs.dart';
import '../page/pages/album_list_page.dart';
import '../page/pages/artist_list_page.dart';
import '../page/pages/statistics_page.dart';

import '../page/playlist/playlist_content_notifier.dart';
import '../page/setting/settings_provider.dart';

class PageEntry {
  final bool Function(String label, Set<String> hiddenPages) visible; // 是否显示
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget page;

  PageEntry({
    required this.visible,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.page,
  });
}

class MainView extends StatefulWidget {
  const MainView({super.key});

  @override
  State<MainView> createState() => _MainViewState();
}

class _MainViewState extends State<MainView> {
  int _currentIndex = 0;

  final int _tappedIndex = -1;

  late final List<PageEntry> _entries;

  final TextStyle _mainViewTextStyle = const TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
  );

  @override
  void initState() {
    super.initState();

    _entries = [
      PageEntry(
        visible: (label, hiddenPages) => true, // 歌单始终显示
        label: '歌单',
        icon: Icons.playlist_play,
        selectedIcon: Icons.playlist_play_outlined,
        page: const Playlist(),
      ),
      PageEntry(
        visible: (label, hiddenPages) => !hiddenPages.contains(label),
        label: '全部歌曲',
        icon: Icons.queue_music,
        selectedIcon: Icons.queue_music_outlined,
        page: const AllSongs(),
      ),
      PageEntry(
        visible: (label, hiddenPages) => !hiddenPages.contains(label),
        label: '歌手',
        icon: Icons.person_outlined,
        selectedIcon: Icons.person,
        page: const ArtistListPage(),
      ),
      PageEntry(
        visible: (label, hiddenPages) => !hiddenPages.contains(label),
        label: '专辑',
        icon: Icons.album_outlined,
        selectedIcon: Icons.album,
        page: const AlbumListPage(),
      ),
      PageEntry(
        visible: (label, hiddenPages) => !hiddenPages.contains(label),
        label: '统计',
        icon: Icons.leaderboard_outlined,
        selectedIcon: Icons.leaderboard,
        page: const StatisticsPage(),
      ),
      PageEntry(
        visible: (label, hiddenPages) => !hiddenPages.contains(label),
        label: '歌曲详情信息',
        icon: Icons.library_music_outlined,
        selectedIcon: Icons.library_music,
        page: const SongDetails(),
      ),
      PageEntry(
        visible: (label, hiddenPages) => true, // 设置始终显示
        label: '设置',
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings,
        page: const Setting(),
      ),
    ];
  }

  NavigationRailDestination _buildDest(PageEntry entry, int index) {
    return NavigationRailDestination(
      icon: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedScale(
          scale: _tappedIndex == index ? 1.1 : 1.0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeInOut,
          child: Tooltip(
            message: entry.label,
            child: Icon(
              entry.icon,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
      selectedIcon: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedScale(
          scale: _currentIndex == index ? 1.1 : 1.0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeInOut,
          child: Icon(
            entry.selectedIcon,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
      label: Text(entry.label, style: _mainViewTextStyle),
    );
  }

  @override
  Widget build(BuildContext context) {
    final playlistNotifier = context.read<PlaylistContentNotifier>();
    final settings = context.watch<SettingsProvider>();
    final hiddenPages = settings.hiddenPages.toSet();

    final visibleEntries = _entries
        .where((e) => e.visible(e.label, hiddenPages))
        .toList();

    // 确保当前索引不超过可见项的数量
    if (_currentIndex >= visibleEntries.length && visibleEntries.isNotEmpty) {
      _currentIndex = visibleEntries.length - 1;
    } else if (visibleEntries.isEmpty) {
      _currentIndex = 0;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return Row(
          children: [
            SafeArea(
              child: NavigationRail(
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest,
                extended: false,
                selectedIndex: _currentIndex,
                onDestinationSelected: (int index) {
                  switch (visibleEntries[index].page.runtimeType) {
                    case Playlist _:
                      playlistNotifier.clearActiveDetailView();
                      break;
                    case AllSongs _:
                      playlistNotifier.setActiveAllSongsView();
                      break;
                  }
                  setState(() {
                    _currentIndex = index;
                  });
                },
                destinations: [
                  for (int i = 0; i < visibleEntries.length; i++)
                    _buildDest(visibleEntries[i], i),
                ],
              ),
            ),
            Expanded(
              child: visibleEntries.isNotEmpty
                  ? visibleEntries[_currentIndex].page
                  : const SizedBox.shrink(),
            ),
          ],
        );
      },
    );
  }
}
