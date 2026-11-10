import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../page/playlist/playlist_content_notifier.dart';
import '../../page/playlist/playlist_models.dart';
import '../../services/network/network_media_service.dart';
import '../../services/network/remote_entry.dart';
import '../../services/network/remote_source.dart';
import '../../services/network/remote_stream.dart';
import '../../services/notification_service.dart';
import '../setting/settings_provider.dart';
import '../../widgets/custom_background_layer.dart';
import 'network_source_editor.dart';

/// 「网络媒体」页：WebDAV / FTP 网络驱动器的浏览与播放入口。
///
/// 设计要点：
///   * 左侧管理网络源（添加 / 编辑 / 删除 / 测试连接），右侧浏览目录；
///   * 列表**只显示文件夹与音频文件**，网盘里的视频、图片、文档不会混进来；
///   * 支持「播放全部音频」「全部加入播放队列」以及「递归扫描整棵子树」，
///     一次把多层目录里的音乐加进队列，不用逐首点；
///   * 全程按需拉流、不落盘，本地磁盘不会被网盘曲库占满。
class NetworkMediaPage extends StatefulWidget {
  const NetworkMediaPage({super.key});

  @override
  State<NetworkMediaPage> createState() => _NetworkMediaPageState();
}

class _NetworkMediaPageState extends State<NetworkMediaPage>
    with AutomaticKeepAliveClientMixin {
  List<RemoteSource> _sources = <RemoteSource>[];
  RemoteSource? _active;
  String? _selectedSourceId;
  String _currentPath = '';
  final List<String> _history = <String>[];
  List<RemoteEntry> _entries = <RemoteEntry>[];
  String? _artworkUrl;
  bool _loading = false;
  String? _error;
  bool _enqueueMode = false;
  String _filter = '';
  final TextEditingController _filterController = TextEditingController();

  bool _scanning = false;
  bool _cancelScan = false;
  int _scanFound = 0;
  int _scanDirs = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _sources = RemoteSourceStore.instance.sources;
  }

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  NotificationService get _notification => context.read<NotificationService>();

  // --- 网络源管理 ---

  void _refreshSources() {
    setState(() {
      _sources = RemoteSourceStore.instance.sources;
      if (_active != null && !_sources.any((s) => s.id == _active!.id)) {
        _active = null;
        _selectedSourceId = null;
        _entries = <RemoteEntry>[];
        _artworkUrl = null;
        _error = null;
        _history.clear();
      }
    });
  }

  Future<void> _addSource() async {
    final source = await showRemoteSourceEditor(context);
    if (source == null) return;
    await RemoteSourceStore.instance.upsert(source);
    _refreshSources();
    _notification.info('已保存「${source.name}」，选中后即可开始浏览');
  }

  Future<void> _editSource() async {
    final target = _active ?? _sourceById(_selectedSourceId);
    if (target == null) {
      _notification.error('请先选择一个网络源');
      return;
    }
    final updated = await showRemoteSourceEditor(context, existing: target);
    if (updated == null) return;
    await RemoteSourceStore.instance.upsert(updated);
    _refreshSources();
    if (_active != null && _active!.id == updated.id) {
      setState(() {
        _active = updated;
        _history.clear();
        _currentPath = NetworkMediaService.rootOf(updated);
      });
      await _loadDirectory();
    }
    _notification.info('已更新「${updated.name}」');
  }

  Future<void> _deleteSource() async {
    final target = _active ?? _sourceById(_selectedSourceId);
    if (target == null) {
      _notification.error('请先选择一个网络源');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除网络源'),
        content: Text(
          '确定删除「${target.name}」吗？\n'
          '播放队列里来自该源的歌曲将无法继续播放。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await RemoteSourceStore.instance.remove(target.id);
    setState(() {
      if (_active?.id == target.id) {
        _active = null;
        _entries = <RemoteEntry>[];
        _artworkUrl = null;
        _error = null;
        _history.clear();
      }
      _selectedSourceId = null;
    });
    _refreshSources();
    _notification.info('已删除「${target.name}」');
  }

  RemoteSource? _sourceById(String? id) {
    if (id == null) return null;
    for (final source in _sources) {
      if (source.id == id) return source;
    }
    return null;
  }

  // --- 目录浏览 ---

  Future<void> _openSource(RemoteSource source) async {
    setState(() {
      _active = source;
      _selectedSourceId = source.id;
      _history.clear();
      _filter = '';
      _filterController.clear();
      _currentPath = NetworkMediaService.rootOf(source);
      _artworkUrl = null;
      _error = null;
    });
    await _loadDirectory();
  }

  Future<void> _loadDirectory() async {
    final source = _active;
    if (source == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await NetworkMediaService.listDirectory(
        source,
        _currentPath,
      );
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _artworkUrl = NetworkMediaService.directoryArtworkUrl(source, entries);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _entries = <RemoteEntry>[];
        _artworkUrl = null;
        _loading = false;
        _error = '$error';
      });
    }
  }

  Future<void> _goUp() async {
    if (_history.isEmpty) {
      setState(() {
        _active = null;
        _entries = <RemoteEntry>[];
        _artworkUrl = null;
        _error = null;
        _filter = '';
        _filterController.clear();
      });
      return;
    }
    setState(() => _currentPath = _history.removeLast());
    await _loadDirectory();
  }

  void _openEntry(RemoteEntry entry) {
    if (entry.isDirectory) {
      setState(() {
        _history.add(_currentPath);
        _currentPath = entry.path;
        _filter = '';
        _filterController.clear();
      });
      _loadDirectory();
      return;
    }
    if (entry.isPlayableMedia) {
      _playEntry(entry);
    } else {
      _notification.error('「${entry.name}」不是支持的音频格式');
    }
  }

  /// 列表只显示目录与音频，不混入视频 / 图片 / 文档。
  List<RemoteEntry> get _visibleEntries {
    final keyword = _filter.trim().toLowerCase();
    return _entries.where((entry) {
      if (!entry.isDirectory && !entry.isAudio) return false;
      if (keyword.isEmpty) return true;
      return entry.name.toLowerCase().contains(keyword);
    }).toList(growable: false);
  }

  List<RemoteEntry> get _audioEntries =>
      _entries.where((entry) => entry.isAudio).toList(growable: false);

  /// 「播放全部媒体」时包含视频容器（mpv 无视频输出时只出声）。
  List<RemoteEntry> get _playableEntries =>
      _entries.where((entry) => entry.isPlayableMedia).toList(growable: false);

  String get _albumLabel {
    final source = _active;
    if (source == null) return '网络媒体';
    final dir = remoteEntryName(_currentPath, isDirectory: true);
    return dir.isEmpty || dir == '目录' ? source.name : '${source.name} · $dir';
  }

  Song _songOf(RemoteEntry entry, {String? album}) {
    return NetworkMediaService.nasSong(
      source: _active!,
      entry: entry,
      album: album ?? _albumLabel,
      artworkUrl: _artworkUrl,
    );
  }

  Future<bool> _ensureProxy() async {
    if (await NetworkMediaService.ensureProxy()) return true;
    _notification.error('本机流代理未启动（端口 18765-18774 可能被占用），请重启应用后再试');
    return false;
  }

  Future<void> _playEntry(RemoteEntry entry) async {
    if (_active == null) return;
    if (!await _ensureProxy()) return;
    final playable = _playableEntries;
    final index = playable.indexWhere((item) => item.path == entry.path);
    if (index < 0) return;
    final songs = playable.map((item) => _songOf(item)).toList();
    await _dispatch(songs, index);
  }

  Future<void> _playAll({required bool includeVideo}) async {
    if (_active == null) return;
    final entries = includeVideo ? _playableEntries : _audioEntries;
    if (entries.isEmpty) {
      _notification.error('当前目录没有可播放的音频文件');
      return;
    }
    if (!await _ensureProxy()) return;
    final songs = entries.map((item) => _songOf(item)).toList();
    await _dispatch(songs, 0);
  }

  Future<void> _addAllToQueue() async {
    if (_active == null) return;
    if (_audioEntries.isEmpty) {
      _notification.error('当前目录没有可加入队列的音频文件');
      return;
    }
    if (!await _ensureProxy()) return;
    if (!mounted) return;
    final songs = _audioEntries.map((item) => _songOf(item)).toList();
    await context.read<PlaylistContentNotifier>().addSongsToPlayingQueue(songs);
  }

  /// 列表行内的「加入队列」按钮。抽成方法，避免在 builder 闭包里
  /// 跨 await 使用与 State 无关的 BuildContext。
  Future<void> _enqueueEntry(RemoteEntry entry) async {
    if (!await _ensureProxy()) return;
    if (!mounted) return;
    final song = _songOf(entry);
    await context.read<PlaylistContentNotifier>().addSongsToPlayingQueue(
      <Song>[song],
    );
  }

  Future<void> _dispatch(
    List<Song> songs,
    int index, {
    bool? enqueue,
  }) async {
    if (songs.isEmpty) return;
    final notifier = context.read<PlaylistContentNotifier>();
    final toQueue = enqueue ?? _enqueueMode;
    if (toQueue) {
      await notifier.addSongsToPlayingQueue(songs);
    } else {
      await notifier.playFromDynamicList(songs, index);
    }
  }

  /// 递归扫描当前目录下所有子目录里的音频，一次性播放或加入队列。
  Future<void> _scanAndDispatch({required bool enqueue}) async {
    final source = _active;
    if (source == null) return;
    if (!await _ensureProxy()) return;
    setState(() {
      _scanning = true;
      _cancelScan = false;
      _scanFound = 0;
      _scanDirs = 0;
    });
    RemoteScanResult? scan;
    try {
      scan = await NetworkMediaService.scanDirectory(
        source,
        _currentPath,
        onProgress: (found, dirs) {
          if (!mounted) return;
          setState(() {
            _scanFound = found;
            _scanDirs = dirs;
          });
        },
        isCancelled: () => _cancelScan,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _scanning = false);
      _notification.error('扫描失败：$error');
      return;
    }
    if (!mounted) return;
    setState(() => _scanning = false);
    final result = scan;

    if (result.cancelled) {
      _notification.info('已取消扫描');
      return;
    }
    if (result.entries.isEmpty) {
      _notification.error('该目录及其子目录里没有找到音频文件');
      return;
    }

    final dirLabel = remoteEntryName(_currentPath, isDirectory: true);
    final album = dirLabel.isEmpty || dirLabel == '目录'
        ? '${source.name} · 递归扫描'
        : '${source.name} · $dirLabel（含子目录）';
    final songs = result.entries
        .map((entry) => _songOf(entry, album: album))
        .toList(growable: false);
    await _dispatch(songs, 0, enqueue: enqueue);

    final buffer = StringBuffer(
      '已扫描 ${result.directories} 个目录，找到 ${result.entries.length} 首音频',
    );
    if (result.truncated) buffer.write('（已达上限，结果可能不完整）');
    buffer.write(enqueue ? '，已加入播放队列' : '，已开始播放');
    _notification.info(buffer.toString());
  }

  // --- 顶部操作 ---

  Future<void> _openMenu() async {
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        MediaQuery.sizeOf(context).width - 220,
        120,
        MediaQuery.sizeOf(context).width,
        0,
      ),
      items: <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(
          value: 'refresh',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.refresh, size: 18),
            title: Text('刷新当前目录'),
          ),
        ),
        const PopupMenuItem<String>(
          value: 'playAudio',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.play_arrow, size: 18),
            title: Text('播放全部音频'),
          ),
        ),
        const PopupMenuItem<String>(
          value: 'playMedia',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.play_circle_outline, size: 18),
            title: Text('播放全部媒体（含视频，仅出声）'),
          ),
        ),
        const PopupMenuItem<String>(
          value: 'queue',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.playlist_add, size: 18),
            title: Text('全部加入播放队列'),
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'scanPlay',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.travel_explore, size: 18),
            title: Text('递归扫描并播放'),
            subtitle: Text('含所有子目录'),
          ),
        ),
        const PopupMenuItem<String>(
          value: 'scanQueue',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.library_add_check_outlined, size: 18),
            title: Text('递归扫描并加入队列'),
            subtitle: Text('含所有子目录'),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'click',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              _enqueueMode ? Icons.playlist_add : Icons.play_circle_fill,
              size: 18,
            ),
            title: Text(_enqueueMode ? '点击行为：加入队列' : '点击行为：立即播放'),
          ),
        ),
        const PopupMenuItem<String>(
          value: 'edit',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.edit_outlined, size: 18),
            title: Text('编辑当前网络源'),
          ),
        ),
        const PopupMenuItem<String>(
          value: 'delete',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.delete_outline, size: 18),
            title: Text('删除当前网络源'),
          ),
        ),
      ],
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'refresh':
        await _loadDirectory();
        break;
      case 'playAudio':
        await _playAll(includeVideo: false);
        break;
      case 'playMedia':
        await _playAll(includeVideo: true);
        break;
      case 'queue':
        await _addAllToQueue();
        break;
      case 'scanPlay':
        await _scanAndDispatch(enqueue: false);
        break;
      case 'scanQueue':
        await _scanAndDispatch(enqueue: true);
        break;
      case 'click':
        setState(() => _enqueueMode = !_enqueueMode);
        break;
      case 'edit':
        await _editSource();
        break;
      case 'delete':
        await _deleteSource();
        break;
    }
  }

  // --- 视图 ---

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final settings = context.watch<SettingsProvider>();
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: CustomBackgroundSurfaces.transparentWhenEnabled(
        settings,
        colorScheme.surface,
      ),
      appBar: AppBar(
        title: const Text('网络媒体'),
        backgroundColor: CustomBackgroundSurfaces.transparentWhenEnabled(
          settings,
          colorScheme.surface,
        ),
        surfaceTintColor: Colors.transparent,
        actions: <Widget>[
          if (_active != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                children: <Widget>[
                  TextButton.icon(
                    onPressed: _scanning ? null : () => _playAll(includeVideo: false),
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('播放全部'),
                  ),
                  const SizedBox(width: 4),
                  TextButton.icon(
                    onPressed: _scanning ? null : _addAllToQueue,
                    icon: const Icon(Icons.playlist_add, size: 18),
                    label: const Text('加入队列'),
                  ),
                ],
              ),
            ),
        ],
      ),
      body: Column(
        children: <Widget>[
          const Divider(height: 1, thickness: 1),
          Expanded(
            child: Row(
              children: <Widget>[
                SizedBox(width: 264, child: _buildSourcePane(colorScheme)),
                const VerticalDivider(width: 1, thickness: 1),
                Expanded(child: _buildBrowserPane(colorScheme)),
              ],
            ),
          ),
          if (_scanning) _buildScanBar(colorScheme),
        ],
      ),
    );
  }

  Widget _buildSourcePane(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '网络驱动器',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 2),
              Text(
                'WebDAV / FTP · 按需拉流，不占用本地空间',
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: _addSource,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('添加网络源'),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _sources.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Text(
                      '还没有网络源\n点击「添加网络源」填写\nWebDAV 或 FTP 地址',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.6,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: _sources.length,
                  itemBuilder: (context, index) {
                    final source = _sources[index];
                    final selected = _active?.id == source.id;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Material(
                        color: selected
                            ? colorScheme.secondaryContainer
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () {
                            setState(() => _selectedSourceId = source.id);
                            _openSource(source);
                          },
                          onSecondaryTap: () => setState(
                            () => _selectedSourceId = source.id,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            child: Row(
                              children: <Widget>[
                                Icon(
                                  source.type == RemoteSourceType.webdav
                                      ? Icons.cloud_outlined
                                      : Icons.dns_outlined,
                                  size: 18,
                                  color: selected
                                      ? colorScheme.onSecondaryContainer
                                      : colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(
                                        source.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: selected
                                              ? FontWeight.w600
                                              : FontWeight.w400,
                                          color: selected
                                              ? colorScheme.onSecondaryContainer
                                              : colorScheme.onSurface,
                                        ),
                                      ),
                                      const SizedBox(height: 1),
                                      Text(
                                        '${remoteSourceTypeLabel(source.type)} · ${source.host}:${source.port}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          color: selected
                                              ? colorScheme
                                                  .onSecondaryContainer
                                              : colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        const Divider(height: 1, thickness: 1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: <Widget>[
              Expanded(
                child: TextButton.icon(
                  onPressed: _selectedSourceId == null ? null : _editSource,
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('编辑'),
                ),
              ),
              Expanded(
                child: TextButton.icon(
                  onPressed: _selectedSourceId == null ? null : _deleteSource,
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('删除'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBrowserPane(ColorScheme colorScheme) {
    final active = _active;
    if (active == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.cloud_queue,
              size: 46,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 10),
            Text(
              '从左侧选择一个网络源开始浏览',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '列表只显示文件夹与音频文件',
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Row(
            children: <Widget>[
              IconButton(
                tooltip: _history.isEmpty ? '返回网络源列表' : '返回上级目录',
                onPressed: _goUp,
                icon: const Icon(Icons.arrow_upward, size: 18),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      active.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      _currentPath,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 190,
                height: 34,
                child: TextField(
                  controller: _filterController,
                  onChanged: (value) => setState(() => _filter = value),
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    hintText: '在当前目录筛选',
                    hintStyle: const TextStyle(fontSize: 11.5),
                    isDense: true,
                    prefixIcon: const Icon(Icons.search, size: 16),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 30,
                      minHeight: 30,
                    ),
                    suffixIcon: _filter.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close, size: 14),
                            visualDensity: VisualDensity.compact,
                            onPressed: () {
                              _filterController.clear();
                              setState(() => _filter = '');
                            },
                          ),
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(vertical: 6),
                  ),
                ),
              ),
              IconButton(
                tooltip: '刷新',
                onPressed: _loading ? null : _loadDirectory,
                icon: const Icon(Icons.refresh, size: 18),
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                tooltip: '更多',
                onPressed: _openMenu,
                icon: const Icon(Icons.more_vert, size: 18),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        Expanded(child: _buildEntryList(colorScheme)),
        _buildStatusBar(colorScheme),
      ],
    );
  }

  Widget _buildStatusBar(ColorScheme colorScheme) {
    final audioCount = _audioEntries.length;
    final dirCount = _entries.where((entry) => entry.isDirectory).length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: colorScheme.outlineVariant, width: 1),
        ),
      ),
      child: Row(
        children: <Widget>[
          Text(
            '$dirCount 个文件夹 · $audioCount 首音频',
            style: TextStyle(
              fontSize: 10.5,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          Text(
            _enqueueMode ? '点击：加入队列' : '点击：立即播放',
            style: TextStyle(
              fontSize: 10.5,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEntryList(ColorScheme colorScheme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.error_outline, size: 38, color: colorScheme.error),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11.5, height: 1.5),
              ),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: _loadDirectory,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    final entries = _visibleEntries;
    if (entries.isEmpty) {
      return Center(
        child: Text(
          _filter.isEmpty ? '该目录为空，或只有不支持的文件' : '没有匹配「$_filter」的条目',
          style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 2),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        return ListTile(
          dense: true,
          visualDensity: const VisualDensity(vertical: -2),
          leading: Icon(
            entry.isDirectory
                ? Icons.folder_outlined
                : Icons.audio_file_outlined,
            size: 18,
            color: entry.isDirectory
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant,
          ),
          title: Text(
            entry.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5),
          ),
          subtitle: entry.isDirectory
              ? null
              : Text(
                  entry.sizeLabel,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
          trailing: entry.isDirectory
              ? Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    IconButton(
                      tooltip: '加入队列',
                      icon: const Icon(Icons.playlist_add, size: 18),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _enqueueEntry(entry),
                    ),
                    IconButton(
                      tooltip: '播放',
                      icon: const Icon(Icons.play_arrow, size: 18),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _playEntry(entry),
                    ),
                  ],
                ),
          onTap: () => _openEntry(entry),
        );
      },
    );
  }

  Widget _buildScanBar(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        border: Border(
          top: BorderSide(color: colorScheme.outlineVariant, width: 1),
        ),
      ),
      child: Row(
        children: <Widget>[
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text(
            '正在递归扫描：已找到 $_scanFound 首音频 / 已扫描 $_scanDirs 个目录',
            style: const TextStyle(fontSize: 11.5),
          ),
          const Spacer(),
          TextButton(
            onPressed: () => setState(() => _cancelScan = true),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }
}
