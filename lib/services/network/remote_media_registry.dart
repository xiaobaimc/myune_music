import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../page/playlist/playlist_models.dart';
import 'local_stream_proxy.dart';

/// 远端流的元数据注册表。
///
/// 网络音乐的 `Song.filePath` 是本机代理 URL，不是本地文件。原有
/// `_parseSongMetadata()` 会对本地文件做 `File.exists()` 与标签读取，
/// 对 URL 会误报「文件不存在 (解析失败)」。这里按 URL 保存浏览页构造好的
/// 标题 / 歌手 / 专辑 / 时长 / 封面，播放链路只需在解析函数开头查一次表即可。
///
/// 元数据同时编码在代理 URL 里（见 [LocalStreamProxy.urlForNas]），因此应用
/// 重启后，恢复的播放队列里即使注册表为空也能从 URL 还原出正确的歌曲信息。
class RemoteMediaRegistry {
  RemoteMediaRegistry._();

  static const String _userAgent = 'MyuneMusic/1.0 (Desktop)';

  static final Map<String, Song> _entries = <String, Song>{};
  static final Map<String, Uint8List> _artwork = <String, Uint8List>{};

  static void register(String url, Song song) {
    if (url.isEmpty) return;
    // 队列可能反复播放同一地址，控制内存占用上限，超出时淘汰最早项。
    if (_entries.length > 512) {
      _entries.remove(_entries.keys.first);
    }
    _entries[url] = song;
  }

  /// 从代理 URL 解出规范化 target。
  static Map<String, dynamic>? decodeTarget(String url) {
    try {
      final segments = Uri.parse(url).pathSegments;
      if (segments.length < 2 || segments[0] != LocalStreamProxy.token) {
        return null;
      }
      return LocalStreamProxy.decodeToken(segments[1]);
    } catch (_) {
      return null;
    }
  }

  static String? artworkUrlFor(String url) {
    final target = decodeTarget(url);
    if (target == null) return null;
    final value = (target['u'] ?? target['cover'] ?? target['art'] ?? '')
        .toString()
        .trim();
    return value.isEmpty ? null : value;
  }

  static String? mediaIdOf(String url) {
    final target = decodeTarget(url);
    if (target == null) return null;
    final value = (target['id'] ?? '').toString().trim();
    return value.isEmpty ? null : value;
  }

  static Song? lookup(String urlOrId) {
    // 统一规范化：裸媒体标识还原成代理 URL、旧端口 URL 改写到当前端口。
    // 这样播放状态恢复、队列重建、歌曲详情等所有入口拿到的 filePath
    // 都是「此刻真正能连上」的地址。
    final playable = normalizePlayablePath(urlOrId);
    if (playable != urlOrId) return lookup(playable);

    final direct = _entries[urlOrId];
    if (direct != null) return direct;

    // 仍无法还原的裸标识（例如 nas:）交给调用方兜底。
    if (LocalStreamProxy.isMediaId(urlOrId)) return null;
    if (!LocalStreamProxy.isProxyUrl(urlOrId)) return null;

    final target = decodeTarget(urlOrId);
    if (target == null) return null;
    String text(String key) => (target[key] ?? '').toString().trim();
    final title = text('t');
    // 即使 URL 里没有编码标题，也必须返回一个占位 Song：播放链路据此识别
    // 「网络媒体」，不会再把 URL 交给 File.exists() / readAudioInfo()
    // 而误报「文件不存在」。
    final mediaId = text('id');
    final resolvedTitle = title.isNotEmpty
        ? title
        : (mediaId.isNotEmpty ? mediaId : '网络媒体');
    final artistText = text('r');
    final albumText = text('l');
    final durationRaw = target['d'];
    final duration = durationRaw is num
        ? durationRaw.toInt()
        : (int.tryParse(durationRaw?.toString().trim() ?? '') ?? 0);
    final song = Song(
      title: resolvedTitle,
      artist: artistText.isEmpty ? '未知歌手' : artistText,
      album: albumText.isEmpty ? '网络媒体' : albumText,
      filePath: urlOrId,
      duration: duration > 0 ? Duration(seconds: duration) : null,
      albumArt: _artwork[urlOrId],
    );
    register(urlOrId, song);
    return song;
  }

  /// 登记一张已下载的封面（网盘目录封面）。
  /// 若该 URL 已有注册 Song，会同步回填 albumArt，UI 无需再等一次网络请求。
  static void registerArtwork(String url, Uint8List bytes) {
    if (url.isEmpty || bytes.isEmpty) return;
    if (_artwork.length > 128) _artwork.remove(_artwork.keys.first);
    _artwork[url] = bytes;
    final song = _entries[url];
    if (song != null && song.albumArt == null) {
      _entries[url] = _copyWithArt(song, bytes);
    }
  }

