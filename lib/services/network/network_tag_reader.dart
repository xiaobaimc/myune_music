import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../src/rust/api/audio_info.dart';
import 'network_media_service.dart';
import 'network_proxy_log.dart';
import 'remote_media_registry.dart';

/// 从一个网络音频文件里读到的内嵌标签。
///
/// 只保留界面真正会用到的字段：标题 / 歌手 / 专辑 / 时长 / 音轨号 /
/// 流派 / 内嵌封面 / 内嵌歌词。
class NetworkTagInfo {
  const NetworkTagInfo({
    this.title,
    this.artist,
    this.album,
    this.genre,
    this.durationMs,
    this.trackNumber,
    this.cover,
    this.lyrics,
    this.partial = false,
  });

  final String? title;
  final String? artist;
  final String? album;
  final String? genre;
  final int? durationMs;
  final int? trackNumber;
  final Uint8List? cover;
  final String? lyrics;

  /// 标签是从「文件头若干 MB」里读出来的，时长可能是估算值。
  final bool partial;

  bool get hasCover => cover != null && cover!.isNotEmpty;
  bool get hasLyrics => lyrics != null && lyrics!.trim().isNotEmpty;
  bool get hasTitle => title != null && title!.trim().isNotEmpty;

  /// 是否读到了「有用的东西」。只有读到时才写进缓存，避免把一次失败
  /// （例如上游临时 502）永久记成「这首歌没有标签」。
  bool get hasAny => hasTitle || hasCover || hasLyrics;
}

/// 网络媒体的内嵌标签读取器（预加载用）。
///
/// 网盘上的音频没法像本地文件那样直接把路径丢给 Rust 解析器，所以这里
/// 先想办法把文件（或它的头部）落到本地临时目录，再交给 `readAudioInfo`。
///
/// 策略是「先便宜后昂贵」：
/// 1. 先用 `Range` 只拉文件头 [_headBytes] 字节。绝大多数格式（MP3 的
///    ID3v2、FLAC 的 METADATA_BLOCK、M4A 的 moov、OGG 的 comment header）
///    都把标签放在文件开头，所以一次 2 MB 的请求就能拿到标题 / 封面 /
///    内嵌歌词，不用为了一首歌把几十 MB 的无损文件整个拉下来。
/// 2. 头部没读出标题和封面时，再退回完整下载（受
///    [NetworkMediaService.tagCacheMaxBytes] 限制），并把结果缓存复用。
///
/// 同一 URL 的结果会记忆化，并发请求会合并成一次，播放列表滚动时不会
/// 对同一个文件反复发请求。
class NetworkTagReader {
  NetworkTagReader._();

  /// 总开关，由设置页的「读取网络媒体内嵌标签」同步过来。
  /// 关掉之后列表只用文件名 / 网盘目录信息，不产生任何额外流量。
  static bool enabled = true;

  /// 头部探测请求的大小。2 MB 足够覆盖 ID3v2 标签 + 常见尺寸的封面。
  static const int _headBytes = 2 * 1024 * 1024;

  /// 记忆化上限。超过后整体清空，比做 LRU 简单且够用。
  static const int _maxEntries = 1500;

  static final Map<String, NetworkTagInfo> _cache = <String, NetworkTagInfo>{};
  static final Map<String, Future<NetworkTagInfo?>> _inflight =
      <String, Future<NetworkTagInfo?>>{};

  /// 已经读到过的标签（同步返回，供列表构建时零成本合并）。
  static NetworkTagInfo? cached(String url) => _cache[url];

  /// 读取指定网络媒体的内嵌标签。读不到返回 null，不抛异常。
  static Future<NetworkTagInfo?> read(String url) {
    if (!enabled) return Future<NetworkTagInfo?>.value();
    if (!RemoteMediaRegistry.isNetwork(url)) {
      return Future<NetworkTagInfo?>.value();
    }
    final hit = _cache[url];
    if (hit != null) return Future<NetworkTagInfo?>.value(hit);
    final pending = _inflight[url];
    if (pending != null) return pending;
    final future = _readUncached(url);
    _inflight[url] = future;
    return future;
  }

  /// 预热：不等待结果，只把请求排进队列。
  static void prefetch(String url) {
    if (!enabled) return;
    if (_cache.containsKey(url)) return;
    if (_inflight.containsKey(url)) return;
    unawaited(read(url));
  }

  static void clear() {
    _cache.clear();
  }

  static Future<NetworkTagInfo?> _readUncached(String url) async {
    try {
      final head = await _fetchHead(url);
      if (head != null) {
        try {
          final info = await _parse(
            head.path,
            partial: !head.complete,
            totalBytes: head.totalBytes,
          );
          if (info != null && info.hasAny) return _remember(url, info);
        } finally {
          // 头部文件只是中间产物：解析完就删，否则看一遍曲库就会在临时目录
          // 里堆出几个 GB。同一次运行内由内存缓存兜底，不会重复下载。
          await _deleteQuietly(head.path);
        }
      }
      final full = await NetworkMediaService.tagCachePath(url);
      if (full == null) return null;
      final info = await _parse(full, partial: false);
      if (info == null) return null;
      return _remember(url, info);
    } catch (error) {
      NetworkProxyLog.instance.write('tag read failed: $error');
      return null;
    } finally {
      _inflight.remove(url);
    }
  }

