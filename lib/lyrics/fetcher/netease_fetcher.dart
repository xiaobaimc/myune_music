// 参考 https://github.com/WisteriaZy/lyricGeter/tree/master/fetcher/netease.py

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../decryptor/eapi_decryptor.dart';
import '../parser/parsed_models.dart';
// import '../parser/yrc_parser.dart';

class NeteaseFetcher {
  static const _baseUrl = 'https://music.163.com';

  static const _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    'Referer': 'https://music.163.com/',
    'Content-Type': 'application/x-www-form-urlencoded',
  };

  // final _yrcParser = YrcParser();

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

  // 获取歌词（含 YRC 逐字）
  Future<ParsedLyrics?> _getLyrics(int songId) async {
    const path = '/api/song/lyric/v1';

    final params = {
      'id': songId,
      'lv': -1, // 普通歌词版本
      'tv': -1, // 翻译版本
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

      // final yrcData = data['yrc'] as Map<String, dynamic>? ?? {};
      final lrcData = data['lrc'] as Map<String, dynamic>? ?? {};
      final tlyricData = data['tlyric'] as Map<String, dynamic>? ?? {};

      // final yrcContent = yrcData['lyric'] as String? ?? '';
      final lrcContent = lrcData['lyric'] as String? ?? '';
      final tlyricContent = tlyricData['lyric'] as String? ?? '';

      // 暂时不使用逐字歌词（YRC），只使用普通 LRC 歌词
      // if (yrcContent.isNotEmpty) {
      //   final parsed = _yrcParser.parse(yrcContent);
      //   // 合并翻译
      //   if (tlyricContent.isNotEmpty) {
      //     return _mergeTranslation(parsed, tlyricContent);
      //   }
      //   return parsed;
      // } else if (lrcContent.isNotEmpty) {
      if (lrcContent.isNotEmpty) {
        final lines = _parseLrcToLines(lrcContent);
        if (tlyricContent.isNotEmpty) {
          final transLines = _parseLrcToLines(tlyricContent);
          return ParsedLyrics(lines: lines, translationLines: transLines);
        }
        return ParsedLyrics(lines: lines);
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  // 将翻译 LRC 合并到 YRC 解析结果中
  // ParsedLyrics _mergeTranslation(ParsedLyrics yrcParsed, String tlyricLrc) {
  //   final transLines = _parseLrcToLines(tlyricLrc);
  //   return ParsedLyrics(
  //     tags: yrcParsed.tags,
  //     lines: yrcParsed.lines,
  //     translationLines: transLines,
  //     romajiLines: yrcParsed.romajiLines,
  //   );
  // }

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
