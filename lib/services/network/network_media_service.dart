import 'dart:async';
import 'dart:typed_data';

import '../../page/playlist/playlist_models.dart';
import 'ftp_client.dart';
import 'local_stream_proxy.dart';
import 'remote_entry.dart';
import 'remote_media_registry.dart';
import 'remote_source.dart';
import 'webdav_client.dart';

/// 网络媒体功能的统一门面：应用启动、目录枚举、把远端条目变成可播放的 Song。
///
/// 页面只依赖这一层，不直接碰协议客户端 / 代理 / 注册表。
class NetworkMediaService {
  NetworkMediaService._();

  /// main() 里调用。代理启动失败不应阻断应用其它功能，因此吞掉异常，
  /// 页面用到代理时再给出可读提示。
  static Future<void> initialize() async {
    await RemoteSourceStore.instance.load();
    try {
      await LocalStreamProxy.instance.start();
    } catch (_) {
      // 端口全被占用时，网络媒体页会在生成 URL 时提示重启应用。
    }
  }

  static Future<List<RemoteEntry>> listDirectory(
    RemoteSource source,
    String path,
  ) async {
    final target = path.trim().isEmpty ? _rootOf(source) : path;
    if (source.type == RemoteSourceType.webdav) {
      return WebDavClient(source).list(target);
    }
    return FtpClient(source).list(target);
  }

  /// 连接自检：能列出根目录即视为可用。返回根目录条目数量。
  static Future<int> testConnection(RemoteSource source) async {
    final entries = await listDirectory(source, _rootOf(source));
    return entries.length;
  }

  static String rootOf(RemoteSource source) => _rootOf(source);

  static String _rootOf(RemoteSource source) {
    return source.type == RemoteSourceType.webdav
        ? source.webdavBaseUri.toString()
        : source.ftpRoot;
  }

