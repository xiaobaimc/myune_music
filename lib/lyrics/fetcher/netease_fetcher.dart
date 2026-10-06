// 参考 https://github.com/WisteriaZy/lyricGeter/tree/master/fetcher/netease.py

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../decryptor/eapi_decryptor.dart';
import '../parser/parsed_models.dart';
import '../parser/yrc_parser.dart';

class NeteaseFetcher {
  static const _baseUrl = 'https://music.163.com';

  static const _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    'Referer': 'https://music.163.com/',
    'Content-Type': 'application/x-www-form-urlencoded',
  };

  final _yrcParser = YrcParser();

  // 把 YRC 的逐字时间轴贴回 LRC 行时，向前看几行
  static const int _wordLookaheadLines = 4;

  // 没匹配上的逐字行落后多少毫秒就丢弃
  static const int _lineOffsetToleranceMs = 1000;

  // 文本对不上时，允许的行起始偏差
  static const int _lineMatchToleranceMs = 60;

  // 搜索歌曲并获取歌词 同时附带歌曲 ID（用于 AMLL 查询）
  Future<({ParsedLyrics? lyrics, int? songId})> search(
    String title,
    String artist,
  ) async {
    // 搜索歌曲
    final songInfo = await _searchSong(title, artist);
    if (songInfo == null) return (lyrics: null, songId: null);

    // 获取歌词
    final lyrics = await _getLyrics(songInfo['id'] as int);
    return (lyrics: lyrics, songId: songInfo['id'] as int);
  }

  // 搜索歌曲，返回第一个匹配结果的
  Future<Map<String, dynamic>?> _searchSong(String title, String artist) async {
    const path = '/api/cloudsearch/pc';
    final query = '$title $artist'.trim();

    final params = {'s': query, 'type': 1, 'offset': 0, 'limit': 10};

    final encrypted = EapiDecryptor.encryptParams(path, params);

    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/eapi/cloudsearch/pc'),
            headers: _headers,
            body: encrypted,
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final data =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (data['code'] != 200) return null;

      final result = data['result'] as Map<String, dynamic>? ?? {};
      final songs = result['songs'] as List<dynamic>? ?? [];
      if (songs.isEmpty) return null;

      // 优先原版，匹配歌手名，过滤片段/翻唱
      int scoreSong(Map<String, dynamic> song) {
        final name = song['name'] as String? ?? '';
        final artistsList = song['ar'] as List<dynamic>? ?? [];
        final singer = artistsList
            .map((a) => (a as Map<String, dynamic>)['name'] ?? '')
            .join(' ');
        var score = 0;
        if (artist.isNotEmpty &&
            singer.toLowerCase().contains(artist.toLowerCase())) {
          score += 1000;
        }
        if (name.contains('片段')) score -= 500;
        if (name.contains('原唱') || name.contains('翻唱')) score -= 300;
        final lower = name.toLowerCase();
        if (lower.contains('sped up') ||
            lower.contains('slowed') ||
            lower.contains('remix')) {
          score -= 200;
        }
        return score;
      }

      final sortedSongs = songs.cast<Map<String, dynamic>>().toList()
        ..sort((a, b) => scoreSong(b).compareTo(scoreSong(a)));
      final first = sortedSongs.first;

      final artists = first['ar'] as List<dynamic>? ?? [];
      final artistNames = artists
          .map((a) => (a as Map<String, dynamic>)['name'] ?? '')
          .join(', ');

      return {
        'id': first['id'] as int,
        'title': first['name'] ?? '',
        'artist': artistNames,
        'duration_ms': (first['dt'] as int?) ?? 0,
      };
    } catch (_) {
      return null;
    }
  }

  // 获取歌词（逐字原文用 YRC，翻译用 tlyric，罗马音用 romalrc）
  Future<ParsedLyrics?> _getLyrics(int songId) async {
    const path = '/api/song/lyric/v1';

    final params = {
      'id': songId,
      'lv': -1, // 普通歌词版本
      'tv': -1, // 翻译版本（tlyric）
      'rv': -1, // 罗马音版本（romalrc）
      'yv': -1, // YRC 逐字版本
    };

    final encrypted = EapiDecryptor.encryptParams(path, params);

    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/eapi/song/lyric/v1'),
            headers: _headers,
            body: encrypted,
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final data =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (data['code'] != 200) return null;

      final yrcData = data['yrc'] as Map<String, dynamic>? ?? {};
      final lrcData = data['lrc'] as Map<String, dynamic>? ?? {};
      final tlyricData = data['tlyric'] as Map<String, dynamic>? ?? {};
      final romalrcData = data['romalrc'] as Map<String, dynamic>? ?? {};

      final yrcContent = yrcData['lyric'] as String? ?? '';
      final lrcContent = lrcData['lyric'] as String? ?? '';
      final tlyricContent = tlyricData['lyric'] as String? ?? '';
      final romalrcContent = romalrcData['lyric'] as String? ?? '';

      final yrcLines = yrcContent.isNotEmpty
          ? _yrcParser.parse(yrcContent).lines
          : <ParsedLine>[];

      var lines = _parseLrcToLines(lrcContent);
      if (yrcLines.isNotEmpty) {
        lines = _attachWordTimings(lines, yrcLines);
      } else if (lines.isEmpty) {
        // 没有 LRC 时退回 YRC 自己的行（会少掉头部行）
        lines = yrcLines;
      }

      if (lines.isEmpty) return null;

      final transLines = tlyricContent.isNotEmpty
          ? _parseLrcToLines(tlyricContent)
          : <ParsedLine>[];

      // 行级罗马音（romalrc）与 LRC/翻译共用同一套时间戳
      final romaLines = romalrcContent.isNotEmpty
          ? _parseLrcToLines(romalrcContent)
          : <ParsedLine>[];

      return ParsedLyrics(
        lines: lines,
        translationLines: transLines,
        romajiLines: romaLines,
      );
    } catch (_) {
      return null;
    }
  }

  // 把逐字歌词（YRC）的时间轴贴到行级歌词（LRC）上
  // 行起始时间仍然用 LRC 的，只替换成 YRC 的逐字 words
  // 这样后面的翻译/罗马音按时间戳匹配不会因为两套时间轴的整体偏移而错行
  //
  // 两套时间轴实测会差几十 几百毫秒（YRC 的行起始是第一个字的起点）
  // 所以以文本一致为主要判据，时间戳只作兜底
  List<ParsedLine> _attachWordTimings(
    List<ParsedLine> baseLines,
    List<ParsedLine> wordLines,
  ) {
    if (baseLines.isEmpty || wordLines.isEmpty) return baseLines;

    final result = <ParsedLine>[];
    var j = 0;

    for (final base in baseLines) {
      // 只在接下来的几行里找匹配
      // 同时避免错配到相邻的其它行
      final int windowEnd = (j + _wordLookaheadLines) < wordLines.length
          ? (j + _wordLookaheadLines)
          : wordLines.length;

      var matchedIndex = -1;

      // 1. 文本一致（忽略空白）最可靠
      for (var k = j; k < windowEnd; k++) {
        if (wordLines[k].words.isNotEmpty &&
            _isSameText(base.text, wordLines[k].text)) {
          matchedIndex = k;
          break;
        }
      }

      // 2. 文本对不上时退回时间戳（容差很小，避免抢走相邻行）
      if (matchedIndex < 0) {
        for (var k = j; k < windowEnd; k++) {
          if (wordLines[k].words.isEmpty) continue;
          if ((wordLines[k].startMs - base.startMs).abs() <=
              _lineMatchToleranceMs) {
            matchedIndex = k;
            break;
          }
        }
      }

      if (matchedIndex < 0) {
        // 落后时才丢弃它，避免指针一直卡住
        while (j < wordLines.length &&
            wordLines[j].startMs < base.startMs - _lineOffsetToleranceMs) {
          j++;
        }
        result.add(base);
        continue;
      }

      result.add(
        ParsedLine(
          startMs: base.startMs,
          endMs: base.endMs,
          words: wordLines[matchedIndex].words,
        ),
      );
      j = matchedIndex + 1;
    }

    return result;
  }

  static bool _isSameText(String a, String b) {
    final na = a.replaceAll(RegExp(r'\s+'), '');
    final nb = b.replaceAll(RegExp(r'\s+'), '');
    return na.isNotEmpty && na == nb;
  }

  // 简单 LRC 解析
  static final _lrcPattern = RegExp(r'\[(\d+):(\d{1,2})[.:](\d{1,3})\]');

  List<ParsedLine> _parseLrcToLines(String lrcContent) {
    final lines = <ParsedLine>[];

    for (var raw in lrcContent.split('\n')) {
      raw = raw.trim();
      if (raw.isEmpty) continue;

      // 检测新版网易云 JSON 歌词行 {"t":12345,"c":[{"tx":"..."}]}
      if (raw.startsWith('{') && raw.endsWith('}')) {
        try {
          final jsonMap = jsonDecode(raw) as Map<String, dynamic>;
          final timeMs = (jsonMap['t'] as num?)?.toInt() ?? 0;
          final cArr = jsonMap['c'] as List<dynamic>? ?? [];
          final buffer = StringBuffer();
          for (final item in cArr) {
            if (item is Map && item.containsKey('tx')) {
              buffer.write(item['tx'] ?? '');
            }
          }
          final text = buffer.toString().trim();
          if (text.isNotEmpty) {
            lines.add(
              ParsedLine(
                startMs: timeMs,
                endMs: timeMs,
                words: [ParsedWord(startMs: timeMs, endMs: timeMs, text: text)],
              ),
            );
          }
          continue;
        } catch (_) {
          // 不是合法的单行 json，按普通文本继续解析
        }
      }

      // 传统 LRC 解析
      final match = _lrcPattern.firstMatch(raw);
      if (match == null) continue;

      final ms =
          int.parse(match.group(1)!) * 60000 +
          int.parse(match.group(2)!) * 1000 +
          int.parse(match.group(3)!.padRight(3, '0').substring(0, 3));
      final text = raw.substring(match.end).trim();

      if (text.isEmpty) continue;

      lines.add(
        ParsedLine(
          startMs: ms,
          endMs: ms,
          words: [ParsedWord(startMs: ms, endMs: ms, text: text)],
        ),
      );
    }

    return lines;
  }
}
