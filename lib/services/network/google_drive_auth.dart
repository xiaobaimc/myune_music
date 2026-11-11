import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// 一次网页 OAuth 登录的结果。
///
/// [refreshToken] 是需要长期保存在本机的凭据；[accessToken] 只用于
/// 登录完成后立刻查询账号信息，不会被持久化，也不会写进日志。
class GoogleDriveAuthResult {
  const GoogleDriveAuthResult({
    required this.clientId,
    required this.clientSecret,
    required this.refreshToken,
    required this.accessToken,
    this.email = '',
    this.displayName = '',
    this.scope = '',
  });

  final String clientId;
  final String clientSecret;
  final String refreshToken;
  final String accessToken;
  final String email;
  final String displayName;
  final String scope;

  String get accountLabel =>
      email.isNotEmpty ? email : (displayName.isNotEmpty ? displayName : 'Google 账号');
}

/// Google OAuth 2.0「Loopback IP address」流程（桌面应用官方推荐方式）。
///
/// 工作流程：
/// 1. 在 `127.0.0.1` 上起一个临时 HTTP 服务，端口从 53682 起顺延；
/// 2. 用系统默认浏览器打开 Google 授权页（`access_type=offline` +
///    `prompt=consent`，确保每次都能拿到 refresh_token）；
/// 3. 用户在网页里登录并同意后，Google 把 `code` 重定向回本机服务；
/// 4. 用 `code` + client_id/client_secret 换 access_token / refresh_token；
/// 5. 用 access_token 查一下账号邮箱，关掉临时服务，返回结果。
///
/// 仓库里不包含任何 client_id / client_secret；它们要么由用户在界面里填，
/// 要么从用户自己放在本机的 `文档/myune_music/google_drive.json` 读取。
class GoogleDriveAuth {
  GoogleDriveAuth._();

  /// 需要的权限：完整 Drive 读写（列目录、下载、上传、删除、新建文件夹）。
  /// 注意：这是 Google 的「受限范围」，未通过 OAuth 验证的应用在授权页会显示
  /// 「此应用未经验证」，把账号加入该 OAuth 客户端的测试用户即可继续。
  static const String scope = 'https://www.googleapis.com/auth/drive';

  static const String _authEndpoint =
      'https://accounts.google.com/o/oauth2/v2/auth';
  static const String _tokenEndpoint = 'https://oauth2.googleapis.com/token';
  static const String _aboutEndpoint =
      'https://www.googleapis.com/drive/v3/about';

  /// 优先使用的端口。Google 对「桌面应用」类型的 OAuth 客户端允许任意
  /// loopback 端口；对「Web 应用」类型则需要在 Cloud Console 里登记精确的
  /// 重定向 URI，因此这里固定从 53682 起顺延，方便一次登记即可长期使用。
  static const int _firstPort = 53682;
  static const int _portAttempts = 12;

  static const Duration _timeout = Duration(minutes: 5);

  /// 启动一次网页登录。[onStatus] 用于把「已打开浏览器 / 等待授权 / 正在换取令牌」
  /// 这类进度回显到界面上。
  static Future<GoogleDriveAuthResult> signIn({
    required String clientId,
    required String clientSecret,
    void Function(String message)? onStatus,
    Future<bool> Function()? isCancelled,
  }) async {
    final id = clientId.trim();
    final secret = clientSecret.trim();
    if (id.isEmpty || secret.isEmpty) {
      throw ArgumentError('请先填写 OAuth client_id 与 client_secret');
    }

    HttpServer? server;
    StreamSubscription<HttpRequest>? subscription;
    var port = 0;
    for (var attempt = 0; attempt < _portAttempts; attempt++) {
      try {
        server = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          _firstPort + attempt,
          shared: false,
        );
        port = server.port;
        break;
      } on SocketException {
        // 端口被占用就顺延，最多尝试 _portAttempts 个。
      }
    }
    if (server == null) {
      throw StateError(
        '本机 $_firstPort-${_firstPort + _portAttempts - 1} 端口都被占用，'
        '无法启动 OAuth 回调服务；请关闭占用程序后重试',
      );
    }

    final redirectUri = 'http://127.0.0.1:$port/';
    final state = _randomState();
    final callback = Completer<_Callback>();

    void handle(HttpRequest request) {
      if (callback.isCompleted) {
        unawaited(_respond(request, false, '该授权请求已被处理，请关闭本页。'));
        return;
      }
      final params = request.uri.queryParameters;
      final error = params['error'] ?? '';
      if (error.isNotEmpty) {
        callback.complete(
          _Callback(error: '授权被拒绝或取消：$error'),
        );
        unawaited(_respond(request, false, '授权未完成：$error，可以关闭本页。'));
        return;
      }
      if (params['state'] != state) {
        callback.complete(
          const _Callback(error: 'state 校验失败，已拒绝该回调（可能为伪造请求）'),
        );
        unawaited(_respond(request, false, '校验失败，已拒绝该回调。'));
        return;
      }
      final code = params['code'] ?? '';
      if (code.isEmpty) {
        callback.complete(
          const _Callback(error: 'Google 未返回授权码 code'),
        );
        unawaited(_respond(request, false, '未收到授权码，请返回应用重试。'));
        return;
      }
      callback.complete(_Callback(code: code));
      unawaited(
        _respond(request, true, '授权成功，可以关闭本页并回到 Myune Music。'),
      );
    }