  static Uint8List? cachedArtwork(String url) => _artwork[url];

  /// 按需下载封面。
  ///
  /// 封面地址本身也是一个本机代理 URL（见
  /// `NetworkMediaService.directoryArtworkUrl`），鉴权由代理补齐，
  /// 因此这里不需要再拼 WebDAV / FTP 凭据。失败或超大图直接返回 null，
  /// 不阻断播放。结果写入内存缓存并回填注册项。
  static Future<Uint8List?> artworkFor(String url) async {
    final cached = _artwork[url];
    if (cached != null) return cached;
    final imageUrl = artworkUrlFor(url);
    if (imageUrl == null || imageUrl.isEmpty) return null;
    try {
      final response = await http
          .get(
            Uri.parse(imageUrl),
            headers: <String, String>{'User-Agent': _userAgent},
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final bytes = response.bodyBytes;
      if (bytes.isEmpty || bytes.length > 4 * 1024 * 1024) return null;
      registerArtwork(url, bytes);
      return bytes;
    } catch (_) {
      return null;
    }
  }

  /// 把裸媒体标识还原成可播放的本机代理 URL；同时修正重启后的端口漂移。
  ///
  /// 代理端口固定在 18765-18774，某次启动若 18765 被占用会顺延。已持久化的
  /// 播放队列里保存的是旧端口 URL，直接交给 Media() 会连不上。这里按原 token
  /// 重新生成 URL，并迁移注册项与封面。代理未启动时返回原值。
  static String normalizePlayablePath(String value) {
    // 端口没变时原样返回，保持所有已注册的 key / 持久化数据完全一致；
    // 只有端口漂移才重写，避免每次播放都生成新 token。
    if (LocalStreamProxy.isProxyUrl(value)) {
      final currentPort = LocalStreamProxy.instance.port;
      if (currentPort == null) return value;
      final uri = Uri.tryParse(value);
      if (uri == null || uri.port == currentPort) return value;
      final target = decodeTarget(value);
      if (target == null) return value;
      try {
        final rewritten = LocalStreamProxy.instance.urlFor(target);
        _migrate(value, rewritten);
        return rewritten;
      } catch (_) {
        return value;
      }
    }
    return value;
  }

  /// 端口漂移后把旧 URL 的注册项与封面缓存迁到新 URL。
  static void _migrate(String from, String to) {
    if (from == to) return;
    final song = _entries.remove(from);
    if (song != null) _entries[to] = _copyWithPath(song, to);
    final art = _artwork.remove(from);
    if (art != null) _artwork[to] = art;
  }

  static Song _copyWithPath(Song song, String filePath) {
    return Song(
      title: song.title,
      artist: song.artist,
      album: song.album,
      filePath: filePath,
      albumArt: song.albumArt,
      duration: song.duration,
      trackNumber: song.trackNumber,
      genre: song.genre,
    );
  }

  /// 规范化一个网络媒体的 Song，供播放队列入口统一调用：
  /// 兼容裸媒体标识，并修正代理端口漂移。本地文件与其它调用方完全不受影响。
  static Song normalizeSong(Song song) {
    if (!isNetwork(song.filePath)) return song;
    final url = normalizePlayablePath(song.filePath);
    if (url == song.filePath) return song;
    final normalized = Song(
      title: song.title,
      artist: song.artist,
      album: song.album,
      filePath: url,
      albumArt: song.albumArt ?? cachedArtwork(url),
      duration: song.duration,
      trackNumber: song.trackNumber,
      genre: song.genre,
    );
    register(url, normalized);
    if (normalized.albumArt != null && normalized.albumArt!.isNotEmpty) {
      registerArtwork(url, normalized.albumArt!);
    }
    return normalized;
  }

  static Song _copyWithArt(Song song, Uint8List bytes) {
    return Song(
      title: song.title,
      artist: song.artist,
      album: song.album,
      filePath: song.filePath,
      albumArt: bytes,
      duration: song.duration,
      trackNumber: song.trackNumber,
      genre: song.genre,
    );
  }

  static void clear() {
    _entries.clear();
    _artwork.clear();
  }

  static int get length => _entries.length;

  /// 是否为网络媒体（本机代理 URL 或裸媒体标识）。播放链路里凡是要走
  /// 文件系统 / 本地标签读取的地方都需要先判断这个。
  static bool isNetwork(String value) =>
      LocalStreamProxy.isProxyUrl(value) || LocalStreamProxy.isMediaId(value);
}
