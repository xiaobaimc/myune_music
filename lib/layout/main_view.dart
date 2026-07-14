import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../page/pages/play_list.dart';
import '../page/pages/setting.dart';
import '../page/pages/song_details.dart';
import '../page/pages/all_songs.dart';
import '../page/pages/album_list_page.dart';
import '../page/pages/artist_list_page.dart';
import '../page/pages/statistics_page.dart';
import '../page/pages/audio_analysis_page.dart';

import '../page/playlist/playlist_content_notifier.dart';
import '../page/setting/settings_provider.dart';
import 'navigation_notifier.dart';

class PageEntry {
  final bool Function(String label, Set<String> hiddenPages) visible; // 是否显示
  final String label;
  final String routeName;
  final IconData icon;
  final IconData selectedIcon;
  final Widget page;

  PageEntry({
    required this.visible,
    required this.label,
    required this.routeName,
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
        routeName: '/playlist',
        icon: Icons.playlist_play,
        selectedIcon: Icons.playlist_play_outlined,
        page: const Playlist(),
      ),
      PageEntry(
        visible: (label, hiddenPages) => !hiddenPages.contains(label),
        label: '全部歌曲',
        routeName: '/all_songs',
        icon: Icons.queue_music,
        selectedIcon: Icons.queue_music_outlined,
        page: const AllSongs(),
      ),
      PageEntry(
        visible: (label, hiddenPages) => !hiddenPages.contains(label),
        label: '歌手',
        routeName: '/artists',
        icon: Icons.person_outlined,
        selectedIcon: Icons.person,
        page: const ArtistListPage(),
      ),
      PageEntry(
        visible: (label, hiddenPages) => !hiddenPages.contains(label),
        label: '专辑',
        routeName: '/albums',
        icon: Icons.album_outlined,
        selectedIcon: Icons.album,
        page: const AlbumListPage(),
      ),
      PageEntry(
        visible: (label, hiddenPages) => !hiddenPages.contains(label),
        label: '统计',
        routeName: '/statistics',
        icon: Icons.leaderboard_outlined,
        selectedIcon: Icons.leaderboard,
        page: const StatisticsPage(),
      ),
      PageEntry(
        visible: (label, hiddenPages) => !hiddenPages.contains(label),
        label: '歌曲详情信息',
        routeName: '/song_details',
        icon: Icons.library_music_outlined,
        selectedIcon: Icons.library_music,
        page: const SongDetails(),
      ),
      PageEntry(
        visible: (label, hiddenPages) => !hiddenPages.contains(label),
        label: '音频分析',
        routeName: '/audio_analysis',
        icon: Icons.graphic_eq_outlined,
        selectedIcon: Icons.graphic_eq,
        page: const AudioAnalysisPage(),
      ),
      PageEntry(
        visible: (label, hiddenPages) => true, // 设置始终显示
        label: '设置',
        routeName: '/settings',
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings,
        page: const Setting(),
      ),
    ];
  }

  NavigationRailDestination _buildDest(
    PageEntry entry,
    int index,
    int currentIndex,
  ) {
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
          scale: currentIndex == index ? 1.1 : 1.0,
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
    final navigationNotifier = context.watch<NavigationNotifier>();
    final hiddenPages = settings.hiddenPages.toSet();

    final visibleEntries = _entries
        .where((e) => e.visible(e.label, hiddenPages))
        .toList();

    int currentIndex = visibleEntries.indexWhere(
      (e) => e.routeName == navigationNotifier.currentRoute,
    );
    if (currentIndex == -1) {
      currentIndex = 0;
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
                selectedIndex: currentIndex,
                onDestinationSelected: (int index) {
                  switch (visibleEntries[index].page) {
                    case Playlist _:
                      playlistNotifier.clearActiveDetailView();
                      break;
                    case AllSongs _:
                      playlistNotifier.setActiveAllSongsView();
                      break;
                    case SongDetails _:
                      playlistNotifier.clearViewingSong();
                      break;
                  }

                  if (currentIndex == index) return;

                  navigationNotifier.navigateTo(
                    visibleEntries[index].routeName,
                  );
                },
                destinations: [
                  for (int i = 0; i < visibleEntries.length; i++)
                    _buildDest(visibleEntries[i], i, currentIndex),
                ],
              ),
            ),
            Expanded(
              child: visibleEntries.isNotEmpty
                  ? Navigator(
                      key: navigationNotifier.navigatorKey,
                      // initialRoute: visibleEntries[_currentIndex].routeName,
                      onGenerateRoute: (settings) {
                        // 查找与路由匹配的条目
                        final entry = visibleEntries.firstWhere(
                          (e) => e.routeName == settings.name,
                          orElse: () => visibleEntries.first,
                        );

                        return PageRouteBuilder(
                          pageBuilder:
                              (context, animation, secondaryAnimation) =>
                                  entry.page,
                          transitionDuration: const Duration(milliseconds: 150),
                          reverseTransitionDuration: const Duration(
                            milliseconds: 150,
                          ),
                          transitionsBuilder:
                              (context, animation, secondaryAnimation, child) {
                                final curvedAnimation = CurvedAnimation(
                                  parent: animation,
                                  curve: Curves.easeInOut,
                                  reverseCurve: Curves.easeInOut,
                                );

                                return FadeTransition(
                                  opacity: curvedAnimation,
                                  child: child,
                                );
                              },
                        );
                      },
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        );
      },
    );
  }
}
