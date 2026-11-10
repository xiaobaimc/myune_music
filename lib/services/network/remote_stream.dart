import 'dart:async';

import 'remote_entry.dart';

/// 代理转发一段远端字节流时的描述信息。
///
/// [totalLength] 是整个资源的长度（未知时为 null），[servedStart] /
/// [servedEnd] 是本次实际返回的区间（闭区间，servedEnd 为 null 表示到文件尾）。
/// 本机代理据此生成 200/206、Content-Length 与 Content-Range，mpv/FFmpeg
/// 才能对网络流做拖动进度。
class RemoteStreamResult {
  const RemoteStreamResult({
    required this.bytes,
    this.totalLength,
    this.servedStart = 0,
    this.servedEnd,
    this.contentType,
    this.close,
  });

  final Stream<List<int>> bytes;
  final int? totalLength;
  final int servedStart;
  final int? servedEnd;
  final String? contentType;
  final Future<void> Function()? close;
}

typedef RemoteStreamOpener =
    Future<RemoteStreamResult> Function(int? start, int? end);

/// 把上游字节流截断到最多 [limit] 字节。用于 FTP：FTP 没有「只取前 N 字节」
/// 的语义，REST + RETR 会一直发到文件尾，需要本地限速后才能正确响应
/// `Range: bytes=a-b`。达到上限后 `break` 会取消订阅，由调用方关闭套接字。
Stream<List<int>> limitByteStream(Stream<List<int>> source, int? limit) async* {
  if (limit == null) {
    yield* source;
    return;
  }
  var remaining = limit;
  await for (final chunk in source) {
    if (remaining <= 0) break;
    if (chunk.length <= remaining) {
      yield chunk;
      remaining -= chunk.length;
    } else {
      yield chunk.sublist(0, remaining);
      remaining = 0;
    }
  }
}

/// HTTP 上游响应的 Range 描述，供 WebDAV / B 站 CDN 两条链路共用，
/// 避免 200/206、Content-Length、Content-Range 的推导出现分叉。
class RemoteRangeInfo {
  const RemoteRangeInfo({
    required this.totalLength,
    required this.servedStart,
    required this.servedEnd,
    required this.limit,
  });

  final int? totalLength;
  final int servedStart;
  final int? servedEnd;
  final int? limit;
}

RemoteRangeInfo describeHttpRange({
  required String? contentRange,
  required int? contentLength,
  required int? requestedStart,
  required int? requestedEnd,
  bool upstreamPartial = false,
}) {
  var servedStart = requestedStart ?? 0;
  int? servedEnd = requestedEnd;
  int? total;
  final match = contentRange == null
      ? null
      : RegExp(
          r'bytes\s+(\d+)-(\d+)/(\d+|\*)',
          caseSensitive: false,
        ).firstMatch(contentRange);
  if (match != null) {
    servedStart = int.tryParse(match.group(1)!) ?? servedStart;
    servedEnd = int.tryParse(match.group(2)!);
    final totalText = match.group(3)!;
    total = totalText == '*' ? null : int.tryParse(totalText);
  } else if (upstreamPartial && (requestedStart ?? 0) > 0) {
    // 上游返回 206 却没有 Content-Range：数据确实按请求起点返回，
    // 但总长度未知。让代理回退到顺序流 + 本地跳过起点。
    servedStart = requestedStart ?? 0;
    servedEnd = requestedEnd;
    total = null;
  } else {
    // 上游忽略了 Range，退回 200：上游字节流从 0 开始，按请求终点截断。
    // `_handle` 会检测到 servedStart==0 且请求起点>0，在代理侧跳过起点字节。
    total = (contentLength != null && contentLength >= 0) ? contentLength : null;
    servedStart = 0;
    servedEnd = requestedEnd ?? (total != null && total > 0 ? total - 1 : null);
  }

  int? limit;
  if (servedEnd != null) {
    final count = servedEnd - servedStart + 1;
    limit = count > 0 ? count : 0;
  } else if (total != null) {
    limit = total - servedStart;
  }
  return RemoteRangeInfo(
    totalLength: total,
    servedStart: servedStart,
    servedEnd: servedEnd,
    limit: limit,
  );
}

/// 丢弃上游流的前 [skip] 个字节后转发。
///
/// 某些 WebDAV / FTP / NAS 服务端会忽略 `Range` 直接返回 200 完整文件。
/// 此时代理不能把「从 0 开始」的字节谎报成 206 的指定区间，否则 mpv
/// 在拖动进度后会拿到错位数据并报 loading failed。用这个流在代理侧真正
/// 跳过起点之前的字节，就能在没有上游 Range 支持的情况下给出合法 206。
Stream<List<int>> skipByteStream(Stream<List<int>> source, int skip) async* {
  var remaining = skip;
  await for (final chunk in source) {
    if (remaining <= 0) {
      yield chunk;
      continue;
    }
    if (chunk.length <= remaining) {
      remaining -= chunk.length;
      continue;
    }
    yield chunk.sublist(remaining);
    remaining = 0;
  }
}

