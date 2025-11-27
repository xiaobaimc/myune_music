import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../page/pages/play_list.dart';
import '../page/pages/setting.dart';
import '../page/pages/song_details.dart';
import '../page/pages/all_songs.dart';
import '../page/pages/album_list_page.dart';
import '../page/pages/artist_list_page.dart';
import '../page/pages/statistics_page.dart';

import '../page/playlist/playlist_content_notifier.dart';

class MainView extends StatefulWidget {
  const MainView({super.key});

  @override
  State<MainView> createState() => _MainViewState();
}

class _MainViewState extends State<MainView> {
  int _currentIndex = 0;
  bool _isManuallyExpanded = false;
  bool _hasUserToggled = false;
  bool _isExpanded = true;

  final int _tappedIndex = -1;

  Widget _buildPage(int index) {
    switch (index) {
      case 0:
        return const Playlist();
      case 1:
        return const AllSongs();
      case 2:
        return const ArtistListPage();
      case 3:
        return const AlbumListPage();
      case 4:
        return const StatisticsPage();
      case 5:
        return const SongDetails();
      case 6:
        return const Setting();
      default:
        return const SizedBox.shrink();
    }
  }

  final TextStyle _mainViewTextStyle = const TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
  );

  // 加载保存的展开状态
  Future<void> _loadExpandedState() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isExpanded = prefs.getBool('isNavigationRailExpanded') ?? true;
      // 如果从未手动切换过，则使用保存的状态
      if (!_hasUserToggled) {
        _isManuallyExpanded = _isExpanded;
      }
    });
  }

  // 保存展开状态
  Future<void> _saveExpandedState(bool isExpanded) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isNavigationRailExpanded', isExpanded);
  }

  @override
  void initState() {
    super.initState();
    _loadExpandedState();
  }

  @override
  Widget build(BuildContext context) {
    final playlistNotifier = context.read<PlaylistContentNotifier>();
    return LayoutBuilder(
      builder: (context, constraints) {
        // final bool isWideScreen = constraints.maxWidth >= 1000;
        final aspectRatio = MediaQuery.of(context).size.aspectRatio;
        final bool isPortrait = aspectRatio <= 1.0; // 竖屏判断

        final bool actualExtended;
        if (_hasUserToggled) {
          // 即使手动点击过折叠按钮，在竖屏状态下也要保持折叠
          actualExtended = isPortrait ? false : _isManuallyExpanded;
        } else {
          // 在竖屏状态下始终折叠，否则根据保存的状态决定
          actualExtended = isPortrait ? false : _isExpanded;
        }
        return Row(
          children: [
            SafeArea(
              child: NavigationRail(
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest,
                extended: actualExtended,
                selectedIndex: _currentIndex,
                onDestinationSelected: (int index) {
                  switch (index) {
                    case 0:
                      playlistNotifier.clearActiveDetailView();
                      break;
                    case 1:
                      playlistNotifier.setActiveAllSongsView();
                      break;
                  }
                  setState(() {
                    _currentIndex = index;
                  });
                },
                destinations: [
                  NavigationRailDestination(
                    icon: AnimatedScale(
                      scale: _tappedIndex == 0 ? 1.1 : 1.0,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeInOut,
                      child: Tooltip(
                        message: '歌单',
                        child: Icon(
                          Icons.playlist_play,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    selectedIcon: AnimatedScale(
                      scale: _currentIndex == 0 ? 1.1 : 1.0,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeInOut,
                      child: Icon(
                        Icons.playlist_play_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    label: Text('歌单', style: _mainViewTextStyle),
                  ),
                  NavigationRailDestination(
                    icon: AnimatedScale(
                      scale: _tappedIndex == 1 ? 1.1 : 1.0,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeInOut,
                      child: Tooltip(
                        message: '全部歌曲',
                        child: Icon(
                          Icons.queue_music,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    selectedIcon: AnimatedScale(
                      scale: _currentIndex == 1 ? 1.1 : 1.0,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeInOut,
                      child: Icon(
                        Icons.queue_music_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    label: Text('全部歌曲', style: _mainViewTextStyle),
                  ),
                  NavigationRailDestination(
                    icon: AnimatedScale(
                      scale: _tappedIndex == 2 ? 1.1 : 1.0,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeInOut,
                      child: Tooltip(
                        message: '歌手',
                        child: Icon(
                          Icons.person_outlined,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    selectedIcon: AnimatedScale(
                      scale: _currentIndex == 2 ? 1.1 : 1.0,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeInOut,
                      child: Icon(
                        Icons.person,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    label: Text('歌手', style: _mainViewTextStyle),
                  ),
                  NavigationRailDestination(
                    icon: AnimatedScale(
                      scale: _tappedIndex == 3 ? 1.1 : 1.0,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeInOut,
                      child: Tooltip(
                        message: '专辑',
                        child: Icon(
                          Icons.album_outlined,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    selectedIcon: AnimatedScale(
                      scale: _currentIndex == 3 ? 1.1 : 1.0,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeInOut,
                      child: Icon(
                        Icons.album,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    label: Text('专辑', style: _mainViewTextStyle),
                  ),
                  NavigationRailDestination(
                    icon: AnimatedScale(
                      scale: _tappedIndex == 3 ? 1.1 : 1.0,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeInOut,
                      child: Tooltip(
                        message: '统计',
                        child: Icon(
                          Icons.leaderboard_outlined,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    selectedIcon: AnimatedScale(
                      scale: _currentIndex == 3 ? 1.1 : 1.0,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeInOut,
                      child: Icon(
                        Icons.leaderboard,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    label: Text('统计', style: _mainViewTextStyle),
                  ),
                  NavigationRailDestination(
                    icon: AnimatedScale(
                      scale: _tappedIndex == 4 ? 1.1 : 1.0,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeInOut,
                      child: Tooltip(
                        message: '歌曲详情信息',
                        child: Icon(
                          Icons.library_music_outlined,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    selectedIcon: AnimatedScale(
                      scale: _currentIndex == 4 ? 1.1 : 1.0,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeInOut,
                      child: Icon(
                        Icons.library_music,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    label: Text('歌曲详情信息', style: _mainViewTextStyle),
                  ),
                  NavigationRailDestination(
                    icon: AnimatedScale(
                      scale: _tappedIndex == 5 ? 1.1 : 1.0,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeInOut,
                      child: Tooltip(
                        message: '设置',
                        child: Icon(
                          Icons.settings_outlined,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    selectedIcon: AnimatedScale(
                      scale: _currentIndex == 5 ? 1.1 : 1.0,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeInOut,
                      child: Icon(
                        Icons.settings,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    label: Text('设置', style: _mainViewTextStyle),
                  ),
                ],
                // 在竖屏状态下隐藏折叠按钮
                trailing: isPortrait
                    ? null
                    : Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(
                                left: 8,
                                bottom: 16,
                              ),
                              child: CircleAvatar(
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.1),
                                child: IconButton(
                                  icon: Icon(
                                    actualExtended
                                        ? Icons.arrow_back_ios_new
                                        : Icons.arrow_forward_ios,
                                  ),
                                  onPressed: () {
                                    final newState = !actualExtended;
                                    setState(() {
                                      _isManuallyExpanded = newState;
                                      _hasUserToggled = true;
                                    });
                                    // 保存状态
                                    _saveExpandedState(newState);
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
            Expanded(
              child: _buildPage(_currentIndex), // 动态展示页面
            ),
          ],
        );
      },
    );
  }
}
