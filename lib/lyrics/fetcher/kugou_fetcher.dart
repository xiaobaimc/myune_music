// 参考 https://github.com/WisteriaZy/lyricGeter/tree/master/fetcher/kugou.py
// 签名算法参考 LDDC-Android KugouApi.kt

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../decryptor/krc_decryptor.dart';
import '../parser/krc_parser.dart';
import '../parser/parsed_models.dart';

class KugouFetcher {
  // 签名密钥（来自 LDDC-Android）
  static const _signatureKey = 'LnT6xpN3khm36zse0QzvmgTZ3waWdRSA';
  static const _clientVer = '11070';

  final _krcParser = KrcParser();

  // 搜索歌曲并获取歌词
  Future<ParsedLyrics?> search(String title, String artist) async {
    try {
      final songInfo = await _searchSong(title, artist);
      if (songInfo == null) return null;

      return await _getLyrics(songInfo['hash'] as String);
    } catch (_) {
      return null;
    }
  }

  static String _md5Hash(String text) {
    return md5.convert(utf8.encode(text)).toString();
  }

  // 生成 API 签名
  static String _generateSignature(Map<String, String> params) {
    final sorted = params.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final paramStr = sorted.map((e) => '${e.key}=${e.value}').join();
    return _md5Hash('$_signatureKey$paramStr$_signatureKey');
  }

  // 搜索歌曲，返回第一个匹配结果的
  Future<Map<String, dynamic>?> _searchSong(String title, String artist) async {
    final keyword = '$artist $title'.trim();
    final mid = _md5Hash(DateTime.now().millisecondsSinceEpoch.toString());
    final clientTime = (DateTime.now().millisecondsSinceEpoch ~/ 1000)
        .toString();

    final params = <String, String>{
      'keyword': keyword,
      'page': '1',
      'pagesize': '10',
      'filter': '0',
      'userid': '0',
      'appid': '3116',
      'token': '',
      'clienttime': clientTime,
      'iscorrection': '1',
      'uuid': '-',
      'mid': mid,
      'dfid': '-',
      'clientver': _clientVer,
      'platform': 'AndroidFilter',
    };
    params['signature'] = _generateSignature(params);

    final headers = {
      'User-Agent': 'Android14-1070-$_clientVer-201-0-search-wifi',
      'KG-Rec': '1',
      'KG-RC': '1',
    };

    try {
      final uri = Uri.parse(
        'http://mobilecdn.kugou.com/api/v3/search/song',
      ).replace(queryParameters: params);

      final response = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['status'] != 1) return null;

      final songs =
          (data['data'] as Map<String, dynamic>?)?['info'] as List<dynamic>? ??
          [];
      if (songs.isEmpty) return null;

      // 艺术家匹配 > 非片段 > 非翻唱
      int scoreSong(Map<String, dynamic> song) {
        final songTitle = song['songname'] as String? ?? '';
        final songArtist = song['singername'] as String? ?? '';
        var score = 0;
        if (artist.isNotEmpty &&
            songArtist.toLowerCase().contains(artist.toLowerCase())) {
          score += 1000;
        }
        if (songTitle.contains('片段')) score -= 500;
        if (songTitle.contains('原唱') || songTitle.contains('翻唱')) {
          score -= 300;
        }
        final lower = songTitle.toLowerCase();
        if (lower.contains('sped up') || lower.contains('slowed')) {
          score -= 200;
        }
        return score;
      }

      final sortedSongs = songs.cast<Map<String, dynamic>>().toList()
        ..sort((a, b) => scoreSong(b).compareTo(scoreSong(a)));
      final selected = sortedSongs.first;

      return {
        'hash': selected['hash'] as String? ?? '',
        'title': selected['songname'] as String? ?? '',
        'artist': selected['singername'] as String? ?? '',
      };
    } catch (_) {
      return null;
    }
  }

  // 获取歌词
  Future<ParsedLyrics?> _getLyrics(String songHash) async {
    try {
      // 搜索歌词候选
      final candidate = await _searchLyricCandidate(songHash);
      if (candidate == null) return null;

      final lyricId = candidate['id'] as String;
      final accessKey = candidate['accesskey'] as String;

      // 下载加密歌词
      final encryptedContent = await _downloadLyric(lyricId, accessKey);
      if (encryptedContent == null) return null;

      // 解密
      final decrypted = KrcDecryptor.decrypt(encryptedContent);
      if (decrypted == null) return null;

      // 解析
      return _krcParser.parse(decrypted);
    } catch (_) {
      return null;
    }
  }

  // 搜索歌词候选
  Future<Map<String, String>?> _searchLyricCandidate(String songHash) async {
    final mid = _md5Hash(DateTime.now().millisecondsSinceEpoch.toString());
    final clientTime = (DateTime.now().millisecondsSinceEpoch ~/ 1000)
        .toString();

    final params = <String, String>{
      'clienttime': clientTime,
      'mid': mid,
      'clientver': _clientVer,
      'dfid': '-',
      'appid': '3116',
      'keyword': '%20',
      'bitrate': '0',
      'album_id': '0',
      'hash': songHash,
      'album_audio_id': '',
    };
    params['signature'] = _generateSignature(params);

    final headers = {
      'User-Agent': 'Android14-1070-$_clientVer-201-0-Lyric-wifi',
    };

    final uri = Uri.parse(
      'https://krcs.kugou.com/search',
    ).replace(queryParameters: params);

    final response = await http
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) return null;

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = data['candidates'] as List<dynamic>? ?? [];
    if (candidates.isEmpty) return null;

    final first = candidates[0] as Map<String, dynamic>;
    final id = first['id']?.toString();
    final accesskey = first['accesskey']?.toString();
    if (id == null || accesskey == null) return null;

    return {'id': id, 'accesskey': accesskey};
  }

  // 下载加密歌词内容（Base64 编码的 KRC）
  Future<String?> _downloadLyric(String lyricId, String accessKey) async {
    final params = {
      'id': lyricId,
      'accesskey': accessKey,
      'fmt': 'krc',
      'charset': 'utf8',
      'client': 'mobi',
      'ver': '1',
    };

    final headers = {
      'User-Agent': 'Android14-1070-$_clientVer-201-0-Lyric-wifi',
    };

    final uri = Uri.parse(
      'http://lyrics.kugou.com/download',
    ).replace(queryParameters: params);

    final response = await http
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) return null;

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['content'] as String?;
  }
}