/// 把代理侧解析出的 Range 请求写成 `bytes=a-b` 形式。
String formatRangeHeader(int? start, int? end) {
  if (start == null && end == null) return '';
  return 'bytes=${start ?? 0}-${end ?? ''}';
}

/// 按文件名推断 Content-Type。mpv 主要靠内容嗅探，这里给一个合理默认值，
/// 让 FFmpeg 在探测阶段少走弯路；视频容器也返回 video/*，mpv 只出声。
String guessContentType(String name) {
  final ext = RemoteEntry.extensionOf(name);
  if (ext.isEmpty) return 'application/octet-stream';
  if (RemoteEntry.isAudioName(name)) {
    switch (ext) {
      case 'mp3':
      case 'mp2':
      case 'mp1':
      case 'mpa':
      case 'mpga':
      case 'm1a':
      case 'm2a':
        return 'audio/mpeg';
      case 'flac':
        return 'audio/flac';
      case 'wav':
      case 'wave':
      case 'pcm':
      case 'adpcm':
      case 'cdda':
        return 'audio/wav';
      case 'aiff':
      case 'aif':
      case 'aifc':
      case 'iff':
      case '8svx':
      case 'au':
      case 'snd':
        return 'audio/aiff';
      case 'caf':
        return 'audio/x-caf';
      case 'm4a':
      case 'm4b':
      case 'm4r':
      case 'mp4a':
      case 'alac':
      case 'aax':
      case 'aa':
        return 'audio/mp4';
      case 'aac':
      case 'adts':
        return 'audio/aac';
      case 'ogg':
      case 'oga':
      case 'spx':
      case 'celt':
        return 'audio/ogg';
      case 'opus':
        return 'audio/ogg; codecs=opus';
      case 'wma':
      case 'asf':
        return 'audio/x-ms-wma';
      case 'ape':
        return 'audio/x-ape';
      case 'wv':
      case 'wavpack':
        return 'audio/x-wavpack';
      case 'tta':
        return 'audio/x-tta';
      case 'tak':
        return 'audio/x-tak';
      case 'dsf':
      case 'dff':
      case 'dsd':
        return 'audio/x-dsd';
      case 'mpc':
      case 'mp+':
        return 'audio/x-musepack';
      case 'ac3':
      case 'eac3':
      case 'ac4':
        return 'audio/ac3';
      case 'dts':
      case 'dtshd':
        return 'audio/dts';
      case 'mid':
      case 'midi':
      case 'kar':
      case 'rmi':
        return 'audio/midi';
      case 'amr':
      case '3ga':
        return 'audio/amr';
      case 'ra':
      case 'ram':
        return 'audio/x-pn-realaudio';
      default:
        // 无法给出更精确类型时交给 FFmpeg 内容嗅探，避免发送 audio/* 这类
        // 不适合作为响应头的通配 MIME。
        return 'application/octet-stream';
    }
  }
  if (RemoteEntry.isVideoName(name)) {
    switch (ext) {
      case 'mp4':
      case 'm4v':
      case 'm4p':
      case 'mov':
      case 'qt':
      case '3gp':
      case '3g2':
        return 'video/mp4';
      case 'mkv':
      case 'webm':
        return 'video/webm';
      case 'avi':
      case 'divx':
      case 'xvid':
        return 'video/x-msvideo';
      case 'wmv':
        return 'video/x-ms-wmv';
      case 'flv':
      case 'f4v':
        return 'video/x-flv';
      case 'mpg':
      case 'mpeg':
      case 'mpe':
      case 'm2v':
      case 'vob':
        return 'video/mpeg';
      case 'ts':
      case 'm2ts':
      case 'mts':
        return 'video/mp2t';
      case 'rm':
      case 'rmvb':
        return 'video/x-pn-realvideo';
      default:
        return 'application/octet-stream';
    }
  }
  return 'application/octet-stream';
}

/// 极简 XML 文本反转义，只覆盖 WebDAV PROPFIND 的 href / displayname 会用到的实体。
String xmlUnescape(String value) {
  return value
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');
}

/// 解码 PROPFIND 的 href，得到用于显示的文件名。
String remoteEntryName(String href, {required bool isDirectory}) {
  var decoded = href.trim();
  try {
    decoded = Uri.decodeComponent(decoded);
  } catch (_) {
    // href 里出现非法百分号编码时保留原值。
  }
  decoded = xmlUnescape(decoded);
  final trimmed = decoded.replaceAll(RegExp(r'/+$'), '');
  final slash = trimmed.lastIndexOf('/');
  final name = slash >= 0 ? trimmed.substring(slash + 1) : trimmed;
  if (name.isNotEmpty) return name;
  return isDirectory ? '目录' : '文件';
}
