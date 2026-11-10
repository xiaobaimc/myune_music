import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'remote_entry.dart';
import 'remote_source.dart';
import 'remote_stream.dart';

/// 极简 FTP 客户端，直接基于 dart:io 的控制连接 + PASV 数据连接实现，
/// 不引入任何 FTP/WebDAV pub 依赖。
///
/// 支持匿名登录、USER/PASS、TYPE I、PASV、LIST、SIZE、REST、RETR，
/// 其中 REST 用来响应本机代理的 Range 请求，实现网络流的拖动进度。
class FtpClient {
  FtpClient(this.source);

  final RemoteSource source;

  static final RegExp _unixRe = RegExp(
    r'^([d\-l])[rwxstST\-]{9}\s+\d+\s+\S+\s+\S+\s+(\d+)\s+'
    r'([A-Za-z]{3}\s+\d{1,2}\s+(?:\d{2}:\d{2}|\d{4}))\s+(.+)$',
  );
  static final RegExp _unixLooseRe = RegExp(
    r'^([d\-l])[rwxstST\-]{9}\s+(.+)$',
  );
  static final RegExp _dosRe = RegExp(
    r'^\d{2,4}-\d{2}-\d{2,4}\s+\d{1,2}:\d{2}(?::\d{2})?(?:AM|PM)?\s+'
    r'(<DIR>|\d+)\s+(.+)$',
    caseSensitive: false,
  );

  Future<_FtpSession> _connect() async {
    final socket = await Socket.connect(
      source.host.trim(),
      source.port,
      timeout: const Duration(seconds: 15),
    );
    final control = _FtpControl(socket);
    try {
      await control.readReply(); // 220 欢迎语
      final user = source.username.trim().isEmpty
          ? 'anonymous'
          : source.username.trim();
      final pass = source.username.trim().isEmpty
          ? 'anonymous@starnote.local'
          : source.password;
      final userReply = await control.send('USER $user');
      // 有些服务器 USER 直接返回 230 完成登录，此时不能再发 PASS。
      if (!userReply.startsWith('230')) {
        await control.send('PASS $pass');
      }
      await control.send('TYPE I');
      return _FtpSession(socket, control);
    } catch (_) {
      control.dispose();
      socket.destroy();
      rethrow;
    }
  }

  /// 列出 [dirPath] 目录。首次进入传配置里的 ftpRoot。
  Future<List<RemoteEntry>> list(String dirPath) async {
    final session = await _connect();
    try {
      final data = await session.openDataConnection();
      await session.control.send('LIST $dirPath');
      final builder = BytesBuilder(copy: false);
      await for (final chunk in data) {
        builder.add(chunk);
      }
      await session.drainCompletionReply();
      final text = utf8.decode(builder.takeBytes(), allowMalformed: true);
      return _parseList(text, dirPath);
    } finally {
      await session.close();
    }
  }

  /// 打开一个远端文件，支持 REST 起点与本地截断终点。
  Future<RemoteStreamResult> open(
    String remotePath, {
    int? start,
    int? end,
    Duration headerTimeout = const Duration(seconds: 25),
  }) async {
    final session = await _connect();
    try {
      final total = await session.control.size(remotePath);
      // FTP 协议要求 REST 之后紧跟 RETR。先建立数据连接（PASV），再 REST，
      // 最后 RETR；旧实现把 PASV 夹在 REST 和 RETR 之间，部分 NAS 会因此
      // 重置重启点，Range 请求实际从 0 开始，mpv 拖动进度后报 loading failed。
      final data = await session.openDataConnection();
      if (start != null && start > 0) {
        await session.control.send('REST $start');
      }
      await session.control.send('RETR $remotePath');

      final servedStart = start ?? 0;
      int? servedEnd = end;
      if (total != null && total > 0) {
        final maxEnd = total - 1;
        if (servedEnd == null || servedEnd > maxEnd) servedEnd = maxEnd;
      }
      int? limit;
      if (servedEnd != null && servedEnd >= servedStart) {
        limit = servedEnd - servedStart + 1;
      } else if (total != null && total > servedStart) {
        limit = total - servedStart;
      }

      return RemoteStreamResult(
        bytes: limitByteStream(data.cast<List<int>>(), limit),
        totalLength: total,
        servedStart: servedStart,
        servedEnd: servedEnd,
        contentType: guessContentType(
          remoteEntryName(remotePath, isDirectory: false),
        ),
        close: session.close,
      );
    } catch (_) {
      await session.close();
      rethrow;
    }
  }

