import 'dart:convert';
import 'dart:typed_data';

/// 从音频文件「头部若干 MB」里直接解析出的内嵌标签。
///
/// 存在的意义：网盘音频往往几十 MB，为了一个封面把整首歌下载下来不现实；
/// 而把截断的文件交给 Rust 的 lofty 解析器，又容易因为扩展名缺失、文件被
/// 截断、需要读音频属性等原因解析失败（59 MB 的 FLAC 就是典型例子）。
///
/// 主流格式的标签本来就在文件开头：FLAC 的 METADATA_BLOCK、MP3 的 ID3v2
/// 都集中在前几百 KB。这里用纯 Dart 按字节解析，不依赖文件扩展名、不要求
/// 文件完整、也不读音频帧，因此结果稳定可复现。lofty 仍作为其它格式
/// （M4A / OGG / APE 等）的补充，由 [NetworkTagReader] 合并两者的结果。
class NetworkHeaderTags {
  const NetworkHeaderTags({
    this.title,
    this.artist,
    this.album,
    this.genre,
    this.lyrics,
    this.cover,
    this.coverMime,
    this.durationMs,
    this.sampleRate,
    this.trackNumber,
    required this.format,
  });

  final String? title;
  final String? artist;
  final String? album;
  final String? genre;
  final String? lyrics;
  final Uint8List? cover;
  final String? coverMime;
  final int? durationMs;
  final int? sampleRate;
  final int? trackNumber;

  /// 命中的容器名，仅用于诊断日志，例如 `flac` / `id3v2.3`。
  final String format;

  bool get hasCover => cover != null && cover!.isNotEmpty;
  bool get hasLyrics => lyrics != null && lyrics!.trim().isNotEmpty;
  bool get hasAny =>
      (title != null && title!.trim().isNotEmpty) ||
      hasCover ||
      hasLyrics ||
      (artist != null && artist!.trim().isNotEmpty);
}

/// 无状态的头部标签解析器。
class NetworkHeaderTagParser {
  const NetworkHeaderTagParser._();

  /// 传入文件开头的字节（建议至少 2 MB）。识别不了返回 null。
  static NetworkHeaderTags? parse(Uint8List bytes) {
    if (bytes.length < 16) return null;
    if (_ascii(bytes, 0, 4) == 'fLaC') return _parseFlac(bytes);
    if (_ascii(bytes, 0, 3) == 'ID3') return _parseId3(bytes);
    return null;
  }

  // --- FLAC ---

  static NetworkHeaderTags? _parseFlac(Uint8List bytes) {
    String? title;
    String? artist;
    String? album;
    String? genre;
    String? lyrics;
    Uint8List? cover;
    String? coverMime;
    int? durationMs;
    int? sampleRate;
    int? trackNumber;

    var pos = 4;
    var blocks = 0;
    while (pos + 4 <= bytes.length && blocks < 64) {
      final header = bytes[pos];
      final last = (header & 0x80) != 0;
      final type = header & 0x7F;
      final length = _u24be(bytes, pos + 1);
      final start = pos + 4;
      final end = start + length;
      if (end > bytes.length) break; // 块被截断，不再往后猜
      final body = Uint8List.sublistView(bytes, start, end);

      if (type == 0 && body.length >= 18) {
        // STREAMINFO：20 bit 采样率 + 36 bit 总采样数，可算出精确时长。
        sampleRate =
            (body[10] << 12) | (body[11] << 4) | (body[12] >> 4);
        final totalSamples = ((body[13] & 0x0F) << 32) |
            (body[14] << 24) |
            (body[15] << 16) |
            (body[16] << 8) |
            body[17];
        if (sampleRate! > 0 && totalSamples > 0) {
          durationMs = (totalSamples * 1000 ~/ sampleRate!);
        }
      } else if (type == 4) {
        // VORBIS_COMMENT（小端，UTF-8 的 KEY=VALUE 列表）
        var p = 0;
        if (body.length >= 4) {
          final vendorLen = _u32le(body, p);
          p += 4 + vendorLen;
        }
        if (p + 4 <= body.length) {
          final count = _u32le(body, p);
          p += 4;
          for (var i = 0; i < count && p + 4 <= body.length; i++) {
            final itemLen = _u32le(body, p);
            p += 4;
            if (p + itemLen > body.length) break;
            final raw = utf8.decode(
              Uint8List.sublistView(body, p, p + itemLen),
              allowMalformed: true,
            );
            p += itemLen;
            final eq = raw.indexOf('=');
            if (eq <= 0) continue;
            final key = raw.substring(0, eq).toUpperCase().trim();
            final value = raw.substring(eq + 1).trim();
            if (value.isEmpty) continue;
            if (key == 'TITLE') {
              title ??= value;
            } else if (key == 'ARTIST' || key == 'ALBUMARTIST') {
              artist ??= value;
            } else if (key == 'ALBUM') {
              album ??= value;
            } else if (key == 'GENRE') {
              genre ??= value;
            } else if (key == 'TRACKNUMBER') {
              trackNumber ??= _leadingInt(value);
            } else if (key == 'LYRICS' ||
                key == 'UNSYNCEDLYRICS' ||
                key == 'UNSYNCED LYRICS') {
              lyrics ??= value;
            }
          }
        }
      } else if (type == 6 && cover == null) {
        // PICTURE（大端）：type / mime / desc / 宽高色深 / 图片数据
        var p = 0;
        if (body.length >= 8) {
          p += 4; // picture type
          final mimeLen = _u32be(body, p);
          p += 4;
          if (p + mimeLen <= body.length) {
            coverMime = _ascii(body, p, mimeLen).toLowerCase();
            p += mimeLen;
            if (p + 4 <= body.length) {
              final descLen = _u32be(body, p);
              p += 4 + descLen + 16; // desc + width/height/depth/colors
              if (p + 4 <= body.length) {
                final dataLen = _u32be(body, p);
                p += 4;
                if (p + dataLen <= body.length && dataLen > 0) {
                  cover = Uint8List.sublistView(body, p, p + dataLen);
                }
              }
            }
          }
        }
      }

      pos = end;
      blocks++;
      if (last) break;
    }

    return NetworkHeaderTags(
      title: _clean(title),
      artist: _clean(artist),
      album: _clean(album),
      genre: _clean(genre),
      lyrics: _clean(lyrics),
      cover: cover,
      coverMime: coverMime,
      durationMs: durationMs,
      sampleRate: sampleRate,
      trackNumber: trackNumber,
      format: 'flac',
    );
  }