  static Future<void> _deleteQuietly(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  static NetworkTagInfo _remember(String url, NetworkTagInfo info) {
    if (_cache.length >= _maxEntries) _cache.clear();
    _cache[url] = info;
    return info;
  }

  static Future<NetworkTagInfo?> _parse(
    String path, {
    required bool partial,
    int? totalBytes,
  }) async {
    try {
      final info = await readAudioInfo(
        path: path,
        options: const AudioInfoOptions(
          needCover: true,
          needLyrics: true,
          needAudioProps: true,
          needExtraTags: true,
          needTrackNumber: true,
        ),
      );
      var durationMs = info.durationMs?.toInt();
      if (durationMs != null && durationMs <= 0) durationMs = null;
      if (partial) durationMs = _trustworthyDuration(durationMs, info, totalBytes);
      return NetworkTagInfo(
        title: _clean(info.title),
        artist: _clean(info.artist),
        album: _clean(info.album),
        genre: _clean(info.genre),
        durationMs: durationMs,
        trackNumber: info.trackNumber,
        cover: (info.cover != null && info.cover!.isNotEmpty)
            ? info.cover
            : null,
        lyrics: (info.lyrics != null && info.lyrics!.trim().isNotEmpty)
            ? info.lyrics
            : null,
        partial: partial,
      );
    } catch (error) {
      NetworkProxyLog.instance.write('tag parse failed ($path): $error');
      return null;
    }
  }

  /// 头部截断后解析出来的时长可能只是「按已有字节估算」的结果。
  ///
  /// 用 `总字节数 × 8 ÷ 比特率` 反推一个期望时长，和解析结果比对：
  /// 差异在 10% 以内才采信。对 MP3 这类没有 Xing/VBRI 头的 CBR 文件，
  /// 截断后的估算是整段按已下载字节算出来的，会明显偏小，正好被这条
  /// 规则挡掉，避免播放列表里出现错误的时长。
  static int? _trustworthyDuration(
    int? durationMs,
    AudioInfo info,
    int? totalBytes,
  ) {
    if (durationMs == null) return null;
    final bitrate = info.bitrate;
    if (bitrate == null || bitrate <= 0 || totalBytes == null) return null;
    final expectedMs = totalBytes * 8 * 1000 / bitrate;
    if (expectedMs <= 0) return null;
    final diff = (expectedMs - durationMs).abs();
    return diff <= expectedMs * 0.1 ? durationMs : null;
  }

  static String? _clean(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// 只拉文件头。返回本地缓存文件与「是否已经是完整文件」。
  ///
  /// 头部文件用完即删（见 [_readUncached]），这里不再做「复用已有头部文件」
  /// 的缓存，避免临时目录被几 GB 的音频头塞满。
  static Future<_HeadFile?> _fetchHead(String url) async {
    try {
      final root = await getTemporaryDirectory();
      final dir = Directory(p.join(root.path, 'myune_net_cache'));
      if (!await dir.exists()) await dir.create(recursive: true);
      final hash = crypto.sha1.convert(utf8.encode(url)).toString();

      final client = http.Client();
      IOSink? opened;
      try {
        final request = http.Request('GET', Uri.parse(url))
          ..headers['Range'] = 'bytes=0-${_headBytes - 1}';
        final response = await client
            .send(request)
            .timeout(const Duration(seconds: 20));
        if (response.statusCode != 200 && response.statusCode != 206) {
          await response.stream.drain<void>();
          return null;
        }
        final declaredTotal =
            _totalFromRange(response.headers) ?? response.contentLength;
        final file = File(p.join(dir.path, '$hash.head'));
        // 不可空局部变量：`opened` 只用于异常时兜底关闭。
        final sink = file.openWrite();
        opened = sink;
        var received = 0;
        await for (final chunk in response.stream) {
          if (received + chunk.length > _headBytes) {
            sink.add(chunk.sublist(0, _headBytes - received));
            received = _headBytes;
            break;
          }
          received += chunk.length;
          sink.add(chunk);
        }
        await sink.close();
        opened = null;
        if (received == 0) {
          await _deleteQuietly(file.path);
          return null;
        }
        final complete = declaredTotal != null && received >= declaredTotal;
        return _HeadFile(
          file.path,
          complete: complete,
          totalBytes: declaredTotal,
        );
      } finally {
        try {
          await opened?.close();
        } catch (_) {}
        client.close();
      }
    } catch (error) {
      NetworkProxyLog.instance.write('tag head failed: $error');
      return null;
    }
  }

  /// 从 `Content-Range: bytes 0-2097151/12345678` 里取出总长度。
  static int? _totalFromRange(Map<String, String> headers) {
    final raw = headers['content-range'] ?? headers['Content-Range'];
    if (raw == null) return null;
    final slash = raw.lastIndexOf('/');
    if (slash < 0) return null;
    return int.tryParse(raw.substring(slash + 1).trim());
  }
}

class _HeadFile {
  const _HeadFile(this.path, {required this.complete, this.totalBytes});

  final String path;

  /// 头部请求已经拿回了整个文件（文件本身小于头部大小）。
  final bool complete;

  /// 远端文件的总字节数（上游没声明时为 null）。
  final int? totalBytes;
}
