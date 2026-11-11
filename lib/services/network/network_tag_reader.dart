import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../src/rust/api/audio_info.dart';
import 'network_header_tags.dart';
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

  /// 用磁盘上的封面二进制补全一个来自 JSON 索引的条目。
  ///
  /// JSON 里刻意不存封面（体积大），启动时需要把同名 `.cover` 文件补回来，
  /// 否则 `cached()` 返回的条目永远 `hasCover == false`。
  NetworkTagInfo withCover(Uint8List? cover) => NetworkTagInfo(
    title: title,
    artist: artist,
    album: album,
    genre: genre,
    durationMs: durationMs,
    trackNumber: trackNumber,
    cover: cover ?? this.cover,
    lyrics: lyrics,
    partial: partial,
  );

  /// 落盘用的轻量表示。封面体积大，单独写成二进制文件，不进 JSON。
  Map<String, dynamic> toJson() => <String, dynamic>{
    if (title != null) 'title': title,
    if (artist != null) 'artist': artist,
    if (album != null) 'album': album,
    if (genre != null) 'genre': genre,
    if (durationMs != null) 'durationMs': durationMs,
    if (trackNumber != null) 'trackNumber': trackNumber,
    if (lyrics != null) 'lyrics': lyrics,
    if (partial) 'partial': true,
    'updatedAt': DateTime.now().millisecondsSinceEpoch,
  };

  static NetworkTagInfo? fromJson(Map<String, dynamic> json) {
    int? asInt(Object? value) {
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString().trim() ?? '');
    }

    String? asText(Object? value) {
      final text = value?.toString().trim();
      return (text == null || text.isEmpty) ? null : text;
    }

    final info = NetworkTagInfo(
      title: asText(json['title']),
      artist: asText(json['artist']),
      album: asText(json['album']),
      genre: asText(json['genre']),
      durationMs: asInt(json['durationMs']),
      trackNumber: asInt(json['trackNumber']),
      lyrics: asText(json['lyrics']),
      partial: json['partial'] == true,
    );
    return info.hasAny ? info : null;
  }
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

  /// 磁盘缓存目录（位于 `文档/myune_music/tag_cache/`）。
  static const String _diskDirName = 'tag_cache';
  static const String _jsonSuffix = '.json';
  static const String _coverSuffix = '.cover';

  /// 磁盘条目 / 体积上限，超出后按最后修改时间淘汰最旧的。
  static const int _diskMaxEntries = 3000;
  static const int _diskMaxBytes = 512 * 1024 * 1024;

  /// 启动时一次性补回内存的封面上限。超过就保留「按需 hydrate」，避免超大
  /// 曲库把启动时间和内存一起拖垮。
  static const int _maxHydratedCoverBytes = 128 * 1024 * 1024;

  static final Map<String, NetworkTagInfo> _cache = <String, NetworkTagInfo>{};
  static final Map<String, Future<NetworkTagInfo?>> _inflight =
      <String, Future<NetworkTagInfo?>>{};

  /// 磁盘索引：`sha1(stableKey) -> 元数据（不含封面）`。
  ///
  /// 启动时一次性读入，之后 [cached] 同步命中，列表首帧就有标题 / 时长 /
  /// 内嵌歌词；封面按需从同名 `.cover` 文件补，不必重新联网。
  static final Map<String, NetworkTagInfo> _diskIndex =
      <String, NetworkTagInfo>{};

  static Directory? _diskDir;
  static bool _diskReady = false;

  /// 应用启动时调用一次：把磁盘上的标签索引与封面一起读进内存。
  ///
  /// 封面是单独的 `.cover` 二进制文件。以前这里只读 JSON 元数据，导致重启后
  /// `cached()` 返回的条目恒为 `hasCover == false`，列表里的网络媒体封面全部
  /// 空白，必须手动点一次「一键读取本目录封面」才会重新出现。现在启动即补回，
  /// 纯本地 IO、不产生任何网络请求；分批并发 + 体积上限控制启动开销。
  static Future<void> initialize() async {
    if (_diskReady) return;
    _diskReady = true;
    final dir = await _diskDirectory();
    if (dir == null) return;
    var loaded = 0;
    var hydrated = 0;
    var hydratedBytes = 0;
    try {
      final files = <File>[];
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith(_jsonSuffix)) {
          files.add(entity);
        }
      }
      const int batchSize = 8;
      for (var i = 0; i < files.length; i += batchSize) {
        final batch = files.skip(i).take(batchSize).toList(growable: false);
        final results = await Future.wait(
          batch.map<Future<MapEntry<String, NetworkTagInfo>?>>(
            (file) => _loadDiskEntry(
              file,
              hydratedBytes < _maxHydratedCoverBytes,
            ),
          ),
        );
        for (final entry in results) {
          if (entry == null) continue;
          _diskIndex[entry.key] = entry.value;
          loaded++;
          final cover = entry.value.cover;
          if (cover != null && cover.isNotEmpty) {
            hydrated++;
            hydratedBytes += cover.length;
          }
        }
      }
      NetworkProxyLog.instance.write(
        'tag cache loaded $loaded entries, covers hydrated $hydrated '
        '(${(hydratedBytes / 1048576).toStringAsFixed(1)} MB)',
      );
    } catch (error) {
      NetworkProxyLog.instance.write('tag cache load failed: $error');
    }
  }

  /// 读一个磁盘条目：JSON 元数据 + 同名 `.cover` 二进制。
  static Future<MapEntry<String, NetworkTagInfo>?> _loadDiskEntry(
    File file,
    bool hydrateCover,
  ) async {
    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final hash = p.basenameWithoutExtension(file.path);
      var info = NetworkTagInfo.fromJson(Map<String, dynamic>.from(decoded));
      if (hydrateCover) {
        final cover = await _readCoverByHash(hash);
        if (cover != null && cover.isNotEmpty) {
          // 极少数文件只有封面、没有标题/歌词时 fromJson 会返回 null，
          // 这里仍然保留它的封面，不能把这类条目整个丢掉。
          info = (info ?? const NetworkTagInfo()).withCover(cover);
        }
      }
      if (info == null) return null;
      return MapEntry(hash, info);
    } catch (_) {
      // 单个文件损坏就跳过，不影响其它条目。
      return null;
    }
  }

  /// 已经读到过的标签（同步返回，供列表构建时零成本合并）。
  ///
  /// 内存没命中时查磁盘索引——这就是「重启后不用重新联网」的关键。
  static NetworkTagInfo? cached(String url) {
    final hit = _cache[url];
    if (hit != null) return hit;
    final key = _stableKey(url);
    if (key == null) return null;
    final disk = _diskIndex[_hash(key)];
    if (disk == null) return null;
    _cache[url] = disk;
    return disk;
  }

  /// 读取指定网络媒体的内嵌标签。读不到返回 null，不抛异常。
  static Future<NetworkTagInfo?> read(String url) {
    if (!enabled) return Future<NetworkTagInfo?>.value();
    if (!RemoteMediaRegistry.isNetwork(url)) {
      return Future<NetworkTagInfo?>.value();
    }
    final hit = _cache[url];
    if (hit != null) {
      if (hit.hasCover) return Future<NetworkTagInfo?>.value(hit);
      // 磁盘索引里的条目不含封面：从磁盘补一次，避免为了封面重新联网。
      final pendingCover = _inflight[url];
      if (pendingCover != null) return pendingCover;
      final future = _hydrateCover(url, hit).whenComplete(
        () => _inflight.remove(url),
      );
      _inflight[url] = future;
      return future;
    }
    final pending = _inflight[url];
    if (pending != null) return pending;
    final future = _readUncached(url).whenComplete(
      () => _inflight.remove(url),
    );
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

  /// 批量读取一组网络音频的标签 / 封面（「一键读取本目录」用）。
  ///
  /// 与「滚动到哪读到哪」互补：用户希望主动把整个目录的封面先缓存好时调用。
  /// 默认 2 并发，避免把上游或 Drive 配额打满；已经缓存过的条目会直接命中
  /// 内存 / 磁盘，不产生网络请求。返回真正读到内容的条数。
  static Future<int> prefetchAll(
    List<String> urls, {
    int concurrency = 2,
    void Function(int done, int total)? onProgress,
  }) async {
    if (!enabled) return 0;
    final targets = urls
        .where((url) => url.isNotEmpty && RemoteMediaRegistry.isNetwork(url))
        .toList(growable: false);
    if (targets.isEmpty) return 0;
    var done = 0;
    var success = 0;
    var next = 0;

    Future<void> worker() async {
      while (true) {
        final index = next++;
        if (index >= targets.length) return;
        try {
          final info = await read(targets[index]);
          if (info != null && info.hasAny) success++;
        } catch (_) {
          // 单首失败不影响整批。
        }
        done++;
        onProgress?.call(done, targets.length);
      }
    }

    final workers = <Future<void>>[
      for (var i = 0; i < concurrency && i < targets.length; i++) worker(),
    ];
    await Future.wait(workers);
    return success;
  }

  static void clear() {
    _cache.clear();
  }

  static Future<NetworkTagInfo?> _readUncached(String url) async {
    try {
      final head = await _fetchHead(url);
      if (head != null) {
        try {
          // 两条独立路径，互不拖累：
          // 1) 纯 Dart 按字节解析头部（不需要扩展名、不需要文件完整），
          //    FLAC / MP3 的封面与内嵌歌词由此稳定拿到；
          // 2) lofty 解析同一个文件，覆盖 M4A / OGG / APE 等其它容器。
          // 任一条成功即可，最后按「字节解析优先」合并。
          final headerTags = NetworkHeaderTagParser.parse(head.bytes);
          NetworkTagInfo? loftyInfo;
          try {
            loftyInfo = await _parse(
              head.path,
              partial: !head.complete,
              totalBytes: head.totalBytes,
            );
          } catch (_) {
            // lofty 对截断文件报错是预期内，交给字节解析结果兜底。
          }
          final merged = _combine(head, headerTags, loftyInfo);
          if (merged != null && merged.hasAny) return _remember(url, merged);
          NetworkProxyLog.instance.write(
            'tag read empty ext=${head.extension} head=${head.bytes.length}B '
            'via=${headerTags?.format ?? '-'} lofty=${loftyInfo != null}',
          );
        } finally {
          // 头部文件只是中间产物：解析完就删，否则看一遍曲库就会在临时目录
          // 里堆出几个 GB。同一次运行内由内存缓存兜底，不会重复下载。
          await _deleteQuietly(head.path);
        }
      }

      // 头部完全解析不出来时才退回完整下载。远端已声明总长且超过缓存上限
      // 时直接跳过，避免为了一个封面发起必失败的几十 MB 请求。
      if (head != null &&
          head.totalBytes != null &&
          head.totalBytes! > NetworkMediaService.tagCacheMaxBytes) {
        return null;
      }
      final full = await NetworkMediaService.tagCachePath(url);
      if (full == null) return null;
      final info = await _parse(full, partial: false);
      if (info == null || !info.hasAny) return null;
      NetworkProxyLog.instance.write(
        'tag read ok via=full cover=${info.cover?.length ?? 0}B '
        'lyrics=${info.lyrics?.length ?? 0}ch',
      );
      return _remember(url, info);
    } catch (error) {
      NetworkProxyLog.instance.write('tag read failed: $error');
      return null;
    } finally {
      _inflight.remove(url);
    }
  }

  /// 合并两条解析路径的结果，并写一条可核对的诊断日志。
  ///
  /// 字节解析出来的元数据是「完整标签块」，优先于 lofty 对截断文件的估算；
  /// 尤其是时长（FLAC STREAMINFO 直接给出精确值）。
  static NetworkTagInfo? _combine(
    _HeadFile head,
    NetworkHeaderTags? header,
    NetworkTagInfo? lofty,
  ) {
    if (header == null && lofty == null) return null;
    final Uint8List? cover = (header?.hasCover ?? false)
        ? header!.cover
        : lofty?.cover;
    final String? lyrics = (header?.hasLyrics ?? false)
        ? header!.lyrics
        : lofty?.lyrics;
    final info = NetworkTagInfo(
      title: header?.title ?? lofty?.title,
      artist: header?.artist ?? lofty?.artist,
      album: header?.album ?? lofty?.album,
      genre: header?.genre ?? lofty?.genre,
      durationMs: header?.durationMs ?? lofty?.durationMs,
      trackNumber: header?.trackNumber ?? lofty?.trackNumber,
      cover: cover,
      lyrics: lyrics,
      partial: header == null && (lofty?.partial ?? false),
    );
    NetworkProxyLog.instance.write(
      'tag read ok ext=${head.extension} head=${head.bytes.length}B '
      'total=${head.totalBytes ?? '-'}B via=${header?.format ?? 'lofty'} '
      'cover=${cover?.length ?? 0}B lyrics=${lyrics?.length ?? 0}ch '
      'duration=${info.durationMs ?? '-'}ms',
    );
    return info;
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
    // 落盘是「顺手」动作：失败只写日志，绝不影响本次解析结果。
    unawaited(_saveToDisk(url, info));
    return info;
  }

  /// 稳定 key：网络源 id + 媒体 id（取不到时用远端路径）。
  ///
  /// 刻意不用代理 URL：代理端口会在 18765-18774 之间漂移，用完整 URL 做 key
  /// 会让每次换端口都全部失效。
  static String? _stableKey(String url) {
    final target = RemoteMediaRegistry.decodeTarget(url);
    if (target == null) return null;
    final source = (target['s'] ?? '').toString().trim();
    final mediaId = (target['id'] ?? '').toString().trim();
    final path = (target['p'] ?? '').toString().trim();
    final identity = mediaId.isNotEmpty ? mediaId : path;
    if (identity.isEmpty) return null;
    return '${source.isEmpty ? '-' : source}|$identity';
  }

  static String _hash(String key) =>
      crypto.sha1.convert(utf8.encode(key)).toString();

  static Future<Directory?> _diskDirectory() async {
    if (_diskDir != null) return _diskDir;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, 'myune_music', _diskDirName));
      if (!await dir.exists()) await dir.create(recursive: true);
      _diskDir = dir;
      return dir;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _saveToDisk(String url, NetworkTagInfo info) async {
    final key = _stableKey(url);
    if (key == null) return;
    final dir = await _diskDirectory();
    if (dir == null) return;
    final hash = _hash(key);
    try {
      final jsonFile = File(p.join(dir.path, '$hash$_jsonSuffix'));
      await jsonFile.writeAsString(jsonEncode(info.toJson()), flush: true);
      if (info.hasCover) {
        final coverFile = File(p.join(dir.path, '$hash$_coverSuffix'));
        await coverFile.writeAsBytes(info.cover!, flush: true);
      }
      _diskIndex[hash] = info;
      unawaited(_trimDisk(dir));
    } catch (error) {
      NetworkProxyLog.instance.write('tag cache save failed: $error');
    }
  }

  static Future<Uint8List?> _readCoverFile(String key) =>
      _readCoverByHash(_hash(key));

  static Future<Uint8List?> _readCoverByHash(String hash) async {
    final dir = await _diskDirectory();
    if (dir == null) return null;
    try {
      final file = File(p.join(dir.path, '$hash$_coverSuffix'));
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      return bytes.isEmpty ? null : bytes;
    } catch (_) {
      return null;
    }
  }

  /// 内存条目来自磁盘索引（不含封面）时，从磁盘补一次封面。
  static Future<NetworkTagInfo?> _hydrateCover(
    String url,
    NetworkTagInfo base,
  ) async {
    try {
      final key = _stableKey(url);
      if (key == null) return base;
      final cover = await _readCoverFile(key);
      if (cover == null) return base;
      final merged = base.withCover(cover);
      _cache[url] = merged;
      return merged;
    } finally {
      _inflight.remove(url);
    }
  }

  /// 超过条目数或体积上限时，按最后修改时间删最旧的。
  static Future<void> _trimDisk(Directory dir) async {
    try {
      final files = (await dir.list().toList()).whereType<File>().toList();
      if (files.isEmpty) return;
      int totalBytes = 0;
      int jsonCount = 0;
      final stats = <MapEntry<File, int>>[];
      for (final file in files) {
        final stat = await file.stat();
        totalBytes += stat.size.toInt();
        if (file.path.endsWith(_jsonSuffix)) jsonCount++;
        stats.add(
          MapEntry(file, stat.modified.millisecondsSinceEpoch.toInt()),
        );
      }
      if (jsonCount <= _diskMaxEntries && totalBytes <= _diskMaxBytes) return;
      stats.sort((a, b) => a.value.compareTo(b.value));
      for (final entry in stats) {
        if (jsonCount <= _diskMaxEntries && totalBytes <= _diskMaxBytes) break;
        final file = entry.key;
        final isJson = file.path.endsWith(_jsonSuffix);
        final base = p.basenameWithoutExtension(file.path);
        try {
          final size = await file.length();
          await file.delete();
          totalBytes -= size;
          if (isJson) {
            jsonCount--;
            _diskIndex.remove(base);
          }
          // JSON 和封面成对存在，删一个就把另一个也带走。
          final partner = File(
            p.join(dir.path, '$base${isJson ? _coverSuffix : _jsonSuffix}'),
          );
          if (await partner.exists()) {
            final partnerSize = await partner.length();
            await partner.delete();
            totalBytes -= partnerSize;
            if (!isJson) jsonCount--;
          }
        } catch (_) {}
      }
    } catch (_) {}
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

  /// 只拉文件头。返回字节、带真实扩展名的临时文件与总长度。
  ///
  /// 头部文件用完即删（见 [_readUncached]），这里不做「复用已有头部文件」
  /// 的缓存，避免临时目录被几 GB 的音频头塞满。
  static Future<_HeadFile?> _fetchHead(String url) async {
    try {
      final root = await getTemporaryDirectory();
      final dir = Directory(p.join(root.path, 'myune_net_cache'));
      if (!await dir.exists()) await dir.create(recursive: true);
      final hash = crypto.sha1.convert(utf8.encode(url)).toString();

      final client = http.Client();
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
        final buffer = BytesBuilder(copy: false);
        var received = 0;
        await for (final chunk in response.stream) {
          if (received + chunk.length > _headBytes) {
            buffer.add(chunk.sublist(0, _headBytes - received));
            received = _headBytes;
            break;
          }
          received += chunk.length;
          buffer.add(chunk);
        }
        if (received == 0) return null;
        final bytes = buffer.takeBytes();

        // 关键：文件名必须带真实音频扩展名，且不能与 tagCachePath 的
        // 完整缓存文件同名（那里是 `$hash$ext`）。以前写成 `$hash.head`，
        // Rust 的 lofty 认不出格式，几十 MB 的 FLAC 就永远读不到封面。
        // 扩展名优先取远端路径，取不到再按文件头 magic 兜底。
        final ext = _extensionOf(url, bytes);
        final file = File(p.join(dir.path, '${hash}_head$ext'));
        await file.writeAsBytes(bytes, flush: true);
        final complete = declaredTotal != null && received >= declaredTotal;
        return _HeadFile(
          file.path,
          bytes,
          complete: complete,
          totalBytes: declaredTotal,
          extension: ext,
        );
      } finally {
        client.close();
      }
    } catch (error) {
      NetworkProxyLog.instance.write('tag head failed: $error');
      return null;
    }
  }

  /// 从代理 URL 里编码的远端路径取扩展名；取不到时按文件头 magic 判断。
  static String _extensionOf(String url, Uint8List bytes) {
    var candidate = '';
    final target = RemoteMediaRegistry.decodeTarget(url);
    if (target != null) {
      candidate = (target['p'] ?? '').toString();
      if (candidate.isEmpty) candidate = (target['t'] ?? '').toString();
    }
    if (candidate.isEmpty) {
      try {
        final segments = Uri.parse(url).pathSegments;
        if (segments.isNotEmpty) candidate = segments.last;
      } catch (_) {}
    }
    final dot = candidate.lastIndexOf('.');
    if (dot >= 0) {
      var ext = candidate.substring(dot + 1).toLowerCase();
      final query = ext.indexOf('?');
      if (query >= 0) ext = ext.substring(0, query);
      ext = ext.replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (ext.isNotEmpty && ext.length <= 5) return '.$ext';
    }
    if (bytes.length >= 12 && _magic(bytes, 4, 4) == 'ftyp') return '.m4a';
    if (bytes.length >= 4) {
      final head = _magic(bytes, 0, 4);
      if (head == 'fLaC') return '.flac';
      if (head == 'OggS') return '.ogg';
      if (head == 'MAC ') return '.ape';
    }
    if (bytes.length >= 3 && _magic(bytes, 0, 3) == 'ID3') return '.mp3';
    return '.bin';
  }

  static String _magic(Uint8List bytes, int start, int length) {
    final end = start + length > bytes.length ? bytes.length : start + length;
    if (end <= start) return '';
    return latin1.decode(
      Uint8List.sublistView(bytes, start, end),
      allowInvalid: true,
    );
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
  const _HeadFile(
    this.path,
    this.bytes, {
    required this.complete,
    required this.extension,
    this.totalBytes,
  });

  final String path;

  /// 头部字节，纯 Dart 解析器直接读它，不依赖文件扩展名。
  final Uint8List bytes;

  /// 写盘时使用的扩展名（诊断用）。
  final String extension;

  /// 头部请求已经拿回了整个文件（文件本身小于头部大小）。
  final bool complete;

  /// 远端文件的总字节数（上游没声明时为 null）。
  final int? totalBytes;
}