  /// 探测：登录 + SIZE + 只读一个数据块就断开。
  Future<RemoteProbeResult> probe(String remotePath) async {
    final stopwatch = Stopwatch()..start();
    _FtpSession? session;
    try {
      session = await _connect();
      final total = await session.control.size(remotePath);
      final data = await session.openDataConnection();
      await session.control.send('RETR $remotePath');
      await data.first.timeout(const Duration(seconds: 15));
      stopwatch.stop();
      return RemoteProbeResult(
        ok: true,
        statusCode: 226,
        elapsedMs: stopwatch.elapsedMilliseconds,
        totalLength: total,
        supportsRange: true,
        contentType: guessContentType(
          remoteEntryName(remotePath, isDirectory: false),
        ),
      );
    } catch (error) {
      stopwatch.stop();
      return RemoteProbeResult(
        ok: false,
        statusCode: 0,
        elapsedMs: stopwatch.elapsedMilliseconds,
        message: '$error',
      );
    } finally {
      await session?.close();
    }
  }

  List<RemoteEntry> _parseList(String text, String dirPath) {
    final entries = <RemoteEntry>[];
    final seen = <String>{};
    for (final raw in const LineSplitter().convert(text)) {
      final line = raw.trimRight();
      if (line.isEmpty) continue;
      final entry = _parseLine(line, dirPath);
      if (entry == null) continue;
      if (entry.name == '.' || entry.name == '..') continue;
      if (!seen.add(entry.name)) continue;
      entries.add(entry);
    }
    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }

  RemoteEntry? _parseLine(String line, String dirPath) {
    final unix = _unixRe.firstMatch(line);
    if (unix != null) {
      final isDir = unix.group(1) == 'd' || unix.group(1) == 'l';
      final name = (unix.group(4) ?? '').trim();
      if (name.isEmpty) return null;
      return RemoteEntry(
        name: name,
        path: p.posix.join(dirPath, name),
        isDirectory: isDir,
        size: isDir ? null : int.tryParse(unix.group(2) ?? ''),
      );
    }
    final dos = _dosRe.firstMatch(line);
    if (dos != null) {
      final marker = dos.group(1) ?? '';
      final isDir = marker.toUpperCase() == '<DIR>';
      final name = (dos.group(2) ?? '').trim();
      if (name.isEmpty) return null;
      return RemoteEntry(
        name: name,
        path: p.posix.join(dirPath, name),
        isDirectory: isDir,
        size: isDir ? null : int.tryParse(marker),
      );
    }
    final loose = _unixLooseRe.firstMatch(line);
    if (loose != null) {
      final isDir = loose.group(1) == 'd' || loose.group(1) == 'l';
      final tokens = (loose.group(2) ?? '').split(RegExp(r'\s+'));
      var monthIndex = -1;
      for (var i = 0; i < tokens.length; i++) {
        if (RegExp(r'^[A-Za-z]{3}$').hasMatch(tokens[i])) {
          monthIndex = i;
          break;
        }
      }
      String name;
      int? size;
      if (monthIndex >= 0 && tokens.length > monthIndex + 3) {
        name = tokens.sublist(monthIndex + 3).join(' ');
        for (var i = 1; i < monthIndex; i++) {
          final value = int.tryParse(tokens[i]);
          if (value != null) {
            size = value;
            break;
          }
        }
      } else {
        name = tokens.isEmpty ? '' : tokens.last;
      }
      if (name.isEmpty) return null;
      return RemoteEntry(
        name: name,
        path: p.posix.join(dirPath, name),
        isDirectory: isDir,
        size: isDir ? null : size,
      );
    }
    return null;
  }
}

/// 一条 FTP 会话：控制连接 + 可选的数据连接。每次 list/open 都新建会话，
/// 避免 PASV / REST 状态在多个请求之间互相污染。
class _FtpSession {
  _FtpSession(this._controlSocket, this.control);

  final Socket _controlSocket;
  final _FtpControl control;
  Socket? _dataSocket;
  bool _closed = false;

