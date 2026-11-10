import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 网络硬盘 / 共享网盘协议。
///
/// 用户口述的「名称以 web 开头的协议」按网络硬盘场景解释为 WebDAV
/// （Web Distributed Authoring and Versioning），这是 NAS / 共享网盘最常用
/// 的 HTTP 文件协议；另一种按用户要求支持 FTP。
enum RemoteSourceType { webdav, ftp }

String remoteSourceTypeLabel(RemoteSourceType type) {
  return switch (type) {
    RemoteSourceType.webdav => 'WebDAV',
    RemoteSourceType.ftp => 'FTP',
  };
}

RemoteSourceType remoteSourceTypeFromName(String? name) {
  return name == 'ftp' ? RemoteSourceType.ftp : RemoteSourceType.webdav;
}

/// 一条网络音乐源连接配置。密码仅保存在本机 shared_preferences，
/// 不随仓库提交，也不会写进日志。
class RemoteSource {
  const RemoteSource({
    required this.id,
    required this.name,
    required this.type,
    required this.host,
    required this.port,
    required this.rootPath,
    this.username = '',
    this.password = '',
    this.useTls = false,
  });

  final String id;
  final String name;
  final RemoteSourceType type;
  final String host;
  final int port;
  final String rootPath;
  final String username;
  final String password;
  final bool useTls;

  static int defaultPort(RemoteSourceType type, bool useTls) {
    return switch (type) {
      RemoteSourceType.webdav => useTls ? 443 : 80,
      RemoteSourceType.ftp => 21,
    };
  }

  bool get isAnonymous => username.trim().isEmpty;

  /// WebDAV 的根 URI。rootPath 必须以 / 结尾，PROPFIND 目录时才能正确解析相对 href。
  Uri get webdavBaseUri {
    var root = rootPath.trim();
    if (root.isEmpty) root = '/';
    if (!root.startsWith('/')) root = '/$root';
    if (!root.endsWith('/')) root = '$root/';
    return Uri(
      scheme: useTls ? 'https' : 'http',
      host: host.trim(),
      port: port,
      path: root,
    );
  }

  String get ftpRoot {
    var root = rootPath.trim();
    if (root.isEmpty) root = '/';
    if (!root.startsWith('/')) root = '/$root';
    return root;
  }

  String get displaySubtitle {
    final scheme = type == RemoteSourceType.webdav
        ? (useTls ? 'https' : 'http')
        : 'ftp';
    return '$scheme://${host.trim()}:$port${rootPath.trim().isEmpty ? '' : rootPath.trim()}';
  }

  RemoteSource copyWith({
    String? name,
    RemoteSourceType? type,
    String? host,
    int? port,
    String? rootPath,
    String? username,
    String? password,
    bool? useTls,
  }) {
    return RemoteSource(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      host: host ?? this.host,
      port: port ?? this.port,
      rootPath: rootPath ?? this.rootPath,
      username: username ?? this.username,
      password: password ?? this.password,
      useTls: useTls ?? this.useTls,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'type': type.name,
        'host': host,
        'port': port,
        'rootPath': rootPath,
        'username': username,
        'password': password,
        'useTls': useTls,
      };

  factory RemoteSource.fromJson(Map<String, dynamic> json) {
    final type = remoteSourceTypeFromName(json['type'] as String?);
    final useTls = json['useTls'] == true;
    final port = (json['port'] as num?)?.toInt();
    return RemoteSource(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '未命名',
      type: type,
      host: (json['host'] as String?) ?? '',
      port: port ?? defaultPort(type, useTls),
      rootPath: (json['rootPath'] as String?) ?? '/',
      username: (json['username'] as String?) ?? '',
      password: (json['password'] as String?) ?? '',
      useTls: useTls,
    );
  }
}

/// 网络源配置的持久化仓库。应用启动时 load 一次，之后全部走内存，
/// 代理端解析 bilibili / NAS 目标时也需要同步查表。
class RemoteSourceStore {
  RemoteSourceStore._();

  static final RemoteSourceStore instance = RemoteSourceStore._();

  static const String _storageKey = 'myune.network.sources.v1';

  final List<RemoteSource> _sources = <RemoteSource>[];
  bool _loaded = false;

  List<RemoteSource> get sources => List<RemoteSource>.unmodifiable(_sources);

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_storageKey) ?? const <String>[];
    _sources.clear();
    for (final item in raw) {
      try {
        final decoded = jsonDecode(item);
        if (decoded is Map<String, dynamic>) {
          final source = RemoteSource.fromJson(decoded);
          if (source.id.isNotEmpty && source.host.isNotEmpty) {
            _sources.add(source);
          }
        }
      } catch (_) {
        // 跳过损坏的历史条目，不影响其它配置。
      }
    }
    _loaded = true;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _storageKey,
      _sources.map((s) => jsonEncode(s.toJson())).toList(),
    );
  }

  Future<void> upsert(RemoteSource source) async {
    await load();
    final index = _sources.indexWhere((s) => s.id == source.id);
    if (index >= 0) {
      _sources[index] = source;
    } else {
      _sources.add(source);
    }
    await _persist();
  }

  Future<void> remove(String id) async {
    await load();
    _sources.removeWhere((s) => s.id == id);
    await _persist();
  }

  RemoteSource? byId(String id) {
    for (final source in _sources) {
      if (source.id == id) return source;
    }
    return null;
  }
}
