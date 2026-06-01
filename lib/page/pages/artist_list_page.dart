import 'package:flutter/material.dart';
import '../../page/song_list/artist_list.dart';
class ArtistListPage extends StatelessWidget {
  const ArtistListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: ArtistList(),
    );
  }
}
