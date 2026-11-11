import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../services/network/google_drive_auth.dart';
import '../../services/network/network_media_service.dart';
import '../../services/network/remote_source.dart';
import 'google_drive_folder_picker.dart';

/// 网络源的新增 / 编辑对话框。
///
/// 只依赖 Material 基础控件，不引入额外依赖；密码保存在本机
/// shared_preferences 中，不会写进日志或随仓库提交。
Future<RemoteSource?> showRemoteSourceEditor(
  BuildContext context, {
  RemoteSource? existing,
}) {
  return showDialog<RemoteSource>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _RemoteSourceEditor(existing: existing),
  );
}

class _RemoteSourceEditor extends StatefulWidget {
  const _RemoteSourceEditor({this.existing});

  final RemoteSource? existing;

  @override
  State<_RemoteSourceEditor> createState() => _RemoteSourceEditorState();
}

class _RemoteSourceEditorState extends State<_RemoteSourceEditor> {
  late final TextEditingController _name;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _rootPath;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late final TextEditingController _clientId;
  late final TextEditingController _clientSecret;
  late final TextEditingController _refreshToken;
  late final TextEditingController _rootFolderId;

  late RemoteSourceType _type;
  late bool _useTls;

  bool _obscurePassword = true;
  bool _testing = false;
  String? _testMessage;
  bool _testOk = false;

  bool _signingIn = false;
  bool _pickingFolder = false;
  String _loggedInEmail = '';
  String _rootFolderLabel = '';
  final ValueNotifier<String> _authStatus = ValueNotifier<String>('');

  @override
  void initState() {
    super.initState();
    final source = widget.existing;
    _type = source?.type ?? RemoteSourceType.webdav;
    _useTls = source?.useTls ?? false;
    _name = TextEditingController(text: source?.name ?? '');
    _host = TextEditingController(text: source?.host ?? '');
    _port = TextEditingController(
      text: (source?.port ?? RemoteSource.defaultPort(_type, _useTls))
          .toString(),
    );
    _rootPath = TextEditingController(text: source?.rootPath ?? '/');
    _username = TextEditingController(text: source?.username ?? '');
    _password = TextEditingController(text: source?.password ?? '');
    _clientId = TextEditingController(text: source?.clientId ?? '');
    _clientSecret = TextEditingController(text: source?.clientSecret ?? '');
    _refreshToken = TextEditingController(text: source?.refreshToken ?? '');
    _rootFolderId = TextEditingController(text: source?.rootFolderId ?? '');
    if (source?.isGoogleDrive ?? false) {
      _loggedInEmail = '';
      _rootFolderLabel = source?.rootFolderName ?? '';
    }
  }

  @override
  void dispose() {
    _authStatus.dispose();
    _name.dispose();
    _host.dispose();
    _port.dispose();
    _rootPath.dispose();
    _username.dispose();
    _password.dispose();
    _clientId.dispose();
    _clientSecret.dispose();
    _refreshToken.dispose();
    _rootFolderId.dispose();
    super.dispose();
  }

  void _applyType(RemoteSourceType type) {
    setState(() {
      _type = type;
      if (type == RemoteSourceType.ftp) {
        _useTls = false;
        _port.text = RemoteSource.defaultPort(type, false).toString();
      } else if (type == RemoteSourceType.googleDrive) {
        _useTls = true;
        _port.text = '443';
        if (_name.text.trim().isEmpty) _name.text = 'Google Drive';
      } else {
        _port.text = RemoteSource.defaultPort(type, _useTls).toString();
      }
      _testMessage = null;
    });
  }

