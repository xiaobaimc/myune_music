import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'ftp_client.dart';
import 'network_proxy_log.dart';
import 'remote_source.dart';
import 'remote_stream.dart';
import 'webdav_client.dart';

/// 本机流代理：把 WebDAV / FTP 统一包装成
/// `http://127.0.0.1:<port>/myune/<token>`，交给 mpv 播放。
///
/// 这样 `AudioService.playSong()` 里原有的 `Media(filePath)` 一个字都不用改，
/// 同时解决三件事：
///   1. mpv 不直接认识带鉴权的 WebDAV 请求，FTP 也不是所有构建都带；
///   2. 代理支持 HTTP Range，网络流可以拖动进度；
///   3. 只按需拉流、不落盘，本地磁盘不会被网盘曲库撑满。
///
/// 端口取固定的一小段（18765-18774），token 固定，因此重启应用后
/// 已保存队列里的 URL 仍然有效，不需要重新解析。
class LocalStreamProxy {
  LocalStreamProxy._();

  static final LocalStreamProxy instance = LocalStreamProxy._();

  static const String token = 'myune';
  static const List<int> _ports = <int>[
    18765,
    18766,
    18767,
    18768,
    18769,
    18770,
    18771,
    18772,
    18773,
    18774,
  ];

  HttpServer? _server;
  int? _port;
  Future<void>? _starting;

  int? get port => _port;
  bool get isRunning => _server != null;

  /// 在 main() 里调用一次。失败不抛给上层，页面会在用到时报出可读错误。
  Future<void> start() async {
    if (_server != null) return;
    final pending = _starting;
    if (pending != null) return pending;
    final future = _startInternal();
    _starting = future;
    try {
      await future;
    } finally {
      _starting = null;
    }
  }

