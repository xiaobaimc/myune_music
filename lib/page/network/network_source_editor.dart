import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../services/network/network_media_service.dart';
import '../../services/network/remote_source.dart';

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
  }

  @override
  void dispose() {
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

  /// Google Drive 原生接入的凭据字段（应用内原生界面，不依赖网页 / 命令行）。
  List<Widget> _driveFields(ColorScheme scheme) {
    return <Widget>[
      const SizedBox(height: 12),
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
        decoration: const InputDecoration(
          labelText: 'refresh_token',
          border: OutlineInputBorder(),
          isDense: true,
        ),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _rootFolderId,
        decoration: const InputDecoration(
          labelText: '根文件夹 ID（留空为整个云端硬盘）',
          hintText: '例如：1AbCdEfGhIjKlMnOpQrStUvWxYz012345',
          border: OutlineInputBorder(),
          isDense: true,
        ),
      ),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          '安全提示：refresh_token 等同于该 Google 账号 Drive 的永久读写权限。'
          '它只保存在本机设置里，不会随程序分发、不会写进日志、也不会提交到仓库；'
          '请勿外发或截图。',
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
