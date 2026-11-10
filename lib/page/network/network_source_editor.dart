import 'package:flutter/material.dart';
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
  }

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _port.dispose();
    _rootPath.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  void _applyType(RemoteSourceType type) {
    setState(() {
      _type = type;
      if (type == RemoteSourceType.ftp) {
        _useTls = false;
        _port.text = RemoteSource.defaultPort(type, false).toString();
      } else {
        _port.text = RemoteSource.defaultPort(type, _useTls).toString();
      }
      _testMessage = null;
    });
  }

  RemoteSource? _build({bool requireHost = true}) {
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(widget.existing == null ? '添加网络源' : '编辑网络源'),
      content: SizedBox(
        width: 460,
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
