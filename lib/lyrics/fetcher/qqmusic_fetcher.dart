// 参考 https://github.com/WisteriaZy/lyricGeter/tree/master/fetcher/qqmusic.py
// 参考: https://github.com/chenmozhijin/LDDC

import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../decryptor/qrc_decryptor.dart';
import '../parser/parsed_models.dart';
import '../parser/qrc_parser.dart';

class QQMusicFetcher {
  static const _baseUrl = 'https://u.y.qq.com/cgi-bin/musicu.fcg';

  final _qrcParser = QrcParser();

  /// Session 通用参数
  late Map<String, dynamic> _comm;
  bool _inited = false;

  QQMusicFetcher() {
    final romSuffix = ['5', '4', '2'][Random().nextInt(3)];
    _comm = {
      'ct': 11,
      'cv': '1003006',
      'v': '1003006',
      'os_ver': '15',
      'phonetype': '24122RKC7C',
      'rom':
          'Redmi/miro/miro:15/AE3A.240806.005/OS2.0.10$romSuffix.0.VOMCNXM:user/release-keys',
      'tmeAppID': 'qqmusiclight',
      'nettype': 'NETWORK_WIFI',
      'udid': '0',
    };
  }

  /// 搜索歌曲并获取歌词 同时返回歌曲 ID（用于 AMLL 查询）。
  Future<({ParsedLyrics? lyrics, int? songId})> search(
    String title,
    String artist,
  ) async {
    try {
      await _ensureSession();

      // 搜索歌曲
      final songInfo = await _searchSong(title, artist);
      if (songInfo == null) return (lyrics: null, songId: null);

      final songId = songInfo['id'] as int;

      // 获取歌词
      final lyrics = await _getLyrics(songInfo);
      return (lyrics: lyrics, songId: songId);
    } catch (_) {
      return (lyrics: null, songId: null);
    }
  }

  // 初始化 Session
  Future<void> _ensureSession() async {
    if (_inited) return;

    final data = await _request('GetSession', 'music.getSession.session', {
      'caller': 0,
      'uid': '0',
      'vkey': 0,
    });

    final session = data['session'] as Map<String, dynamic>;
    _comm['uid'] = session['uid'];
    _comm['sid'] = session['sid'];
    _comm['userip'] = session['userip'];
    _inited = true;
  }

  // 统一 API 请求
  Future<Map<String, dynamic>> _request(
    String method,
    String module,
    Map<String, dynamic> param,
  ) async {
    if (!_inited && method != 'GetSession') {
      await _ensureSession();
    }

    final body = jsonEncode({
      'comm': _comm,
      'request': {'method': method, 'module': module, 'param': param},
    });

    final response = await http
        .post(
          Uri.parse(_baseUrl),
          headers: {
            'cookie': 'tmeLoginType=-1;',
            'content-type': 'application/json',
            'accept-encoding': 'gzip',
            'user-agent': 'okhttp/3.14.9',
          },
          body: body,
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('QQ Music API HTTP ${response.statusCode}');
    }

    final data =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

    if (data['code'] != 0) {
      throw Exception('QQ Music API error code: ${data['code']}');
    }

    final requestData = data['request'] as Map<String, dynamic>;
    if (requestData['code'] != 0) {
      throw Exception('QQ Music request error: ${requestData['code']}');
    }

    return requestData['data'] as Map<String, dynamic>;
  }

  // 搜索歌曲，返回最佳匹配的 {id, mid, title, artist, album, duration}
  Future<Map<String, dynamic>?> _searchSong(String title, String artist) async {
    final query = '$title $artist'.trim();

    final data = await _request(
      'DoSearchForQQMusicDesktop',
      'music.search.SearchCgiService',
      {'query': query, 'page_num': 1, 'num_per_page': 10, 'search_type': 0},
    );

    final songs =
        ((data['body'] as Map<String, dynamic>?)?['song']
                as Map<String, dynamic>?)?['list']
            as List<dynamic>? ??
        [];

    if (songs.isEmpty) return null;

    // 降低片段/翻唱/sped up 版本的优先级
    int scoreSong(Map<String, dynamic> song) {
      final name = '${song['name'] ?? ''} ${song['title'] ?? ''}';
      var score = 0;
      if (name.contains('片段')) score -= 500;
      if (name.contains('原唱') || name.contains('翻唱')) score -= 300;
      final lower = name.toLowerCase();
      if (lower.contains('sped up') || lower.contains('slowed')) score -= 200;
      return score;
    }

    final sortedSongs = songs.cast<Map<String, dynamic>>().toList()
      ..sort((a, b) => scoreSong(b).compareTo(scoreSong(a)));
    final first = sortedSongs.first;

    final singers = first['singer'] as List<dynamic>? ?? [];
    final artistNames = singers
        .map((s) => (s as Map<String, dynamic>)['name'] as String? ?? '')
        .where((n) => n.isNotEmpty)
        .join(', ');

    return {
      'id': first['id'] as int? ?? 0,
      'mid': first['mid'] as String? ?? '',
      'title': (first['title'] as String?) ?? (first['name'] as String?) ?? '',
      'artist': artistNames,
      'album': (first['album'] as Map<String, dynamic>?)?['name'] ?? '',
      'duration': first['interval'] as int? ?? 0,
    };
  }

  // 获取歌词（加密 QRC 解密 解析）。
  Future<ParsedLyrics?> _getLyrics(Map<String, dynamic> song) async {
    final songId = song['id'] as int;
    final songTitle = song['title'] as String? ?? '';
    final songArtist = song['artist'] as String? ?? '';
    final songAlbum = song['album'] as String? ?? '';
    final duration = song['duration'] as int? ?? 0;

    final param = {
      'albumName': base64Encode(utf8.encode(songAlbum)),
      'crypt': 1,
      'ct': 19,
      'cv': 2111,
      'interval': duration,
      'lrc_t': 0,
      'qrc': 1,
      'qrc_t': 0,
      'roma': 1,
      'roma_t': 0,
      'singerName': base64Encode(utf8.encode(songArtist)),
      'songID': songId,
      'songName': base64Encode(utf8.encode(songTitle)),
      'trans': 1,
      'trans_t': 0,
      'type': 0,
    };

    final data = await _request(
      'GetPlayLyricInfo',
      'music.musichallSong.PlayLyricInfo',
      param,
    );

    // 解密各类歌词字段
    final origLrc = data['lyric'] as String? ?? '';
    final transLrc = data['trans'] as String? ?? '';

    // 判断加密类型
    final qrcT = data['qrc_t'] as int? ?? 0;
    final lrcT = data['lrc_t'] as int? ?? 0;
    final origT = qrcT != 0 ? qrcT : lrcT;
    final transT = data['trans_t'] as int? ?? 0;

    // 解密原文
    String? origDecrypted;
    if (origLrc.isNotEmpty && origT != 0) {
      origDecrypted = QrcDecryptor.decrypt(origLrc);
    }
    if (origDecrypted == null) return null;

    // 解析原文
    final origParsed = _qrcParser.parse(origDecrypted);
    if (origParsed.lines.isEmpty) return null;

    // 解密翻译
    final translationLines = <ParsedLine>[];
    if (transLrc.isNotEmpty && transT != 0) {
      final transDecrypted = QrcDecryptor.decrypt(transLrc);
      if (transDecrypted != null) {
        final transParsed = _qrcParser.parse(transDecrypted);
        translationLines.addAll(transParsed.lines);
      }
    }

    return ParsedLyrics(
      tags: origParsed.tags,
      lines: origParsed.lines,
      translationLines: translationLines,
    );
  }
}