  // --- ID3v2 ---

  static NetworkHeaderTags? _parseId3(Uint8List bytes) {
    final major = bytes[3];
    final tagSize = _syncSafe(bytes, 6);
    final tagEnd = 10 + tagSize > bytes.length ? bytes.length : 10 + tagSize;
    if (tagEnd <= 10) return null;
    final shortId = major == 2;

    String? title;
    String? artist;
    String? album;
    String? genre;
    String? lyrics;
    Uint8List? cover;
    String? coverMime;
    int? trackNumber;

    var pos = 10;
    while (pos + (shortId ? 6 : 10) <= tagEnd) {
      final idLen = shortId ? 3 : 4;
      final id = _ascii(bytes, pos, idLen);
      // 到了标签尾部填充区（全 0）就停止，避免把 padding 误读成帧。
      if (!RegExp(r'^[A-Z0-9]{3,4}$').hasMatch(id)) break;
      final sizeLen = shortId ? 3 : 4;
      final size = shortId
          ? _u24be(bytes, pos + idLen)
          : (major == 4
              ? _syncSafe(bytes, pos + idLen)
              : _u32be(bytes, pos + idLen));
      final bodyStart = pos + idLen + sizeLen + (shortId ? 0 : 2);
      final bodyEnd = bodyStart + size;
      if (size <= 0 || bodyEnd > tagEnd || bodyStart >= tagEnd) break;
      final body = Uint8List.sublistView(bytes, bodyStart, bodyEnd);
      pos = bodyEnd;

      if (id == 'TIT2' || id == 'TT2') {
        title ??= _id3Text(body);
      } else if (id == 'TPE1' || id == 'TP1') {
        artist ??= _id3Text(body);
      } else if (id == 'TALB' || id == 'TAL') {
        album ??= _id3Text(body);
      } else if (id == 'TCON' || id == 'TCO') {
        genre ??= _id3Text(body);
      } else if (id == 'TRCK' || id == 'TRK') {
        trackNumber ??= _leadingInt(_id3Text(body) ?? '');
      } else if (id == 'USLT' || id == 'ULT') {
        lyrics ??= _id3Lyrics(body);
      } else if ((id == 'APIC' || id == 'PIC') && cover == null) {
        final pic = _id3Picture(body, shortId);
        cover = pic?.bytes;
        coverMime = pic?.mime;
      }
    }

    return NetworkHeaderTags(
      title: _clean(title),
      artist: _clean(artist),
      album: _clean(album),
      genre: _clean(genre),
      lyrics: _clean(lyrics),
      cover: cover,
      coverMime: coverMime,
      format: 'id3v2.$major',
    );
  }

