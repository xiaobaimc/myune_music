import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'remote_entry.dart';
import 'remote_source.dart';
import 'remote_stream.dart';

/// Google Drive 原生客户端（Drive API v3）。
///
/// 与 WebDAV / FTP 并列为第三种网络源：直接用 OAuth refresh_token 换取
/// access_token，走官方 `files.list` 列目录、`files.get?alt=media` 拉流。
/// 相比「网盘 → 自建 WebDAV 桥」少了一跳，实测首包在 1 秒内，且原生支持
/// HTTP Range（206 + Content-Range），拖动进度不会再触发
/// `Immediate exit requested`。
///
/// 凭据（client_id / client_secret / refresh_token）只保存在本机
/// shared_preferences，由用户在原生界面里填写或从本机文件导入；
/// 本文件与仓库里**不包含任何真实凭据**，也不会把凭据写进日志。
class GoogleDriveClient {
  GoogleDriveClient(this.source);

  final RemoteSource source;

  static const String _tokenUrl = 'https://oauth2.googleapis.com/token';
  static const String _apiBase = 'https://www.googleapis.com/drive/v3';
  static const String _folderMime = 'application/vnd.google-apps.folder';
  static const String _pathPrefix = 'gd/';

  static final Map<String, _AccessToken> _tokenCache =
      <String, _AccessToken>{};
  static final Map<String, Future<String>> _tokenInflight =
      <String, Future<String>>{};

  /// 目录 / 文件的统一路径：`gd/<fileId>/<URL 编码后的名称>`。
  ///
  /// 末尾带上名称有两个作用：面包屑能直接显示中文 / 日文目录名，
  /// 以及代理可以用扩展名推断 Content-Type，都不需要再发一次 API 请求。
  static String pathOf(String fileId, String name) =>
      '$_pathPrefix$fileId/${Uri.encodeComponent(name)}';

  /// 从统一路径里取回 Drive 的 fileId。
  static String fileIdOf(String path) {
    final trimmed = path.trim();
    if (trimmed.startsWith(_pathPrefix)) {
      final rest = trimmed.substring(_pathPrefix.length);
      final slash = rest.indexOf('/');
      return slash < 0 ? rest : rest.substring(0, slash);
    }
    if (trimmed.isEmpty || trimmed == 'root') return 'root';
    return trimmed;
  }

  static bool isDrivePath(String path) => path.trim().startsWith(_pathPrefix);

  String get _rootId {
    final id = source.rootFolderId.trim();
    return id.isEmpty ? 'root' : id;
  }

  /// access_token 只在内存里缓存，提前 2 分钟过期；并发刷新合并成一次请求。
  Future<String> _accessToken() {
    final key = source.refreshToken;
    final cached = _tokenCache[key];
    if (cached != null && DateTime.now().isBefore(cached.expiresAt)) {
      return Future<String>.value(cached.value);
    }
    final inflight = _tokenInflight[key];
    if (inflight != null) return inflight;
    final future = _refresh(key);
    _tokenInflight[key] = future;
    return future.whenComplete(() => _tokenInflight.remove(key));
  }

  Future<String> _refresh(String refreshToken) async {
    final response = await http
        .post(
          Uri.parse(_tokenUrl),
          headers: <String, String>{
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: <String, String>{
            'client_id': source.clientId,
            'client_secret': source.clientSecret,
            'refresh_token': refreshToken,
            'grant_type': 'refresh_token',
          },
        )
        .timeout(const Duration(seconds: 25));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Google 令牌刷新失败（HTTP ${response.statusCode}）：'
        '${_shortError(response.body)}',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Google 返回的令牌格式异常');
    }
    final value = decoded['access_token']?.toString() ?? '';
    if (value.isEmpty) throw StateError('Google 未返回 access_token');
    final rawSeconds = decoded['expires_in'];
    final seconds = rawSeconds is num ? rawSeconds.toInt() : 3600;
    _tokenCache[refreshToken] = _AccessToken(
      value,
      DateTime.now().add(
        Duration(seconds: seconds > 180 ? seconds - 120 : seconds ~/ 2),
      ),
    );
    return value;
  }

  Map<String, String> _headers(String accessToken) => <String, String>{
        'Authorization': 'Bearer $accessToken',
        'Accept': 'application/json',
        'User-Agent': 'MyuneMusic/1.0 (Desktop)',
      };