  RemoteSource? _build({bool requireHost = true}) {
    // Google Drive 走官方 API，没有服务器地址 / 端口 / 账号密码，
    // 只需要 OAuth 三件套与可选的根文件夹 ID。
    if (_type == RemoteSourceType.googleDrive) {
      final clientId = _clientId.text.trim();
      final clientSecret = _clientSecret.text.trim();
      final refreshToken = _refreshToken.text.trim();
      if (clientId.isEmpty || clientSecret.isEmpty || refreshToken.isEmpty) {
        setState(() {
          _testOk = false;
          _testMessage = '请填写 OAuth 凭据（client_id / client_secret / '
              'refresh_token），或点「从本机文件导入」';
        });
        return null;
      }
      final name = _name.text.trim();
      return RemoteSource(
        id: widget.existing?.id ?? const Uuid().v4(),
        name: name.isEmpty ? 'Google Drive' : name,
        type: RemoteSourceType.googleDrive,
        host: 'www.googleapis.com',
        port: 443,
        rootPath: '/',
        useTls: true,
        clientId: clientId,
        clientSecret: clientSecret,
        refreshToken: refreshToken,
        rootFolderId: _rootFolderId.text.trim(),
        rootFolderName: _rootFolderId.text.trim().isEmpty
            ? ''
            : _rootFolderLabel.trim(),
      );
    }
    final host = _host.text.trim();
    if (requireHost && host.isEmpty) {
      setState(() {
        _testOk = false;
        _testMessage = '请填写服务器地址（IP 或域名）';
      });
      return null;
    }
    final name = _name.text.trim();
    final port = int.tryParse(_port.text.trim()) ??
        RemoteSource.defaultPort(_type, _useTls);
    var root = _rootPath.text.trim();
    if (root.isEmpty) root = '/';
    return RemoteSource(
      id: widget.existing?.id ?? const Uuid().v4(),
      name: name.isEmpty ? host : name,
      type: _type,
      host: host,
      port: port,
      rootPath: root,
      username: _username.text.trim(),
      password: _password.text,
      useTls: _useTls,
    );
  }

