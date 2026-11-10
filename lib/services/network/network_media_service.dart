import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../page/playlist/playlist_models.dart';
import 'ftp_client.dart';
import 'local_stream_proxy.dart';
import 'network_proxy_log.dart';
import 'remote_entry.dart';
import 'remote_media_registry.dart';
import 'remote_source.dart';
import 'remote_stream.dart';
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

  // --- 内嵌标签缓存（预加载） ---

  /// 单个文件允许缓存的上限。超过就跳过标签读取，避免为了一个封面
  /// 把几十上百 MB 的无损文件整个拉下来。
  static const int tagCacheMaxBytes = 48 * 1024 * 1024;

  /// 把远端文件缓存到本地临时目录，供 Rust 标签解析器读取内嵌封面 /
  /// 时长 / 内嵌歌词。同一 URL 只下载一次，之后直接复用缓存文件。
  ///
  /// 返回本地文件路径；不可用（非网络媒体 / 超过上限 / 下载失败）时返回 null。
  static Future<String?> tagCachePath(
    String url, {
    int maxBytes = tagCacheMaxBytes,
  }) async {
    if (!RemoteMediaRegistry.isNetwork(url)) return null;
    try {
      final root = await getTemporaryDirectory();
      final dir = Directory(p.join(root.path, 'myune_net_cache'));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final hash = crypto.sha1.convert(utf8.encode(url)).toString();
      final file = File(p.join(dir.path, '$hash${_extensionOf(url)}'));
      if (await file.exists() && await file.length() > 0) {
        return file.path;
      }
      final ok = await _downloadTo(url, file, maxBytes);
      if (!ok) return null;
      NetworkProxyLog.instance.write(
        'tag cache ready ${p.basename(file.path)} size=${await file.length()}',
      );
      unawaited(pruneTagCache());
      return file.path;
    } catch (error) {
      NetworkProxyLog.instance.write('tag cache failed: $error');
      return null;
    }
  }

  /// 缓存目录的总大小上限。
  ///
  /// 每首读不到头部标签的曲子都会在这里留一份完整副本，长期使用会把临时
  /// 目录撑到几十 GB。超过上限后按「最久未修改」删除，让缓存自然滚动。
  static const int tagCacheMaxTotalBytes = 400 * 1024 * 1024;

  static Future<void> pruneTagCache({
    int maxTotalBytes = tagCacheMaxTotalBytes,
  }) async {
    try {
      final root = await getTemporaryDirectory();
      final dir = Directory(p.join(root.path, 'myune_net_cache'));
      if (!await dir.exists()) return;
      final files = <File>[];
      var total = 0;
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        try {
          total += await entity.length();
          files.add(entity);
        } catch (_) {
          // 文件刚好被删掉时跳过。
        }
      }
      if (total <= maxTotalBytes) return;
      final stats = <MapEntry<File, DateTime>>[];
      for (final file in files) {
        try {
          stats.add(MapEntry(file, (await file.stat()).modified));
        } catch (_) {}
      }
      stats.sort((a, b) => a.value.compareTo(b.value));
      for (final entry in stats) {
        if (total <= maxTotalBytes) break;
        try {
          final size = await entry.key.length();
          await entry.key.delete();
          total -= size;
        } catch (_) {}
      }
    } catch (_) {
      // 清理失败不影响主流程。
    }
  }

  static String _extensionOf(String url) {
    try {
      final segments = Uri.parse(url).pathSegments;
      if (segments.isEmpty) return '.bin';
      final name = segments.last;
      final dot = name.lastIndexOf('.');
      if (dot < 0) return '.bin';
      final ext = name.substring(dot + 1).toLowerCase();
      if (ext.isEmpty || ext.length > 5) return '.bin';
      if (!RegExp(r'^[a-z0-9]+$').hasMatch(ext)) return '.bin';
      return '.$ext';
    } catch (_) {
      return '.bin';
    }
  }

  static Future<bool> _downloadTo(
    String url,
    File file,
    int maxBytes,
  ) async {
    final client = http.Client();
    IOSink? opened;
    try {
      final response = await client
          .send(http.Request('GET', Uri.parse(url)))
          .timeout(const Duration(seconds: 25));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.stream.drain<void>();
        return false;
      }
      final declared = response.contentLength;
      if (declared != null && declared > maxBytes) {
        await response.stream.drain<void>();
        return false;
      }
      // 用不可空局部变量写盘：`sink` 会被置空以标记「已关闭」，
      // 那样的可空变量在循环体里拿不到类型提升。
      final sink = file.openWrite();
      opened = sink;
      var received = 0;
      await for (final chunk in response.stream) {
        received += chunk.length;
        if (received > maxBytes) {
          await sink.close();
          opened = null;
          if (await file.exists()) await file.delete();
          return false;
        }
        sink.add(chunk);
      }
      await sink.close();
      opened = null;
      return received > 0;
    } catch (_) {
      try {
        await opened?.close();
      } catch (_) {}
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
      return false;
    } finally {
      client.close();
    }
  }

  // --- 诊断 ---

  /// 生成一份可读的连接诊断报告。
  ///
  /// 用来区分「上游拒绝 / 太慢 / 不支持 Range」与「本机代理链路异常」，
  /// 比 mpv 的 loading failed、Immediate exit requested 具体得多。
  static Future<String> diagnose(RemoteSource source, String path) async {
    final buffer = StringBuffer();
    buffer.writeln('网络源：${source.name}（${remoteSourceTypeLabel(source.type)}）');
    buffer.writeln('地址：${source.displaySubtitle}');
    buffer.writeln('路径：$path');
    buffer.writeln('');

    RemoteProbeResult probe;
    try {
      probe = source.type == RemoteSourceType.webdav
          ? await WebDavClient(source).probe(path)
          : await FtpClient(source).probe(path);
    } catch (error) {
      probe = RemoteProbeResult(
        ok: false,
        statusCode: 0,
        elapsedMs: 0,
        message: '$error',
      );
    }
    buffer.writeln('① 直连上游（取 1 字节响应头）');
    buffer.writeln(
      '   结果：${probe.ok ? '正常' : '失败'}'
      '（状态 ${probe.statusCode}，首包 ${probe.elapsedMs} ms）',
    );
    if (probe.message.isNotEmpty) {
      buffer.writeln('   原因：${probe.message}');
    }
    buffer.writeln('   文件大小：${probe.lengthLabel}');
    buffer.writeln(
      '   支持 Range：${probe.supportsRange ? '是（可拖动进度）' : '否（拖动会整段重下）'}',
    );
    buffer.writeln('   内容类型：${probe.contentType ?? '未声明'}');
    buffer.writeln('');

    // ② 模拟拖动进度：直接向上游要「文件正中间」的两个字节。
    // 这一步是判断「播到一半卡住 / Immediate exit requested」的关键：
    // 很多网盘桥能顺序读，但 seek 要么不支持，要么要重新走一次网盘 API，
    // 慢到 mpv 超时后主动中断连接。
    final total = probe.totalLength;
    if (probe.ok && total != null && total > 4 * 1024 * 1024) {
      final mid = total ~/ 2;
      RemoteProbeResult seek;
      try {
        seek = source.type == RemoteSourceType.webdav
            ? await WebDavClient(source).probe(path, start: mid, end: mid + 1)
            : await FtpClient(source).probe(path);
      } catch (error) {
        seek = RemoteProbeResult(
          ok: false,
          statusCode: 0,
          elapsedMs: 0,
          message: '$error',
        );
      }
      buffer.writeln('② 模拟拖动进度（直接向服务端要第 $mid 字节附近）');
      buffer.writeln(
        '   结果：${seek.ok ? '正常' : '失败'}'
        '（状态 ${seek.statusCode}，耗时 ${seek.elapsedMs} ms）',
      );
      if (seek.message.isNotEmpty) {
        buffer.writeln('   原因：${seek.message}');
      }
      if (!seek.ok) {
        buffer.writeln('   ⚠ 服务端不支持从中段取数据，拖动进度会失败');
      } else if (seek.elapsedMs > 8000) {
        buffer.writeln('   ⚠ 中段取数据太慢，播放器会因超时主动中断连接');
      } else if (seek.elapsedMs > 3000) {
        buffer.writeln('   ⚠ 中段取数据偏慢，拖动进度后可能要等几秒');
      }
      buffer.writeln('');
    } else if (probe.ok) {
      buffer.writeln('② 模拟拖动进度：文件较小或长度未知，跳过');
      buffer.writeln('');
    }

    buffer.writeln('③ 本机流代理');
    final ready = await ensureProxy();
    if (!ready) {
      buffer.writeln('   代理未启动：端口 18765-18774 全部被占用，请重启应用');
    } else {
      final stopwatch = Stopwatch()..start();
      http.Client? client;
      try {
        final url = LocalStreamProxy.instance.urlForNas(
          source.id,
          path,
          title: '诊断',
          proto: source.type == RemoteSourceType.ftp ? 'ftp' : 'webdav',
        );
        client = http.Client();
        final request = http.Request('GET', Uri.parse(url))
          ..headers['Range'] = 'bytes=0-1';
        final response = await client
            .send(request)
            .timeout(const Duration(seconds: 30));
        stopwatch.stop();
        final first = await response.stream.first.timeout(
          const Duration(seconds: 20),
        );
        buffer.writeln(
          '   结果：HTTP ${response.statusCode}，'
          '首块 ${stopwatch.elapsedMilliseconds} ms，收到 ${first.length} 字节',
        );
        buffer.writeln('   Content-Length：${response.contentLength ?? '未声明'}');
        buffer.writeln(
          '   Content-Range：${response.headers['content-range'] ?? '无'}',
        );
        if (response.statusCode != 200 && response.statusCode != 206) {
          buffer.writeln('   说明：代理无法从上游取到数据，请看下方日志');
        }
      } catch (error) {
        stopwatch.stop();
        buffer.writeln('   失败：$error（耗时 ${stopwatch.elapsedMilliseconds} ms）');
      } finally {
        client?.close();
      }
    }

    final logPath = NetworkProxyLog.instance.path;
    if (logPath != null) {
      buffer.writeln('');
      buffer.writeln('日志文件：$logPath');
    }
    return buffer.toString();
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