  static String? _id3Text(Uint8List body) {
    if (body.isEmpty) return null;
    final encoding = body[0];
    final text = _decodeId3(body, 1, body.length - 1, encoding);
    return text.isEmpty ? null : text;
  }

  static String? _id3Lyrics(Uint8List body) {
    if (body.length < 5) return null;
    final encoding = body[0];
    // 3 字节语言 + 以 encoding 对应的 0 结尾的描述
    var p = 4;
    final descEnd = _findTerminator(body, p, encoding);
    if (descEnd < 0) return null;
    p = descEnd + (encoding == 1 || encoding == 2 ? 2 : 1);
    if (p >= body.length) return null;
    final text = _decodeId3(body, p, body.length - p, encoding);
    return text.isEmpty ? null : text;
  }

  static _Id3Picture? _id3Picture(Uint8List body, bool shortId) {
    if (body.length < 6) return null;
    final encoding = body[0];
    var p = 1;
    String mime;
    if (shortId) {
      // ID3v2.2 的 PIC：3 字节图片格式标记（"JPG" / "PNG"）
      final format = _ascii(body, p, 3).toUpperCase();
      p += 3;
      mime = format == 'PNG' ? 'image/png' : 'image/jpeg';
    } else {
      final mimeEnd = _findZero(body, p, 1);
      if (mimeEnd < 0) return null;
      mime = _ascii(body, p, mimeEnd - p).toLowerCase();
      p = mimeEnd + 1;
    }
    if (p >= body.length) return null;
    p++; // picture type
    final descEnd = _findTerminator(body, p, encoding);
    if (descEnd < 0) return null;
    p = descEnd + (encoding == 1 || encoding == 2 ? 2 : 1);
    if (p >= body.length) return null;
    return _Id3Picture(
      Uint8List.sublistView(body, p, body.length),
      mime,
    );
  }

  static int _findZero(Uint8List bytes, int start, int step) {
    for (var i = start; i < bytes.length; i += step) {
      if (bytes[i] == 0) return i;
    }
    return -1;
  }

  static int _findTerminator(Uint8List bytes, int start, int encoding) {
    if (encoding == 1 || encoding == 2) {
      for (var i = start; i + 1 < bytes.length; i += 2) {
        if (bytes[i] == 0 && bytes[i + 1] == 0) return i;
      }
      return -1;
    }
    return _findZero(bytes, start, 1);
  }

  static String _decodeId3(
    Uint8List bytes,
    int start,
    int length,
    int encoding,
  ) {
    if (length <= 0) return '';
    final slice = Uint8List.sublistView(bytes, start, start + length);
    switch (encoding) {
      case 3:
        return utf8.decode(slice, allowMalformed: true).trim();
      case 1:
      case 2:
        return _decodeUtf16(slice, encoding == 1).trim();
      default:
        return latin1.decode(slice, allowInvalid: true).trim();
    }
  }

  static String _decodeUtf16(Uint8List bytes, bool bom) {
    var little = true;
    var start = 0;
    if (bom && bytes.length >= 2) {
      if (bytes[0] == 0xFE && bytes[1] == 0xFF) {
        little = false;
        start = 2;
      } else if (bytes[0] == 0xFF && bytes[1] == 0xFE) {
        start = 2;
      }
    } else if (!bom) {
      little = false;
    }
    final units = <int>[];
    for (var i = start; i + 1 < bytes.length; i += 2) {
      final unit = little
          ? (bytes[i] | (bytes[i + 1] << 8))
          : ((bytes[i] << 8) | bytes[i + 1]);
      if (unit == 0) break;
      units.add(unit);
    }
    return String.fromCharCodes(units);
  }

  // --- 通用小工具 ---

  static int _u24be(Uint8List b, int o) =>
      (b[o] << 16) | (b[o + 1] << 8) | b[o + 2];

  static int _u32be(Uint8List b, int o) =>
      (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

  static int _u32le(Uint8List b, int o) =>
      b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);

  static int _syncSafe(Uint8List b, int o) =>
      ((b[o] & 0x7F) << 21) |
      ((b[o + 1] & 0x7F) << 14) |
      ((b[o + 2] & 0x7F) << 7) |
      (b[o + 3] & 0x7F);

  static String _ascii(Uint8List b, int start, int length) {
    final end = start + length > b.length ? b.length : start + length;
    if (end <= start) return '';
    return latin1.decode(
      Uint8List.sublistView(b, start, end),
      allowInvalid: true,
    );
  }

  static int? _leadingInt(String value) {
    final head = value.split('/').first.trim();
    return int.tryParse(head);
  }

  static String? _clean(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

class _Id3Picture {
  const _Id3Picture(this.bytes, this.mime);

  final Uint8List bytes;
  final String mime;
}