    try {
      subscription = server.listen(handle);

      final authUri = Uri.parse(_authEndpoint).replace(
        queryParameters: <String, String>{
          'client_id': id,
          'redirect_uri': redirectUri,
          'response_type': 'code',
          'scope': scope,
          'access_type': 'offline',
          'prompt': 'consent',
          'include_granted_scopes': 'true',
          'state': state,
        },
      );

      onStatus?.call('正在打开浏览器，请在网页里登录并授权…');
      final launched = await launchUrl(
        authUri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw StateError(
          '无法打开系统浏览器。请手动复制下面的地址到浏览器完成授权：\n$authUri',
        );
      }

      onStatus?.call('等待网页授权完成（最多 5 分钟）…');
      final cb = await callback.future.timeout(
        _timeout,
        onTimeout: () => throw TimeoutException(
          '等待网页授权超时（5 分钟），请重新发起登录',
        ),
      );
      if (cb.error != null) throw StateError(cb.error!);

      // 用户可能在别处点了「取消」，授权完成后再确认一次。
      if (isCancelled != null && await isCancelled()) {
        throw StateError('已取消登录');
      }

      onStatus?.call('正在换取访问令牌…');
      final tokens = await _exchange(
        code: cb.code!,
        clientId: id,
        clientSecret: secret,
        redirectUri: redirectUri,
      );
      if (tokens.refreshToken.isEmpty) {
        throw StateError(
          'Google 没有返回 refresh_token。请确认授权时勾选了「离线访问」，'
          '或先到 Google 账号「安全性 → 第三方应用访问权限」撤销本应用后重试',
        );
      }

      onStatus?.call('正在读取账号信息…');
      final user = await _about(tokens.accessToken);
      return GoogleDriveAuthResult(
        clientId: id,
        clientSecret: secret,
        refreshToken: tokens.refreshToken,
        accessToken: tokens.accessToken,
        email: user.$1,
        displayName: user.$2,
        scope: tokens.scope,
      );
    } finally {
      await subscription?.cancel();
      await server.close(force: true);
    }
  }

  static Future<_Tokens> _exchange({
    required String code,
    required String clientId,
    required String clientSecret,
    required String redirectUri,
  }) async {
    final response = await http
        .post(
          Uri.parse(_tokenEndpoint),
          headers: <String, String>{
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: <String, String>{
            'code': code,
            'client_id': clientId,
            'client_secret': clientSecret,
            'redirect_uri': redirectUri,
            'grant_type': 'authorization_code',
          },
        )
        .timeout(const Duration(seconds: 30));
    final body = response.body;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('换取令牌失败（HTTP ${response.statusCode}）：${_short(body)}');
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map) throw StateError('Google 返回的令牌格式异常');
    return _Tokens(
      accessToken: (decoded['access_token'] ?? '').toString(),
      refreshToken: (decoded['refresh_token'] ?? '').toString(),
      scope: (decoded['scope'] ?? '').toString(),
    );
  }

  static Future<(String, String)> _about(String accessToken) async {
    try {
      final response = await http
          .get(
            Uri.parse(_aboutEndpoint).replace(
              queryParameters: <String, String>{
                'fields': 'user(emailAddress,displayName)',
              },
            ),
            headers: <String, String>{
              'Authorization': 'Bearer $accessToken',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return ('', '');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['user'] is Map) {
        final user = decoded['user'] as Map;
        return (
          (user['emailAddress'] ?? '').toString(),
          (user['displayName'] ?? '').toString(),
        );
      }
      return ('', '');
    } catch (_) {
      return ('', '');
    }
  }

  static Future<void> _respond(
    HttpRequest request,
    bool ok,
    String message,
  ) async {
    try {
      final title = ok ? '授权成功' : '授权未完成';
      final color = ok ? '#1a7f37' : '#b3261e';
      final html = '<!doctype html><html lang="zh-CN"><head>'
          '<meta charset="utf-8"><title>$title</title>'
          '<style>body{font-family:system-ui,"Microsoft YaHei",sans-serif;'
          'background:#f6f7f9;color:#1f1f1f;display:flex;align-items:center;'
          'justify-content:center;height:100vh;margin:0}'
          '.card{background:#fff;border-radius:12px;padding:32px 40px;'
          'box-shadow:0 2px 12px rgba(0,0,0,.08);max-width:420px;text-align:center}'
          'h1{font-size:20px;margin:0 0 12px;color:$color}'
          'p{font-size:14px;line-height:1.7;color:#555;margin:0}'
          '</style></head><body><div class="card">'
          '<h1>$title</h1><p>${_htmlEscape(message)}</p>'
          '</div></body></html>';
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.html
        ..write(html);
      await request.response.close();
    } catch (_) {
      // 用户可能已经关掉浏览器标签，忽略响应写入失败。
    }
  }

  static String _htmlEscape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static String _short(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final error = (decoded['error'] ?? '').toString();
        final description = (decoded['error_description'] ?? '').toString();
        if (description.isNotEmpty) return '$error: $description';
        if (error.isNotEmpty) return error;
      }
    } catch (_) {
      // 非 JSON 正文按纯文本处理。
    }
    final plain = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return plain.length > 200 ? '${plain.substring(0, 200)}…' : plain;
  }

  static String _randomState() {
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

class _Callback {
  const _Callback({this.code, this.error});

  final String? code;
  final String? error;
}

class _Tokens {
  const _Tokens({
    required this.accessToken,
    required this.refreshToken,
    required this.scope,
  });

  final String accessToken;
  final String refreshToken;
  final String scope;
}