  /// 递归扫描一个远端目录，只收集音频文件。
  ///
  /// 用途：网盘曲库通常按「歌手 / 专辑」多层分目录，用户不想一层层点进去
  /// 再逐首添加。这个函数一次性把整棵子树里的音频收集成列表，交给
  /// 「播放全部 / 加入队列」使用，并且不落盘、只在内存里保存路径。
  ///
  /// 为防止误扫巨型目录拖死界面，设有 [maxEntries] 与 [maxDepth] 上限；
  /// 传入 [isCancelled] 可在用户取消时尽快退出（每处理一个目录检查一次）。
  static Future<RemoteScanResult> scanDirectory(
    RemoteSource source,
    String rootPath, {
    int maxEntries = 5000,
    int maxDepth = 8,
    void Function(int scanned, int directories)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final results = <RemoteEntry>[];
    final visited = <String>{};
    final queue = <_ScanNode>[
      _ScanNode(rootPath.trim().isEmpty ? _rootOf(source) : rootPath, 0),
    ];
    var directories = 0;
    var truncated = false;
    var cancelled = false;

    while (queue.isNotEmpty) {
      if (isCancelled != null && isCancelled()) {
        cancelled = true;
        break;
      }
      final node = queue.removeAt(0);
      if (!visited.add(node.path)) continue;
      directories++;

      List<RemoteEntry> entries;
      try {
        entries = await listDirectory(source, node.path);
      } catch (_) {
        // 单个子目录无权限 / 已删除时跳过，不中断整次扫描。
        continue;
      }

      for (final entry in entries) {
        if (entry.isDirectory) {
          if (node.depth + 1 <= maxDepth) {
            queue.add(_ScanNode(entry.path, node.depth + 1));
          }
          continue;
        }
        if (!entry.isAudio) continue;
        results.add(entry);
        if (results.length >= maxEntries) {
          truncated = true;
          break;
        }
      }
      if (truncated) break;
      onProgress?.call(results.length, directories);
    }

    return RemoteScanResult(
      entries: results,
      directories: directories,
      truncated: truncated,
      cancelled: cancelled,
    );
  }

  /// 在当前目录里找常见的专辑封面文件，返回一个可通过本机代理读取的 URL。
  ///
  /// 封面同样走「按需拉流、不落盘」：URL 编码的是网盘上的图片路径，
  /// 代理会补上 WebDAV / FTP 鉴权。`RemoteMediaRegistry.artworkFor()` 会在
  /// 需要显示封面时下载它，播放列表与媒体会话都能拿到 artwork。
  static String? directoryArtworkUrl(
    RemoteSource source,
    List<RemoteEntry> entries,
  ) {
    const candidates = <String>[
      'cover.jpg',
      'cover.jpeg',
      'cover.png',
      'folder.jpg',
      'folder.jpeg',
      'folder.png',
      'front.jpg',
      'front.png',
      'albumart.jpg',
      'albumart.png',
      'thumb.jpg',
    ];
    RemoteEntry? cover;
    for (final name in candidates) {
      for (final entry in entries) {
        if (!entry.isDirectory && entry.name.toLowerCase() == name) {
          cover = entry;
          break;
        }
      }
      if (cover != null) break;
    }
    if (cover == null) return null;
    try {
      return LocalStreamProxy.instance.urlForNas(
        source.id,
        cover.path,
        title: cover.name,
        proto: source.type == RemoteSourceType.ftp ? 'ftp' : 'webdav',
      );
    } catch (_) {
      return null;
    }
  }

  /// 常见命名 `歌手 - 标题.mp3` 自动拆出歌手，避免网盘音乐全部显示「未知歌手」。
  /// 返回 `[title, artist]`。
  static List<String> splitTitleArtist(String name) {
    final base = name.contains('.')
        ? name.substring(0, name.lastIndexOf('.'))
        : name;
    final match = RegExp(r'\s+[-–—~]\s+').firstMatch(base);
    if (match != null) {
      final artist = base.substring(0, match.start).trim();
      final title = base.substring(match.end).trim();
      if (artist.isNotEmpty && title.isNotEmpty) {
        return <String>[title, artist];
      }
    }
    return <String>[base, '未知歌手'];
  }

  /// 把一个网络硬盘音频文件构造成 Song，并登记元数据。
  static Song nasSong({
    required RemoteSource source,
    required RemoteEntry entry,
    String? artist,
    String? album,
    int? durationSeconds,
    String? artworkUrl,
    Uint8List? albumArt,
  }) {
    final parsed = splitTitleArtist(entry.name);
    final title = parsed[0];
    final resolvedArtist =
        (artist == null || artist.trim().isEmpty) ? parsed[1] : artist.trim();
    final resolvedAlbum =
        (album == null || album.trim().isEmpty) ? source.name : album.trim();
    final url = LocalStreamProxy.instance.urlForNas(
      source.id,
      entry.path,
      title: title,
      artist: resolvedArtist,
      album: resolvedAlbum,
      durationSeconds: durationSeconds,
      artworkUrl: artworkUrl,
      proto: source.type == RemoteSourceType.ftp ? 'ftp' : 'webdav',
      mediaId: 'nas:${source.id}:${entry.path.hashCode}',
    );
    final song = Song(
      title: title,
      artist: resolvedArtist,
      album: resolvedAlbum,
      filePath: url,
      albumArt: albumArt,
      duration: (durationSeconds != null && durationSeconds > 0)
          ? Duration(seconds: durationSeconds)
          : null,
    );
    RemoteMediaRegistry.register(url, song);
    if (albumArt != null && albumArt.isNotEmpty) {
      RemoteMediaRegistry.registerArtwork(url, albumArt);
    }
    return song;
  }

  static bool get proxyReady => LocalStreamProxy.instance.isRunning;

  /// 应用启动时若端口被占用导致代理没起来，允许页面侧再试一次，
  /// 不必让用户重启整个应用。
  static Future<bool> ensureProxy() async {
    if (LocalStreamProxy.instance.isRunning) return true;
    try {
      await LocalStreamProxy.instance.start();
    } catch (_) {
      // 交给调用方提示用户。
    }
    return LocalStreamProxy.instance.isRunning;
  }
}

class _ScanNode {
  const _ScanNode(this.path, this.depth);

  final String path;
  final int depth;
}

/// 递归扫描的结果。
class RemoteScanResult {
  const RemoteScanResult({
    required this.entries,
    required this.directories,
    required this.truncated,
    required this.cancelled,
  });

  final List<RemoteEntry> entries;
  final int directories;

  /// 命中数量上限被截断（结果不完整）。
  final bool truncated;

  /// 用户中途取消。
  final bool cancelled;
}