  Future<void> _startInternal() async {
    HttpServer? bound;
    for (final candidate in _ports) {
      try {
        bound = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          candidate,
          shared: false,
        );
        _port = candidate;
        break;
      } catch (_) {
        // 端口被占用时顺延到下一个。
      }
    }
    if (bound == null) {
      throw StateError('无法启动本机流代理：端口 18765-18774 均被占用');
    }
    _server = bound;
    bound.listen(
      _handle,
      onError: (Object _, StackTrace __) {
        // 单个请求异常已经在 _handle 内处理，这里只防止 server 流被错误终止。
      },
    );
  }

  static bool isProxyUrl(String url) {
    return url.startsWith('http://127.0.0.1:') && url.contains('/$token/');
  }

  /// 是否为裸媒体标识 `nas:{sourceId}:{...}`。
  /// 老队列 / 外部传入的标识不能直接交给 `Media()`，需要先规范化成代理 URL。
  static bool isMediaId(String value) => value.startsWith('nas:');

  /// 网络硬盘 / 共享网盘的目标。
  ///
  /// 元数据一起编码进 URL：应用重启后播放队列里保存的仍是这个 URL，
  /// `RemoteMediaRegistry` 可以直接从 URL 还原标题/歌手/封面，不需要重新联网枚举。
  /// [proto] / [mediaId] 显式写入，避免协议与媒体标识在传递中丢失或错位。
  String urlForNas(
    String sourceId,
    String remotePath, {
    String? title,
    String? artist,
    String? album,
    int? durationSeconds,
    String? artworkUrl,
    String? proto,
    String? mediaId,
  }) {
    return urlFor(<String, dynamic>{
      'k': 'nas',
      's': sourceId,
      'p': remotePath,
      if (proto != null && proto.isNotEmpty) 'proto': proto,
      if (mediaId != null && mediaId.isNotEmpty) 'id': mediaId,
      if (title != null && title.isNotEmpty) 't': title,
      if (artist != null && artist.isNotEmpty) 'r': artist,
      if (album != null && album.isNotEmpty) 'l': album,
      if (durationSeconds != null && durationSeconds > 0) 'd': durationSeconds,
      if (artworkUrl != null && artworkUrl.isNotEmpty) 'u': artworkUrl,
    });
  }

  String urlFor(Map<String, dynamic> target) {
    final port = _port;
    if (port == null) {
      throw StateError('本机流代理尚未启动，请重启应用');
    }
    final normalized = normalizeTarget(target);
    final payload = base64UrlEncode(utf8.encode(jsonEncode(normalized)))
        .replaceAll('=', '');
    return 'http://127.0.0.1:$port/$token/$payload';
  }

  /// 解码 token 并规范化。同时兼容裸媒体标识 `nas:...`。
  static Map<String, dynamic>? decodeToken(String rawToken) {
    Map<String, dynamic>? decoded;
    try {
      final text = utf8.decode(
        base64Url.decode(base64Url.normalize(rawToken)),
      );
      final parsed = jsonDecode(text);
      if (parsed is Map<String, dynamic>) decoded = parsed;
    } catch (_) {
      decoded = null;
    }
    if (decoded == null && isMediaId(rawToken)) {
      decoded = <String, dynamic>{'id': rawToken};
    }
    if (decoded == null) return null;
    return normalizeTarget(decoded);
  }

  /// 把各种别名 / 旧写法统一成规范 target。
  static Map<String, dynamic> normalizeTarget(Map<String, dynamic> raw) {
    final t = <String, dynamic>{...raw};

    void alias(String canonical, List<String> others) {
      if (t.containsKey(canonical) &&
          t[canonical] != null &&
          t[canonical].toString().isNotEmpty) {
        return;
      }
      for (final key in others) {
        final value = t[key];
        if (value != null && value.toString().isNotEmpty) {
          t[canonical] = value;
          return;
        }
      }
    }

    // 1) 流目标类型（kind）
    var kind = (t['k'] ?? t['kind'] ?? t['type'] ?? '')
        .toString()
        .toLowerCase()
        .trim();
    final idRaw = (t['id'] ?? t['mediaId'] ?? t['media'] ?? t['mid'] ?? '')
        .toString()
        .trim();
    if (kind.isEmpty && idRaw.startsWith('nas:')) kind = 'nas';
    switch (kind) {
      case 'nas':
      case 'webdav':
      case 'dav':
      case 'ftp':
      case 'http':
      case 'https':
      case 'network':
      case 'share':
        if (!t.containsKey('proto') && kind != 'nas') {
          t['proto'] = kind;
        }
        kind = 'nas';
        break;
      default:
        break;
    }
    t['k'] = kind;

    // 2) 字段别名
    alias('s', <String>['sourceId', 'src', 'source', 'sid']);
    alias('p', <String>['path', 'href', 'remotePath', 'file', 'url']);
    alias('t', <String>['title', 'name']);
    alias('r', <String>['artist', 'author', 'up', 'singer']);
    alias('l', <String>['album']);
    alias('d', <String>['duration', 'durationSeconds', 'len']);
    alias('u', <String>['cover', 'art', 'artwork', 'pic', 'coverUrl']);
    alias('proto', <String>['scheme', 'protocol', 'pcol']);
    alias('id', <String>['mediaId', 'media', 'mid']);

    // 3) 协议字段规范化（仅作元数据，实际客户端以 RemoteSource.type 为准）
    final proto = (t['proto'] ?? '').toString().toLowerCase().trim();
    if (proto == 'ftp' || proto == 'ftps') {
      t['proto'] = 'ftp';
    } else {
      t['proto'] = 'webdav';
    }
    return t;
  }

  RemoteStreamOpener _resolve(Map<String, dynamic> target) {
    final kind = target['k']?.toString();
    if (kind == 'nas') {
      return (int? start, int? end) =>
          _openNas(target, start: start, end: end);
    }
    throw StateError('未知的流目标类型：$kind（target=$target）');
  }

  /// 拿到上游响应头的总预算。
  ///
  /// 自建的「Google Drive → WebDAV」桥在开始推流前往往要先向网盘申请下载
  /// 地址，首包几十秒很常见。原来的 25 秒会先于播放器放弃，mpv 只会报
  /// `loading failed` / `Immediate exit requested`（实测日志里失败时刻正好
  /// 是发起后 25.0 秒）。这里放宽到 45 秒，仍低于 mpv 默认 60 秒的网络超时，
  /// 这样「慢」还有机会救回来，「死」也能让播放器自己报错。
  static const Duration _openBudget = Duration(seconds: 45);

  Future<RemoteStreamResult> _openNas(
    Map<String, dynamic> target, {
    int? start,
    int? end,
  }) async {
    final sourceId = target['s']?.toString() ?? '';
    final source = RemoteSourceStore.instance.byId(sourceId);
    if (source == null) {
      throw StateError('该网络源已被删除，请在「网络媒体」里重新添加');
    }
    final path = target['p']?.toString() ?? '';
    if (path.isEmpty) throw StateError('远程文件路径为空');

    // 上游是「网盘 → WebDAV」这类自建桥时，首包经常被限流或超时。
    // 这里在总预算内做几次重试，避免一次抖动就让 mpv 直接报
    // loading failed / Immediate exit requested。
    Object? lastError;
    final stopwatch = Stopwatch()..start();
    for (var attempt = 0; attempt < 3; attempt++) {
      final remaining = _openBudget - stopwatch.elapsed;
      if (remaining <= const Duration(seconds: 2)) break;
      try {
        // 以配置里的协议为唯一可信来源；URL 中的 proto 字段只作元数据，
        // 避免别名 / 旧数据把 WebDAV 请求错发到 FTP 端口。
        if (source.type == RemoteSourceType.webdav) {
          return await WebDavClient(
            source,
          ).open(path, start: start, end: end, headerTimeout: remaining);
        }
        return await FtpClient(
          source,
        ).open(path, start: start, end: end, headerTimeout: remaining);
      } catch (error) {
        lastError = error;
        NetworkProxyLog.instance.write(
          'upstream open failed attempt=${attempt + 1}/3 '
          'elapsed=${stopwatch.elapsedMilliseconds}ms '
          'proto=${source.type.name} range=${formatRangeHeader(start, end)} '
          'err=$error',
        );
        if (attempt < 2) {
          await Future<void>.delayed(
            Duration(milliseconds: 250 * (attempt + 1)),
          );
        }
      }
    }
    throw lastError ?? StateError('上游打开失败');
  }

  /// 上游不返回总长度时，单独探测一次。
  ///
  /// 网盘桥常见 `Transfer-Encoding: chunked`，没有 `Content-Length`，
  /// 这样 mpv 拿不到总时长也无法 seek。用一次 `Range: bytes=0-0`
  /// 换回 `Content-Range` 里的总长度，代理就能补上 `Content-Length`。
  Future<int?> _probeTotal(Map<String, dynamic> target) async {
    final source =
        RemoteSourceStore.instance.byId(target['s']?.toString() ?? '');
    final path = target['p']?.toString() ?? '';
    if (source == null || path.isEmpty) return null;
    try {
      final probe = source.type == RemoteSourceType.webdav
          ? await WebDavClient(source).probe(path)
          : await FtpClient(source).probe(path);
      return probe.totalLength;
    } catch (error) {
      NetworkProxyLog.instance.write('probe total length failed: $error');
      return null;
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    RemoteStreamResult? opened;
    try {
      if (request.method != 'GET' && request.method != 'HEAD') {
        response.statusCode = HttpStatus.methodNotAllowed;
        response.headers.set('Allow', 'GET, HEAD');
        await response.close();
        return;
      }
      final segments = request.uri.pathSegments;
      if (segments.length < 2 || segments[0] != token) {
        response.statusCode = HttpStatus.notFound;
        await response.close();
        return;
      }

      final target = decodeToken(segments[1]);
      if (target == null || target['k'] == null || target['k'] == '') {
        response.statusCode = HttpStatus.badRequest;
        await response.close();
        return;
      }

      int? start;
      int? end;
      final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
      if (rangeHeader != null) {
        final match = RegExp(
          r'bytes=(\d*)-(\d*)',
          caseSensitive: false,
        ).firstMatch(rangeHeader);
        if (match != null) {
          final from = match.group(1) ?? '';
          final to = match.group(2) ?? '';
          if (from.isNotEmpty) start = int.tryParse(from);
          if (to.isNotEmpty) end = int.tryParse(to);
          // 后缀型 Range（bytes=-500）暂不支持，按从头开始处理。
        }
      }

      opened = await _resolve(target)(start, end);
      var result = opened;

      // 上游不给总长度时无法构造合法 Content-Range。关掉这次带 Range 的流，
      // 重新从 0 无 Range 拉；若仍拿不到长度，就退化为不带 Range 语义的
      // 200 顺序流（完整、从 0 开始），避免给 mpv 一个截断的 206。
      bool sequentialFallback = false;
      if (rangeHeader != null && result.totalLength == null) {
        await result.close?.call();
        opened = await _resolve(target)(null, null);
        result = opened;
        if (result.totalLength == null) sequentialFallback = true;
      }

      final int? effectiveStart = sequentialFallback ? null : start;
      final int? effectiveEnd = sequentialFallback ? null : end;
      var total = result.totalLength;
      if (total == null) {
        // 上游没给长度：补探一次，让 mpv 能算出时长并支持 seek。
        total = await _probeTotal(target).timeout(
          const Duration(seconds: 10),
          onTimeout: () => null,
        );
        if (total != null) {
          NetworkProxyLog.instance.write('total length probed=$total');
        }
      }

      // 上游忽略了 Range（返回完整文件、起点为 0）而客户端请求了非零起点：
      // 在代理侧真正跳过起点之前的字节，再按终点截断，得到合法 206。
      // 否则 mpv 拖动进度后会收到错位数据并报 loading failed。
      if (!sequentialFallback &&
          effectiveStart != null &&
          effectiveStart > 0 &&
          result.servedStart == 0) {
        int? servedEnd = effectiveEnd ??
            (total != null && total > 0 ? total - 1 : null);
        if (total != null && servedEnd != null && servedEnd > total - 1) {
          servedEnd = total - 1;
        }
        Stream<List<int>> stream = skipByteStream(result.bytes, effectiveStart);
        if (servedEnd != null && servedEnd >= effectiveStart) {
          stream = limitByteStream(stream, servedEnd - effectiveStart + 1);
        }
        result = RemoteStreamResult(
          bytes: stream,
          totalLength: total,
          servedStart: effectiveStart,
          servedEnd: servedEnd,
          contentType: result.contentType,
          close: result.close,
        );
      }

      var servedEnd = result.servedEnd;
      if (servedEnd == null && total != null && total > 0) {
        servedEnd = total - 1;
      }
      final isPartial =
          !sequentialFallback && rangeHeader != null && total != null;
      response.statusCode =
          isPartial ? HttpStatus.partialContent : HttpStatus.ok;
      response.headers.set(
        'Accept-Ranges',
        (isPartial || (total != null && !sequentialFallback))
            ? 'bytes'
            : 'none',
      );
      response.headers.set('Cache-Control', 'no-store');
      if (result.contentType != null) {
        try {
          response.headers.contentType = ContentType.parse(result.contentType!);
        } catch (_) {
          // 非法 Content-Type 交给 mpv 自己嗅探。
        }
      }
      int? declaredLength;
      if (total != null && servedEnd != null) {
        final length = servedEnd - result.servedStart + 1;
        if (length >= 0) {
          response.headers.contentLength = length;
          declaredLength = length;
        }
        if (isPartial) {
          response.headers.set(
            'Content-Range',
            'bytes ${result.servedStart}-$servedEnd/$total',
          );
        }
      } else if (total != null) {
        declaredLength = total - result.servedStart;
        response.headers.contentLength = declaredLength;
      }

      NetworkProxyLog.instance.write(
        'serve status=${response.statusCode} src=${target['s']} '
        'range=${rangeHeader ?? '-'} total=$total '
        'start=${result.servedStart} end=$servedEnd '
        'len=${declaredLength ?? '-'} '
        'ctype=${result.contentType}',
      );

      if (request.method == 'HEAD') {
        await response.close();
        await result.close?.call();
        opened = null;
        return;
      }

      try {
        // 统计实际发出的字节数：mpv 报
        // `http: Error reading HTTP response: Immediate exit requested` 时，
        // 到底是「上游中途断流」还是「播放器自己主动断开」，靠这两个数字
        // 就能一眼分开——前者 sent < expected，后者 sent 与 expected 无关。
        var sent = 0;
        await response.addStream(
          result.bytes.map((chunk) {
            sent += chunk.length;
            return chunk;
          }),
        );
        final expected = declaredLength;
        NetworkProxyLog.instance.write(
          'stream done sent=$sent expected=${expected ?? '-'} '
          '${expected != null && sent != expected ? '⚠ 上游提前结束' : ''}',
        );
      } catch (error) {
        NetworkProxyLog.instance.write(
          'stream aborted by client or upstream: $error',
        );
      } finally {
        await response.close();
        await result.close?.call();
        opened = null;
      }
    } catch (error, stack) {
      // 静默返回 502 会让 mpv 只报 loading failed，无法定位是鉴权、协议
      // 还是媒体标识的问题，这里写出诊断日志。
      NetworkProxyLog.instance.write(
        'proxy error ${request.method} ${request.uri} -> $error',
      );
      developer.log(
        '流代理请求失败：${request.method} ${request.uri} -> $error',
        name: 'MyuneStreamProxy',
        error: error,
        stackTrace: stack,
      );
      try {
        await opened?.close?.call();
      } catch (_) {}
      // 若响应头已经发出，statusCode 赋值会抛 HttpException，忽略即可。
      try {
        response.statusCode = HttpStatus.badGateway;
      } catch (_) {}
      try {
        await response.close();
      } catch (_) {}
    }
  }
}
