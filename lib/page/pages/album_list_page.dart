import 'package:flutter/material.dart';
import '../song_list/album_list.dart';
class AlbumListPage extends StatelessWidget {
  const AlbumListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: AlbumList(),
    );
  }
}
