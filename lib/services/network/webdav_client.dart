import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'remote_entry.dart';
import 'remote_source.dart';
import 'remote_stream.dart';

/// 极简 WebDAV 客户端：PROPFIND 列目录 + GET（支持 Range）读文件。
///
/// 只依赖已有的 `http` 包，不引入 xml/webdav 依赖；PROPFIND 响应用带命名空间
/// 通配的正则解析，兼容 `d:` / `D:` / 默认命名空间以及各厂商 NAS 的实现。
class WebDavClient {
  WebDavClient(this.source);

  final RemoteSource source;

  static final RegExp _responseRe = RegExp(
    r'<(?:[\w.\-]+:)?response\b[^>]*>([\s\S]*?)</(?:[\w.\-]+:)?response>',
    caseSensitive: false,
  );
  static final RegExp _hrefRe = RegExp(
    r'<(?:[\w.\-]+:)?href\b[^>]*>([\s\S]*?)</(?:[\w.\-]+:)?href>',
    caseSensitive: false,
  );
  // 兼容 `<d:resourcetype>...</d:resourcetype>` 包裹（含属性、换行、多行）。
  static final RegExp _resourceTypeRe = RegExp(
    r'<(?:[\w.\-]+:)?resourcetype\b[^>]*>([\s\S]*?)</(?:[\w.\-]+:)?resourcetype>',
    caseSensitive: false,
  );
  // 只匹配开标签：兼容 `<d:collection/>`、`<D:collection></D:collection>`、
  // `<d:collection xmlns:d="DAV:"/>`、`<collection />` 以及带任意属性的形式。
  static final RegExp _collectionTagRe = RegExp(
    r'<(?:[\w.\-]+:)?collection\b',
    caseSensitive: false,
  );
  static final RegExp _lengthRe = RegExp(
    r'<(?:[\w.\-]+:)?getcontentlength\b[^>]*>([\s\S]*?)</(?:[\w.\-]+:)?getcontentlength>',
    caseSensitive: false,
  );
  static final RegExp _modifiedRe = RegExp(
    r'<(?:[\w.\-]+:)?getlastmodified\b[^>]*>([\s\S]*?)</(?:[\w.\-]+:)?getlastmodified>',
    caseSensitive: false,
  );
  static final RegExp _displayNameRe = RegExp(
    r'<(?:[\w.\-]+:)?displayname\b[^>]*>([\s\S]*?)</(?:[\w.\-]+:)?displayname>',
    caseSensitive: false,
  );

  static const String _propfindBody =
      '<?xml version="1.0" encoding="utf-8"?>'
      '<d:propfind xmlns:d="DAV:">'
      '<d:prop><d:resourcetype/><d:getcontentlength/>'
      '<d:getlastmodified/><d:displayname/></d:prop></d:propfind>';

  Map<String, String> get _authHeaders {
    final headers = <String, String>{
      'User-Agent': 'MyuneMusic/1.0 (Desktop)',
      'Accept': '*/*',
    };
    if (source.username.trim().isNotEmpty) {
      final token = base64Encode(
        utf8.encode('${source.username}:${source.password}'),
      );
      headers['Authorization'] = 'Basic $token';
    }
    return headers;
  }

  Uri uriFor(String href) {
    final base = source.webdavBaseUri;
    final candidate = href.trim();
    if (candidate.isEmpty) return base;
    Uri? parsed;
    try {
      parsed = Uri.parse(candidate);
    } catch (_) {
      parsed = null;
    }
    if (parsed != null && parsed.hasScheme && parsed.hasAuthority) {
      return parsed;
    }
    return base.resolve(candidate);
  }

