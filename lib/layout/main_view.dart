import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../page/pages/play_list.dart';
import '../page/pages/setting.dart';
import '../page/pages/song_details.dart';
import '../page/pages/all_songs.dart';
import '../page/pages/album_list_page.dart';
import '../page/pages/artist_list_page.dart';

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
        return const SongDetails();
      case 5:
        return const Setting();
      default:
        return const SizedBox.shrink();
    }
  }

  final TextStyle _mainViewTextStyle = const TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
  );

  @override
  Widget build(BuildContext context) {
    final playlistNotifier = context.read<PlaylistContentNotifier>();
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isWideScreen = constraints.maxWidth >= 1000;

        final bool actualExtended;
        if (_hasUserToggled) {
          actualExtended = _isManuallyExpanded;
        } else {
          actualExtended = isWideScreen;
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
                      break;
                  }
                  setState(() {
                    _currentIndex = index;
                  });
                },
                destinations: [
                  NavigationRailDestination(
                    icon: const Icon(Icons.playlist_play),
                    selectedIcon: const Icon(Icons.playlist_play_outlined),
                    label: Text('歌单', style: _mainViewTextStyle),
                  ),
                  NavigationRailDestination(
                    icon: const Icon(Icons.queue_music),
                    selectedIcon: const Icon(Icons.queue_music_outlined),
                    label: Text('全部歌曲', style: _mainViewTextStyle),
                  ),
                  NavigationRailDestination(
                    icon: const Icon(Icons.person_outlined),
                    selectedIcon: const Icon(Icons.person),
                    label: Text('歌手', style: _mainViewTextStyle),
                  ),
                  NavigationRailDestination(
                    icon: const Icon(Icons.album_outlined),
                    selectedIcon: const Icon(Icons.album),
                    label: Text('专辑', style: _mainViewTextStyle),
                  ),
                  NavigationRailDestination(
                    icon: const Icon(Icons.library_music_outlined),
                    selectedIcon: const Icon(Icons.library_music),
                    label: Text('歌曲详情信息', style: _mainViewTextStyle),
                  ),
                  NavigationRailDestination(
                    icon: const Icon(Icons.settings_outlined),
                    selectedIcon: const Icon(Icons.settings),
                    label: Text('设置', style: _mainViewTextStyle),
                  ),
                ],
                trailing: Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 8, bottom: 16),
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
                              setState(() {
                                _isManuallyExpanded = !actualExtended;
                                _hasUserToggled = true;
                              });
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
