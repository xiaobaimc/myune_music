import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../song_list/album_list.dart';
import '../setting/settings_provider.dart';
import '../../widgets/custom_background_layer.dart';

class AlbumListPage extends StatelessWidget {
  const AlbumListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return Scaffold(
      backgroundColor: CustomBackgroundSurfaces.transparentWhenEnabled(
        settings,
        Theme.of(context).colorScheme.surface,
      ),
      body: const AlbumList(),
    );
  }
}