  /// 列出 [href] 目录的直属子项。首次进入时传空字符串表示配置里的根目录。
  Future<List<RemoteEntry>> list(String href) async {
    final client = http.Client();
    try {
      final target = uriFor(href);
      final request = http.Request('PROPFIND', target)
        ..headers.addAll(_authHeaders)
        ..headers['Depth'] = '1'
        ..headers['Content-Type'] = 'application/xml; charset=utf-8'
        ..body = _propfindBody;
      final response = await client.send(request).timeout(
            const Duration(seconds: 20),
          );
      final body = await response.stream.bytesToString().timeout(
            const Duration(seconds: 30),
          );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'WebDAV PROPFIND 失败（HTTP ${response.statusCode}）：'
          '${_shortBody(body)}',
        );
      }
      return _parsePropfind(body, target);
    } finally {
      client.close();
    }
  }

  /// 打开一个远端文件。start/end 是闭区间，null 表示从头 / 到尾。
  ///
  /// [headerTimeout] 只约束「拿到响应头」这一段：自建的「网盘 → WebDAV」
  /// 桥在开始推流前往往要先向网盘申请下载地址，首包可能要好几十秒。
  /// 这个值必须小于播放器自己的网络超时（mpv 默认 60 秒），否则播放器
  /// 会先放弃，表现为 `loading failed` / `Immediate exit requested`。
  Future<RemoteStreamResult> open(
    String href, {
    int? start,
    int? end,
    Duration headerTimeout = const Duration(seconds: 25),
  }) async {
    final client = http.Client();
    try {
      final target = uriFor(href);
      final request = http.Request('GET', target)
        ..headers.addAll(_authHeaders);
      final range = formatRangeHeader(start, end);
      if (range.isNotEmpty) request.headers['Range'] = range;
      final response = await client.send(request).timeout(headerTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.stream.drain<void>();
        throw Exception('WebDAV GET 失败（HTTP ${response.statusCode}）');
      }

      final info = describeHttpRange(
        contentRange: response.headers['content-range'],
        contentLength: response.contentLength,
        requestedStart: start,
        requestedEnd: end,
        // 上游是否真的返回了 206。忽略 Range 时代理会自行跳过起点字节。
        upstreamPartial: response.statusCode == 206,
      );

      return RemoteStreamResult(
        bytes: limitByteStream(response.stream, info.limit),
        totalLength: info.totalLength,
        servedStart: info.servedStart,
        servedEnd: info.servedEnd,
        contentType: response.headers['content-type'] ??
            guessContentType(remoteEntryName(href, isDirectory: false)),
        close: () async {
          client.close();
        },
      );
    } catch (_) {
      client.close();
      rethrow;
    }
  }

  /// 只取响应头探测一个远端文件，不下载正文。
  ///
  /// 用于「诊断」与「长度补全」：服务端若支持 Range 会返回 206 与
  /// `Content-Range`，从中可直接得到真实总长度；若忽略 Range 则返回 200，
  /// 此时用 `Content-Length` 兜底，并标记为不支持 Range。
  ///
  /// [start] / [end] 可以指定探测的区间：诊断时用「文件中部的一个字节」
  /// 来模拟拖动进度时的 seek，能直接看出上游 seek 是否可用、有多慢。
  Future<RemoteProbeResult> probe(
    String href, {
    int? start,
    int? end,
  }) async {
    final client = http.Client();
    final stopwatch = Stopwatch()..start();
    final from = start ?? 0;
    final to = end ?? (start == null ? 0 : start);
    try {
      final target = uriFor(href);
      final request = http.Request('GET', target)
        ..headers.addAll(_authHeaders)
        ..headers['Range'] = 'bytes=$from-$to';
      final response = await client.send(request).timeout(
            const Duration(seconds: 20),
          );
      stopwatch.stop();
      final contentRange = response.headers['content-range'];
      final contentType = response.headers['content-type'];
      int? total;
      var supportsRange = false;
      if (response.statusCode == 206) {
        supportsRange = true;
        final match = RegExp(
          r'bytes\s+(\d+)-(\d+)/(\d+|\*)',
          caseSensitive: false,
        ).firstMatch(contentRange ?? '');
        final totalText = match?.group(3);
        if (totalText != null && totalText != '*') {
          total = int.tryParse(totalText);
        }
      } else if (response.statusCode >= 200 && response.statusCode < 300) {
        final length = response.contentLength;
        if (length != null && length >= 0) total = length;
      }
      final ok = response.statusCode >= 200 && response.statusCode < 300;
      return RemoteProbeResult(
        ok: ok,
        statusCode: response.statusCode,
        elapsedMs: stopwatch.elapsedMilliseconds,
        totalLength: total,
        supportsRange: supportsRange,
        contentType: contentType,
        message: ok ? '' : _shortError(response.statusCode, contentRange),
      );
    } catch (error) {
      stopwatch.stop();
      return RemoteProbeResult(
        ok: false,
        statusCode: 0,
        elapsedMs: stopwatch.elapsedMilliseconds,
        message: '$error',
      );
    } finally {
      // 探测阶段不读正文，直接断开，避免把整个文件拉下来。
      client.close();
    }
  }

  /// 只取总长度，供代理在「上游不给长度」时补全 Content-Length。
  Future<int?> contentLength(String href) async {
    final result = await probe(href);
    return result.totalLength;
  }

  String _shortError(int statusCode, String? contentRange) {
    switch (statusCode) {
      case 401:
        return '鉴权失败（HTTP 401），请检查用户名 / 密码';
      case 403:
        return '无访问权限（HTTP 403）';
      case 404:
        return '文件不存在（HTTP 404），路径可能已变更';
      case 405:
        return '服务端不接受该请求方法（HTTP 405）';
      case 500:
      case 502:
      case 503:
      case 504:
        return '服务端异常（HTTP $statusCode），可能是上游网盘限流或超时';
      default:
        return 'HTTP $statusCode${contentRange == null ? '' : '（$contentRange）'}';
    }
  }

  /// 判断一个 `<response>` 块是否代表目录。
  ///
  /// 老版本只认 `<d:collection/>` 自闭合标签，导致群晖 / Nextcloud / 绿联 /
  /// 极空间等 NAS 返回的 `<D:collection></D:collection>`、带命名空间属性或
  /// 大写前缀形式被误判成「无后缀文件」，目录无法进入。这里先看
  /// resourcetype 块，再用 href 尾部斜杠兜底。
  bool _isCollection(String block, bool hrefEndsWithSlash) {
    final rt = _resourceTypeRe.firstMatch(block);
    if (rt != null) {
      return _collectionTagRe.hasMatch(rt.group(1) ?? '');
    }
    if (_collectionTagRe.hasMatch(block)) return true;
    return hrefEndsWithSlash;
  }

  List<RemoteEntry> _parsePropfind(String body, Uri requestedDir) {
    final entries = <RemoteEntry>[];
    final seen = <String>{};
    final requestedPath = _decodePath(requestedDir.path);

    for (final match in _responseRe.allMatches(body)) {
      final block = match.group(1) ?? '';
      final hrefMatch = _hrefRe.firstMatch(block);
      if (hrefMatch == null) continue;
      final rawHref = xmlUnescape(hrefMatch.group(1) ?? '').trim();
      if (rawHref.isEmpty) continue;

      // 把 href 统一解析成绝对 URL 再存进 RemoteEntry.path：
      // 1) 支持服务端返回相对 href；
      // 2) 进入子目录后再次 GET / PROPFIND 不会错误地相对「配置根目录」解析，
      //    这是之前 WebDAV 子目录里的文件播放报 loading failed 的根因之一。
      // 部分 NAS 会返回未编码的中文 href，Uri.resolve 会抛 FormatException，
      // 这里退化成 encodeFull 再解析，避免整个目录列举失败。
      Uri absolute;
      try {
        absolute = requestedDir.resolve(rawHref);
      } catch (_) {
        try {
          absolute = requestedDir.resolve(Uri.encodeFull(rawHref));
        } catch (_) {
          continue;
        }
      }
      final absoluteHref = absolute.toString();
      final hrefEndsWithSlash = absolute.path.endsWith('/');
      final isDirectory = _isCollection(block, hrefEndsWithSlash);

      // PROPFIND Depth:1 会把自己也返回，跳过目录自身。比较时用解码后的
      // 路径，兼容服务端 href 与本地请求一个编码、一个不编码的情况。
      final selfPath = _decodePath(absolute.path);
      if (selfPath == requestedPath) continue;
      if (!seen.add(absoluteHref)) continue;

      final lengthMatch = _lengthRe.firstMatch(block);
      final modifiedMatch = _modifiedRe.firstMatch(block);
      final displayMatch = _displayNameRe.firstMatch(block);
      int? size;
      if (lengthMatch != null) {
        size = int.tryParse((lengthMatch.group(1) ?? '').trim());
      }
      DateTime? modified;
      if (modifiedMatch != null) {
        modified = DateTime.tryParse((modifiedMatch.group(1) ?? '').trim());
      }
      var name = remoteEntryName(absolute.path, isDirectory: isDirectory);
      if (displayMatch != null) {
        final display = xmlUnescape(displayMatch.group(1) ?? '').trim();
        if (display.isNotEmpty) name = display;
      }

      entries.add(
        RemoteEntry(
          name: name,
          path: absoluteHref,
          isDirectory: isDirectory,
          size: isDirectory ? null : size,
          modified: modified,
        ),
      );
    }

    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }

  String _decodePath(String path) {
    var decoded = path;
    try {
      decoded = Uri.decodeComponent(decoded);
    } catch (_) {
      // 非法百分号编码时保留原值。
    }
    return decoded.replaceAll(RegExp(r'/+$'), '');
  }

  /// 把 PROPFIND / GET 的正文压成一行可读的错误说明。
  String _shortBody(String body) {
    final plain = body.replaceAll(RegExp(r'<[^>]+>'), ' ').trim();
    if (plain.isEmpty) return '服务端未返回正文';
    return plain.length > 120 ? '${plain.substring(0, 120)}…' : plain;
  }
}