  /// 从本机文件一键导入 Google Drive 凭据。
  ///
  /// 文件位于 `<文档>/myune_music/google_drive.json`，由用户自己放在本机，
  /// 不随程序分发、不写进日志、更不会提交到仓库。这样超长的
  /// refresh_token 不用手抄，也不会出现在任何代码里。
  Future<void> _importFromFile() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final file = File(
        p.join(docs.path, 'myune_music', 'google_drive.json'),
      );
      if (!await file.exists()) {
        setState(() {
          _testOk = false;
          _testMessage = '未找到本机凭据文件：${file.path}';
        });
        return;
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        throw StateError('文件内容不是 JSON 对象');
      }
      String text(String key) => (decoded[key] ?? '').toString().trim();
      setState(() {
        _clientId.text = text('clientId');
        _clientSecret.text = text('clientSecret');
        _refreshToken.text = text('refreshToken');
        _rootFolderId.text = text('rootFolderId');
        _rootFolderLabel = text('rootFolderName');
        if (_name.text.trim().isEmpty) _name.text = 'Google Drive';
        _testOk = true;
        _testMessage = '已从本机文件导入凭据（不会上传，也不会写进日志）';
      });
    } catch (error) {
      setState(() {
        _testOk = false;
        _testMessage = '导入失败：$error';
      });
    }
  }

  /// 本机凭据文件句柄（目录不存在时创建）。
  Future<File> _credentialsFile() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'myune_music'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return File(p.join(dir.path, 'google_drive.json'));
  }

  /// 网页登录只强制需要 client_id / client_secret。若界面里还没填，
  /// 先尝试从用户自己放在本机的 google_drive.json 里补齐这两项。
  Future<void> _ensureClientCredentials() async {
    if (_clientId.text.trim().isNotEmpty &&
        _clientSecret.text.trim().isNotEmpty) {
      return;
    }
    try {
      final file = await _credentialsFile();
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return;
      if (!mounted) return;
      setState(() {
        if (_clientId.text.trim().isEmpty) {
          _clientId.text = (decoded['clientId'] ?? '').toString().trim();
        }
        if (_clientSecret.text.trim().isEmpty) {
          _clientSecret.text = (decoded['clientSecret'] ?? '').toString().trim();
        }
      });
    } catch (_) {
      // 文件损坏时保持界面原状，由用户手动填写。
    }
  }

  /// 网页登录成功后把凭据写回本机文件，下次可直接「从本机文件导入」。
  /// 这个文件只在本机，不进仓库、不写日志。
  Future<void> _saveCredentials({
    required String clientId,
    required String clientSecret,
    required String refreshToken,
  }) async {
    try {
      final file = await _credentialsFile();
      await file.writeAsString(
        jsonEncode(<String, String>{
          'clientId': clientId,
          'clientSecret': clientSecret,
          'refreshToken': refreshToken,
          'rootFolderId': _rootFolderId.text.trim(),
          'rootFolderName': _rootFolderLabel.trim(),
        }),
      );
    } catch (_) {
      // 写文件失败不影响本次登录结果，凭据仍保存在 shared_preferences。
    }
  }

  /// 通过系统浏览器完成 OAuth 授权（loopback 回调），自动填入 refresh_token。
  Future<void> _signInWithBrowser() async {
    if (_signingIn) return;
    await _ensureClientCredentials();
    final id = _clientId.text.trim();
    final secret = _clientSecret.text.trim();
    if (id.isEmpty || secret.isEmpty) {
      setState(() {
        _testOk = false;
        _testMessage = '网页登录需要 OAuth client_id 与 client_secret。'
            '请先点「从本机文件导入凭据」，或在「手动填写凭据」里填好这两项。';
      });
      return;
    }

    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('网页登录 Google Drive'),
        content: const SizedBox(
          width: 460,
          child: Text(
            '接下来会打开系统浏览器，请在 Google 页面登录并点「允许」。\n\n'
                '授权完成后浏览器会跳回 127.0.0.1 的本机回调页，应用会自动取得 '
                'refresh_token 并填好，不需要复制粘贴。\n\n'
                '若授权页提示 redirect_uri_mismatch：到 Google Cloud Console 把 '
                'http://127.0.0.1:53682/ 加入该 OAuth 客户端的「已获授权的重定向 URI」'
                '（客户端类型为「桌面应用」时无需登记）。\n\n'
                '若提示「此应用未经验证」，把你的账号加入该客户端的测试用户即可继续。',
            style: TextStyle(fontSize: 12, height: 1.6),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('打开浏览器登录'),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;

    var cancelled = false;
    var dialogClosed = false;
    BuildContext? progressContext;

    void closeProgress() {
      if (dialogClosed) return;
      dialogClosed = true;
      final ctx = progressContext;
      if (ctx != null && ctx.mounted) Navigator.of(ctx).pop();
    }

    _authStatus.value = '准备打开浏览器…';
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          progressContext = ctx;
          return AlertDialog(
            title: const Text('Google Drive 网页登录'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const LinearProgressIndicator(),
                const SizedBox(height: 14),
                ValueListenableBuilder<String>(
                  valueListenable: _authStatus,
                  builder: (_, value, __) => Text(
                    value,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '登录完成后本窗口会自动关闭；也可以点「取消」中止。',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () {
                  cancelled = true;
                  dialogClosed = true;
                  Navigator.of(ctx).pop();
                },
                child: const Text('取消'),
              ),
            ],
          );
        },
      ),
    );

    setState(() {
      _signingIn = true;
      _testMessage = null;
    });
    try {
      final result = await GoogleDriveAuth.signIn(
        clientId: id,
        clientSecret: secret,
        onStatus: (message) => _authStatus.value = message,
        isCancelled: () async => cancelled,
      );
      if (!mounted) return;
      setState(() {
        _clientId.text = result.clientId;
        _clientSecret.text = result.clientSecret;
        _refreshToken.text = result.refreshToken;
        if (_name.text.trim().isEmpty) _name.text = 'Google Drive';
        _loggedInEmail = result.email;
        _testOk = true;
        _testMessage =
            '网页登录成功（${result.accountLabel}），凭据已自动填入并保存到本机';
      });
      await _saveCredentials(
        clientId: result.clientId,
        clientSecret: result.clientSecret,
        refreshToken: result.refreshToken,
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _testOk = false;
          _testMessage = '网页登录失败：$error';
        });
      }
    } finally {
      closeProgress();
      if (mounted) setState(() => _signingIn = false);
    }
  }

  /// 打开图形化文件夹树，选择「默认读取的文件夹」。
  Future<void> _pickFolder() async {
    if (_pickingFolder) return;
    final refresh = _refreshToken.text.trim();
    if (refresh.isEmpty) {
      setState(() {
        _testOk = false;
        _testMessage = '请先完成网页登录（或填入 refresh_token）后再浏览文件夹';
      });
      return;
    }
    await _ensureClientCredentials();
    setState(() => _pickingFolder = true);
    try {
      final temp = RemoteSource(
        id: widget.existing?.id ?? 'picker',
        name: 'Google Drive',
        type: RemoteSourceType.googleDrive,
        host: 'www.googleapis.com',
        port: 443,
        rootPath: '/',
        useTls: true,
        clientId: _clientId.text.trim(),
        clientSecret: _clientSecret.text.trim(),
        refreshToken: refresh,
        rootFolderId: _rootFolderId.text.trim(),
      );
      final pick = await showGoogleDriveFolderPicker(
        context,
        source: temp,
        initialFolderId: _rootFolderId.text.trim(),
      );
      if (pick == null || !mounted) return;
      setState(() {
        _rootFolderId.text = pick.id;
        _rootFolderLabel = pick.id.isEmpty ? '' : pick.name;
        _testOk = true;
        _testMessage = '默认读取文件夹已设为：${pick.pathLabel}';
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _testOk = false;
          _testMessage = '打开文件夹选择器失败：$error';
        });
      }
    } finally {
      if (mounted) setState(() => _pickingFolder = false);
    }
  }

  Future<void> _test() async {
    final source = _build();
    if (source == null) return;
    setState(() {
      _testing = true;
      _testMessage = null;
    });
    try {
      final count = await NetworkMediaService.testConnection(source);
      if (!mounted) return;
      setState(() {
        _testOk = true;
        _testMessage = '连接成功，根目录有 $count 个条目';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _testOk = false;
        _testMessage = '连接失败：$error';
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  void _save() {
    final source = _build();
    if (source == null) return;
    Navigator.of(context).pop(source);
  }

  /// Google Drive 区域：网页登录 + 图形化选文件夹 + 手动凭据（高级）。
  List<Widget> _driveFields(ColorScheme scheme) {
    final signedIn = _refreshToken.text.trim().isNotEmpty;
    return <Widget>[
      const SizedBox(height: 14),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              signedIn
                  ? Icons.verified_user_outlined
                  : Icons.login_outlined,
              size: 20,
              color: scheme.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    signedIn
                        ? (_loggedInEmail.isNotEmpty
                            ? '已授权：$_loggedInEmail'
                            : '已填入长期凭据')
                        : '尚未登录 Google 账号',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '网页登录会自动取得 refresh_token，无需复制粘贴',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      FilledButton.icon(
        onPressed: _signingIn ? null : _signInWithBrowser,
        icon: _signingIn
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.public, size: 18),
        label: Text(_signingIn ? '正在等待网页授权…' : '网页登录 Google 账号'),
      ),
      const SizedBox(height: 4),
      Text(
        '会打开系统浏览器完成 Google 授权，授权后自动回到应用；'
        '授权范围包含 Drive 读写，以便上传 / 删除文件。',
        style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
      ),
      const SizedBox(height: 14),
      Text(
        '默认读取的文件夹',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
      const SizedBox(height: 6),
      Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: _rootFolderId,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: '文件夹 ID（留空为整个云端硬盘）',
                helperText: '也可以点右侧「浏览」在 Drive 里直接选',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _pickingFolder ? null : _pickFolder,
            icon: _pickingFolder
                ? const SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.folder_open_outlined, size: 16),
            label: const Text('浏览…'),
          ),
        ],
      ),
      if (_rootFolderLabel.trim().isNotEmpty &&
          _rootFolderId.text.trim().isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: <Widget>[
              Icon(Icons.check_circle_outline,
                  size: 14, color: scheme.primary),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  '当前默认文件夹：$_rootFolderLabel',
                  style: TextStyle(fontSize: 11, color: scheme.primary),
                ),
              ),
            ],
          ),
        ),
      const SizedBox(height: 10),
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(top: 4, bottom: 4),
        shape: const Border(),
        collapsedShape: const Border(),
        title: const Text(
          '手动填写 / 导入凭据（高级）',
          style: TextStyle(fontSize: 12.5),
        ),
        children: <Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _importFromFile,
              icon: const Icon(Icons.file_open_outlined, size: 16),
              label: const Text('从本机文件导入凭据'),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _clientId,
            decoration: const InputDecoration(
              labelText: 'OAuth client_id',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _clientSecret,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: 'OAuth client_secret',
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: IconButton(
                tooltip: _obscurePassword ? '显示' : '隐藏',
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 18,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _refreshToken,
            obscureText: _obscurePassword,
            maxLines: 2,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'refresh_token',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ],
      ),
      const SizedBox(height: 6),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          '安全说明：refresh_token 等同于该 Google 账号 Drive 的长期读写权限。'
          '它只保存在本机设置与 文档/myune_music/google_drive.json，'
          '不会随程序分发、不会写进日志、也不会提交到仓库；请勿外发或截图。',
          style: TextStyle(
            fontSize: 11,
            height: 1.5,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDrive = _type == RemoteSourceType.googleDrive;
    return AlertDialog(
      title: Text(widget.existing == null ? '添加网络源' : '编辑网络源'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SegmentedButton<RemoteSourceType>(
                segments: const <ButtonSegment<RemoteSourceType>>[
                  ButtonSegment<RemoteSourceType>(
                    value: RemoteSourceType.webdav,
                    label: Text('WebDAV'),
                    icon: Icon(Icons.cloud_outlined),
                  ),
                  ButtonSegment<RemoteSourceType>(
                    value: RemoteSourceType.ftp,
                    label: Text('FTP'),
                    icon: Icon(Icons.dns_outlined),
                  ),
                  ButtonSegment<RemoteSourceType>(
                    value: RemoteSourceType.googleDrive,
                    label: Text('Google Drive'),
                    icon: Icon(Icons.drive_folder_upload_outlined),
                  ),
                ],
                selected: <RemoteSourceType>{_type},
                onSelectionChanged: (Set<RemoteSourceType> value) {
                  if (value.isEmpty) return;
                  _applyType(value.first);
                },
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: '显示名称',
                  hintText: '例如：家里的 NAS',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              if (isDrive) ..._driveFields(scheme),
              if (!isDrive) ...<Widget>[
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _host,
                      decoration: const InputDecoration(
                        labelText: '服务器地址',
                        hintText: '192.168.1.10 或 nas.example.com',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 96,
                    child: TextField(
                      controller: _port,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '端口',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _rootPath,
                decoration: InputDecoration(
                  labelText: '根路径',
                  hintText: _type == RemoteSourceType.webdav
                      ? '/dav 或 /remote.php/dav/files/用户名'
                      : '/music',
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _username,
                      decoration: const InputDecoration(
                        labelText: '用户名（留空为匿名）',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _password,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: '密码',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        suffixIcon: IconButton(
                          tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 18,
                          ),
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (_type == RemoteSourceType.webdav) ...<Widget>[
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: _useTls,
                  title: const Text('使用 HTTPS（TLS）'),
                  subtitle: const Text('群晖 / Nextcloud 等启用 HTTPS 时打开'),
                  onChanged: (bool value) {
                    setState(() {
                      _useTls = value;
                      _port.text = RemoteSource.defaultPort(_type, value)
                          .toString();
                      _testMessage = null;
                    });
                  },
                ),
              ],
              ],
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _type == RemoteSourceType.webdav
                      ? 'WebDAV 需要服务端已开启 WebDAV 服务；'
                          '群晖在「套件中心 → WebDAV Server」，'
                          '根路径通常为 /，端口 5005（HTTP）/ 5006（HTTPS）。'
                      : _type == RemoteSourceType.googleDrive
                          ? 'Google Drive 走官方 Drive API v3，原生支持拖动进度；'
                              '凭据只保存在本机，不随程序分发、不写日志。'
                              '根文件夹 ID 留空则打开整个「我的云端硬盘」。'
                          : 'FTP 使用被动模式（PASV）与二进制传输；'
                              '只支持明文 FTP，暂不支持 FTPS / SFTP。',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (_testMessage != null) ...<Widget>[
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      _testOk
                          ? Icons.check_circle_outline
                          : Icons.error_outline,
                      size: 16,
                      color: _testOk ? scheme.primary : scheme.error,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _testMessage!,
                        style: TextStyle(
                          fontSize: 11,
                          color: _testOk ? scheme.primary : scheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _testing ? null : _test,
          child: _testing
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('测试连接'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('保存'),
        ),
      ],
    );
  }
}