  /// 列出一个文件夹的直接子项（自动翻页）。
  ///
  /// [path] 为 [pathOf] 生成的统一路径；传空或 `root` 时回落到配置里的
  /// 根文件夹 ID。Google 原生文档（Docs / Sheets 等）没有可下载的二进制，
  /// 这里照常列出但扩展名为空，界面会自动过滤掉。
  Future<List<RemoteEntry>> list(String path) async {
    final folderId = fileIdOf(path);
    final effective = folderId == 'root' ? _rootId : folderId;
    final token = await _accessToken();
    final result = <RemoteEntry>[];
    String? pageToken;
    do {
      final query = <String, String>{
        'q': "'$effective' in parents and trashed = false",
        'fields': 'nextPageToken,files('
            'id,name,mimeType,size,fileExtension,modifiedTime,shortcutDetails)',
        'pageSize': '1000',
        'orderBy': 'name',
        // Workspace / 共享云端硬盘：不带上这两个参数会漏掉共享盘里的曲目。
        'supportsAllDrives': 'true',
        'includeItemsFromAllDrives': 'true',
        if (pageToken != null && pageToken.isNotEmpty) 'pageToken': pageToken,
      };
      final uri = Uri.parse('$_apiBase/files').replace(
        queryParameters: query,
      );
      final response = await http
          .get(uri, headers: _headers(token))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'Google Drive 列目录失败（HTTP ${response.statusCode}）：'
          '${_shortError(response.body)}',
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw StateError('Google Drive 返回的目录格式异常');
      }
      final files = decoded['files'];
      if (files is List) {
        for (final item in files) {
          if (item is! Map) continue;
          var id = (item['id'] ?? '').toString();
          if (id.isEmpty) continue;
          final name = (item['name'] ?? '').toString();
          var mime = (item['mimeType'] ?? '').toString();
          // 快捷方式本身没有内容，必须替换成目标文件 / 文件夹，
          // 否则点进去会拿到一个空条目（与 Go 版 drivedav 的处理一致）。
          final shortcut = item['shortcutDetails'];
          if (shortcut is Map) {
            final targetId = (shortcut['targetId'] ?? '').toString();
            final targetMime = (shortcut['targetMimeType'] ?? '').toString();
            if (targetId.isNotEmpty) id = targetId;
            if (targetMime.isNotEmpty) mime = targetMime;
          }
          final isDirectory = mime == _folderMime;
          final size = int.tryParse((item['size'] ?? '').toString());
          DateTime? modified;
          final rawModified = (item['modifiedTime'] ?? '').toString();
          if (rawModified.isNotEmpty) {
            modified = DateTime.tryParse(rawModified);
          }
          result.add(
            RemoteEntry(
              name: name,
              path: pathOf(id, name),
              isDirectory: isDirectory,
              size: size,
              modified: modified,
            ),
          );
        }
      }
      pageToken = decoded['nextPageToken']?.toString();
    } while (pageToken != null &&
        pageToken.isNotEmpty &&
        result.length < 20000);
    return result;
  }

  /// 打开一个文件。start/end 为闭区间；Google 原生支持 Range，返回 206。
  Future<RemoteStreamResult> open(
    String path, {
    int? start,
    int? end,
    Duration headerTimeout = const Duration(seconds: 25),
  }) async {
    final token = await _accessToken();
    final fileId = fileIdOf(path);
    final client = http.Client();
    try {
      final request = http.Request(
        'GET',
        Uri.parse('$_apiBase/files/$fileId').replace(
          queryParameters: <String, String>{
            'alt': 'media',
            'supportsAllDrives': 'true',
          },
        ),
      )
        ..headers.addAll(_headers(token))
        ..headers['Accept'] = '*/*';
      final range = formatRangeHeader(start, end);
      if (range.isNotEmpty) request.headers['Range'] = range;
      final response = await client.send(request).timeout(headerTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.stream.drain<void>();
        throw Exception(
          'Google Drive 下载失败（HTTP ${response.statusCode}）：'
          '${response.statusCode == 403 ? '该文件可能是 Google 原生文档或被限制共享，没有可下载的二进制内容' : '请检查文件是否存在、凭据是否被撤销'}',
        );
      }
      final info = describeHttpRange(
        contentRange: response.headers['content-range'],
        contentLength: response.contentLength,
        requestedStart: start,
        requestedEnd: end,
        upstreamPartial: response.statusCode == 206,
      );
      return RemoteStreamResult(
        bytes: limitByteStream(response.stream, info.limit),
        totalLength: info.totalLength,
        servedStart: info.servedStart,
        servedEnd: info.servedEnd,
        contentType: response.headers['content-type'] ??
            guessContentType(remoteEntryName(path, isDirectory: false)),
        close: () async {
          client.close();
        },
      );
    } catch (_) {
      client.close();
      rethrow;
    }
  }

  /// 只取响应头探测文件，不下载正文。用于诊断与长度补全。
  Future<RemoteProbeResult> probe(
    String path, {
    int? start,
    int? end,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      final token = await _accessToken();
      final fileId = fileIdOf(path);
      final from = start ?? 0;
      final to = end ?? from;
      final client = http.Client();
      try {
        final request = http.Request(
          'GET',
          Uri.parse('$_apiBase/files/$fileId').replace(
            queryParameters: <String, String>{
              'alt': 'media',
              'supportsAllDrives': 'true',
            },
          ),
        )
          ..headers.addAll(_headers(token))
          ..headers['Accept'] = '*/*'
          ..headers['Range'] = 'bytes=$from-$to';
        final response = await client
            .send(request)
            .timeout(const Duration(seconds: 25));
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
        } else if (response.statusCode >= 200 &&
            response.statusCode < 300) {
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
          message: ok ? '' : _shortError(''),
        );
      } finally {
        client.close();
      }
    } catch (error) {
      stopwatch.stop();
      return RemoteProbeResult(
        ok: false,
        statusCode: 0,
        elapsedMs: stopwatch.elapsedMilliseconds,
        message: '$error',
      );
    }
  }

  /// 直接用 files.get 取文件大小，作为 Range 探测失败时的兜底。
  Future<int?> contentLength(String path) async {
    try {
      final token = await _accessToken();
      final fileId = fileIdOf(path);
      final uri = Uri.parse('$_apiBase/files/$fileId').replace(
        queryParameters: <String, String>{
          'fields': 'size',
          'supportsAllDrives': 'true',
        },
      );
      final response = await http
          .get(uri, headers: _headers(token))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        return int.tryParse((decoded['size'] ?? '').toString());
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // --- 写入操作：图形化文件夹选择、上传、新建、重命名、删除 ---

  /// 把统一路径解析成可作为 parents 的文件夹 ID。
  /// 字面量 `root` 原样保留（Drive API 认这个别名，指向账号真正的根目录），
  /// 只有空路径才回落到配置里的默认文件夹。
  String folderIdOf(String path) {
    return path.trim().isEmpty ? _rootId : fileIdOf(path);
  }

  /// 只列出某个文件夹下的子文件夹（不返回文件），供「选择默认文件夹」界面用。
  Future<List<RemoteEntry>> listFolders(String folderId) async {
    final effective = folderId.trim().isEmpty ? _rootId : folderId;
    final token = await _accessToken();
    final result = <RemoteEntry>[];
    String? pageToken;
    do {
      final uri = Uri.parse('$_apiBase/files').replace(
        queryParameters: <String, String>{
          'q': "'$effective' in parents and "
              "mimeType = '$_folderMime' and trashed = false",
          'fields': 'nextPageToken,files(id,name,mimeType,shortcutDetails)',
          'pageSize': '1000',
          'orderBy': 'name',
          'supportsAllDrives': 'true',
          'includeItemsFromAllDrives': 'true',
          if (pageToken != null && pageToken.isNotEmpty) 'pageToken': pageToken,
        },
      );
      final response = await http
          .get(uri, headers: _headers(token))
          .timeout(const Duration(seconds: 30));
      _ensureOk(response, '列文件夹');
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) throw StateError('Google Drive 返回的目录格式异常');
      final files = decoded['files'];
      if (files is List) {
        for (final item in files) {
          if (item is! Map) continue;
          var id = (item['id'] ?? '').toString();
          if (id.isEmpty) continue;
          final name = (item['name'] ?? '').toString();
          var mime = (item['mimeType'] ?? '').toString();
          final shortcut = item['shortcutDetails'];
          if (shortcut is Map) {
            final targetId = (shortcut['targetId'] ?? '').toString();
            final targetMime = (shortcut['targetMimeType'] ?? '').toString();
            if (targetId.isNotEmpty) id = targetId;
            if (targetMime.isNotEmpty) mime = targetMime;
          }
          if (mime != _folderMime) continue;
          result.add(
            RemoteEntry(
              name: name,
              path: pathOf(id, name),
              isDirectory: true,
            ),
          );
        }
      }
      pageToken = decoded['nextPageToken']?.toString();
    } while (pageToken != null &&
        pageToken.isNotEmpty &&
        result.length < 20000);
    return result;
  }

  /// 读取当前授权账号的邮箱与显示名，用于在界面上确认「登录的是哪个账号」。
  Future<(String, String)> about() async {
    final token = await _accessToken();
    final response = await http
        .get(
          Uri.parse('$_apiBase/about').replace(
            queryParameters: <String, String>{
              'fields': 'user(emailAddress,displayName)',
            },
          ),
          headers: _headers(token),
        )
        .timeout(const Duration(seconds: 15));
    _ensureOk(response, '读取账号信息');
    final decoded = jsonDecode(response.body);
    if (decoded is Map && decoded['user'] is Map) {
      final user = decoded['user'] as Map;
      return (
        (user['emailAddress'] ?? '').toString(),
        (user['displayName'] ?? '').toString(),
      );
    }
    return ('', '');
  }

  /// 在 [parentPath] 对应的文件夹里新建一个子文件夹。
  Future<RemoteEntry> createFolder(String parentPath, String name) async {
    final folderName = name.trim();
    if (folderName.isEmpty) throw ArgumentError('文件夹名称不能为空');
    final token = await _accessToken();
    final response = await http
        .post(
          Uri.parse('$_apiBase/files').replace(
            queryParameters: <String, String>{
              'supportsAllDrives': 'true',
              'fields': 'id,name,mimeType',
            },
          ),
          headers: <String, String>{
            ..._headers(token),
            'Content-Type': 'application/json; charset=UTF-8',
          },
          body: jsonEncode(<String, Object>{
            'name': folderName,
            'mimeType': _folderMime,
            'parents': <String>[folderIdOf(parentPath)],
          }),
        )
        .timeout(const Duration(seconds: 30));
    _ensureOk(response, '新建文件夹');
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) throw StateError('Google Drive 返回的文件格式异常');
    final id = (decoded['id'] ?? '').toString();
    if (id.isEmpty) throw StateError('Google Drive 未返回新文件夹 ID');
    return RemoteEntry(
      name: (decoded['name'] ?? folderName).toString(),
      path: pathOf(id, folderName),
      isDirectory: true,
    );
  }

  /// 把文件 / 文件夹移入回收站。Drive API v3 的 delete 不是永久删除，
  /// 用户仍可在 Google Drive 网页端的「回收站」里恢复。
  Future<void> deleteEntry(String path) async {
    final token = await _accessToken();
    final response = await http
        .delete(
          Uri.parse('$_apiBase/files/${fileIdOf(path)}').replace(
            queryParameters: <String, String>{
              'supportsAllDrives': 'true',
            },
          ),
          headers: _headers(token),
        )
        .timeout(const Duration(seconds: 30));
    // 204 No Content 是成功；部分情况下也会返回 200 + 空正文。
    if (response.statusCode != 204 &&
        (response.statusCode < 200 || response.statusCode >= 300)) {
      _ensureOk(response, '删除');
    }
  }

  /// 重命名文件或文件夹。
  Future<void> renameEntry(String path, String newName) async {
    final name = newName.trim();
    if (name.isEmpty) throw ArgumentError('名称不能为空');
    final token = await _accessToken();
    final response = await http
        .patch(
          Uri.parse('$_apiBase/files/${fileIdOf(path)}').replace(
            queryParameters: <String, String>{
              'supportsAllDrives': 'true',
              'fields': 'id,name',
            },
          ),
          headers: <String, String>{
            ..._headers(token),
            'Content-Type': 'application/json; charset=UTF-8',
          },
          body: jsonEncode(<String, String>{'name': name}),
        )
        .timeout(const Duration(seconds: 30));
    _ensureOk(response, '重命名');
  }

  /// 用 resumable 上传把一个本机文件放进 [parentPath] 对应的文件夹。
  ///
  /// 按 4 MB（256 KB 的整数倍，Drive resumable 的要求）分块 PUT，每块
  /// 独立确认，避免把 80 MB 的无损音频一次性读进内存；[onProgress] 在每块
  /// 确认后回调（已上传字节数 / 总字节数）。[isCancelled] 用于「取消上传」。
  Future<RemoteEntry> uploadFile(
    String parentPath,
    String localPath, {
    String? name,
    void Function(int sent, int total)? onProgress,
    Future<bool> Function()? isCancelled,
  }) async {
    final file = File(localPath);
    if (!await file.exists()) {
      throw StateError('本机文件不存在：$localPath');
    }
    final total = await file.length();
    if (total <= 0) throw StateError('不能上传空文件：$localPath');
    final fileName = (name ?? p.basename(localPath)).trim();
    if (fileName.isEmpty) throw StateError('无法解析文件名：$localPath');
    final contentType = guessContentType(fileName);

    final token = await _accessToken();
    final client = http.Client();
    try {
      final initResponse = await client
          .post(
            Uri.parse(
              'https://www.googleapis.com/upload/drive/v3/files',
            ).replace(
              queryParameters: <String, String>{
                'uploadType': 'resumable',
                'supportsAllDrives': 'true',
              },
            ),
            headers: <String, String>{
              ..._headers(token),
              'Content-Type': 'application/json; charset=UTF-8',
              'X-Upload-Content-Type': contentType,
              'X-Upload-Content-Length': '$total',
            },
            body: jsonEncode(<String, Object>{
              'name': fileName,
              'parents': <String>[folderIdOf(parentPath)],
            }),
          )
          .timeout(const Duration(seconds: 30));
      if (initResponse.statusCode < 200 ||
          initResponse.statusCode >= 300) {
        _ensureOk(initResponse, '初始化上传');
      }
      final sessionUri = initResponse.headers['location'] ?? '';
      if (sessionUri.isEmpty) {
        throw StateError('Google 未返回上传会话地址（Location），无法继续上传');
      }

      const int chunkSize = 4 * 1024 * 1024;
      var sent = 0;
      while (sent < total) {
        if (isCancelled != null && await isCancelled()) {
          throw StateError('上传已取消');
        }
        final endExclusive =
            (sent + chunkSize) > total ? total : (sent + chunkSize);
        final chunk = await _readChunk(file, sent, endExclusive);
        final lastByte = endExclusive - 1;
        final request = http.Request('PUT', Uri.parse(sessionUri))
          ..headers.addAll(<String, String>{
            'Content-Length': '${chunk.length}',
            'Content-Range': 'bytes $sent-$lastByte/$total',
            'Content-Type': contentType,
          })
          ..bodyBytes = chunk;
        final streamed = await client
            .send(request)
            .timeout(const Duration(seconds: 180));
        final body = await streamed.stream.bytesToString();
        if (streamed.statusCode == 308) {
          // Resume Incomplete：这一块已被服务端接收，继续下一块。
          sent = endExclusive;
          onProgress?.call(sent, total);
          continue;
        }
        if (streamed.statusCode == 200 || streamed.statusCode == 201) {
          onProgress?.call(total, total);
          final decoded = jsonDecode(body);
          if (decoded is Map) {
            final id = (decoded['id'] ?? '').toString();
            final finalName = (decoded['name'] ?? fileName).toString();
            return RemoteEntry(
              name: finalName,
              path: pathOf(id.isEmpty ? '' : id, finalName),
              isDirectory: false,
              size: total,
            );
          }
          return RemoteEntry(
            name: fileName,
            path: pathOf('', fileName),
            isDirectory: false,
            size: total,
          );
        }
        throw StateError(
          '上传失败（HTTP ${streamed.statusCode}）：${_shortError(body)}',
        );
      }
      throw StateError('上传未正常结束，请重试');
    } finally {
      client.close();
    }
  }

  static Future<Uint8List> _readChunk(
    File file,
    int start,
    int endExclusive,
  ) async {
    final parts = await file.openRead(start, endExclusive).toList();
    var length = 0;
    for (final part in parts) {
      length += part.length;
    }
    final buffer = Uint8List(length);
    var offset = 0;
    for (final part in parts) {
      buffer.setRange(offset, offset + part.length, part);
      offset += part.length;
    }
    return buffer;
  }

  void _ensureOk(http.Response response, String action) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    String hint = '';
    if (response.statusCode == 403) {
      hint = '（可能是该账号没有写入权限，或 OAuth 授权范围不足）';
    } else if (response.statusCode == 404) {
      hint = '（文件或文件夹不存在，或已被移入回收站）';
    }
    throw StateError(
      'Google Drive $action失败（HTTP ${response.statusCode}）$hint：'
      '${_shortError(response.body)}',
    );
  }

  /// 把 Google 的错误正文压缩成一行可读说明（绝不回显凭据）。
  String _shortError(String body) {
    if (body.trim().isEmpty) return '服务端未返回错误详情';
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final error = (decoded['error'] ?? '').toString();
        final description =
            (decoded['error_description'] ?? decoded['message'] ?? '')
                .toString();
        if (error == 'invalid_grant') {
          return 'refresh_token 已失效或被撤销，请在 Google 账号里重新授权';
        }
        if (error == 'invalid_client') {
          return 'client_id / client_secret 不正确';
        }
        if (description.isNotEmpty) return '$error: $description';
        if (error.isNotEmpty) return error;
      }
    } catch (_) {
      // 非 JSON 正文按纯文本处理。
    }
    final plain = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return plain.length > 160 ? '${plain.substring(0, 160)}…' : plain;
  }
}

class _AccessToken {
  const _AccessToken(this.value, this.expiresAt);

  final String value;
  final DateTime expiresAt;
}