  Future<Socket> openDataConnection() async {
    final reply = await control.send('PASV');
    final match = RegExp(
      r'\((\d{1,3}),(\d{1,3}),(\d{1,3}),(\d{1,3}),(\d{1,3}),(\d{1,3})\)',
    ).firstMatch(reply);
    if (match == null) {
      throw Exception('FTP 服务器不支持 PASV：${reply.split('\n').first}');
    }
    final pasvHost =
        '${match.group(1)}.${match.group(2)}.${match.group(3)}.${match.group(4)}';
    final port = int.parse(match.group(5)!) * 256 + int.parse(match.group(6)!);
    final controlHost = _controlSocket.remoteAddress.address;
    // NAT 后的 NAS 常在 PASV 里返回不可达的内网 / 回环地址。直接改用控制
    // 连接的对端地址（端口仍用 PASV 给出的），比「先连失败再回退」更快、
    // 也不会白等 15 秒超时。
    final host = (pasvHost != controlHost && _isUnroutable(pasvHost))
        ? controlHost
        : pasvHost;
    Socket data;
    try {
      data = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 15),
      );
    } catch (_) {
      // 仍失败时再试控制连接对端，兼容 PASV 返回了另一个同网段地址的情况。
      data = await Socket.connect(
        controlHost,
        port,
        timeout: const Duration(seconds: 15),
      );
    }
    _dataSocket = data;
    return data;
  }

  bool _isUnroutable(String address) {
    if (address == '0.0.0.0' || address == '127.0.0.1' || address == '::1') {
      return true;
    }
    return address.startsWith('10.') ||
        address.startsWith('192.168.') ||
        RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(address) ||
        address.startsWith('169.254.');
  }

  /// 数据传输结束后读取 226 完成响应，避免它留在缓冲区干扰下一次命令。
  Future<void> drainCompletionReply() async {
    try {
      await control.readReply().timeout(const Duration(seconds: 5));
    } catch (_) {
      // 部分服务器不发送 226，忽略即可。
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      _dataSocket?.destroy();
    } catch (_) {}
    try {
      _controlSocket.destroy();
    } catch (_) {}
    control.dispose();
  }
}

/// FTP 控制连接的行读取与多行响应解析。
class _FtpControl {
  _FtpControl(this._socket) {
    _subscription = _socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .listen(_onData, onError: _onError, onDone: _onDone);
  }

  final Socket _socket;
  late final StreamSubscription<String> _subscription;
  final Queue<String> _lines = Queue<String>();
  String _pending = '';
  Completer<String>? _waiter;
  bool _done = false;
  Object? _error;

  void _onData(String chunk) {
    _pending += chunk;
    while (true) {
      final index = _pending.indexOf('\n');
      if (index < 0) break;
      var line = _pending.substring(0, index);
      _pending = _pending.substring(index + 1);
      if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
      _offer(line);
    }
  }

  void _offer(String line) {
    final waiter = _waiter;
    if (waiter != null && !waiter.isCompleted) {
      _waiter = null;
      waiter.complete(line);
    } else {
      _lines.add(line);
    }
  }

  void _onError(Object error, [StackTrace? stack]) {
    _error = error;
    final waiter = _waiter;
    if (waiter != null && !waiter.isCompleted) {
      _waiter = null;
      waiter.completeError(error, stack);
    }
  }

  void _onDone() {
    _done = true;
    _onError(StateError('FTP 控制连接已关闭'));
  }

  Future<String> readLine() {
    if (_error != null) return Future.error(_error!);
    if (_lines.isNotEmpty) return Future.value(_lines.removeFirst());
    if (_done) return Future.error(StateError('FTP 控制连接已关闭'));
    final completer = Completer<String>();
    _waiter = completer;
    return completer.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () {
        if (_waiter == completer) _waiter = null;
        throw TimeoutException('FTP 控制连接响应超时');
      },
    );
  }

  Future<String> readReply() async {
    final buffer = StringBuffer();
    String? code;
    for (var i = 0; i < 40; i++) {
      final line = await readLine();
      if (line.isEmpty) continue;
      buffer.writeln(line);
      final match = RegExp(r'^(\d{3})([ -])(.*)$').firstMatch(line);
      if (match == null) continue;
      if (code == null) {
        code = match.group(1);
        if (match.group(2) == ' ') return buffer.toString().trim();
      } else if (match.group(1) == code && match.group(2) == ' ') {
        return buffer.toString().trim();
      }
    }
    throw Exception('FTP 响应格式异常：${buffer.toString()}');
  }

  Future<String> send(String command) async {
    _socket.write('$command\r\n');
    await _socket.flush();
    final reply = await readReply();
    final code = int.tryParse(reply.substring(0, 3).trim()) ?? 0;
    if (code >= 400) {
      throw Exception('FTP 命令失败：${reply.split('\n').first}');
    }
    return reply;
  }

  Future<int?> size(String remotePath) async {
    try {
      final reply = await send('SIZE $remotePath');
      final match = RegExp(r'^\s*213\s+(\d+)').firstMatch(reply);
      return int.tryParse(match?.group(1) ?? '');
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    _subscription.cancel();
    final waiter = _waiter;
    if (waiter != null && !waiter.isCompleted) {
      _waiter = null;
      waiter.completeError(StateError('FTP 会话已结束'));
    }
  }
}
