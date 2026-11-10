import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 网络媒体 / 本机流代理的诊断日志。
///
/// 网络播放失败时 mpv 只会给一句 `loading failed` 或
/// `http: Error reading HTTP response: Immediate exit requested`，
/// 无法区分是「上游太慢」「鉴权失败」还是「长度撒谎」。这里把每一次代理
/// 请求的上游状态码、长度、Range 区间与耗时都落盘，便于定位到具体环节。
///
/// 写盘是异步且非阻塞的：日志失败绝不影响播放。
class NetworkProxyLog {
  NetworkProxyLog._();

  static final NetworkProxyLog instance = NetworkProxyLog._();

  /// 单文件上限，超过后从头重写，避免无限增长。
  static const int _maxBytes = 512 * 1024;

  File? _file;
  Future<File?>? _initializing;
  final List<String> _pending = <String>[];
  bool _flushing = false;

  /// 日志文件的绝对路径（未初始化完成时为 null）。
  String? get path => _file?.path;

  /// 日志目录，UI 可直接用它打开所在文件夹。
  String? get directory => _file == null ? null : p.dirname(_file!.path);

  Future<File?> _ensureFile() {
    final ready = _file;
    if (ready != null) return Future<File?>.value(ready);
    final running = _initializing;
    if (running != null) return running;
    final future = _openFile();
    _initializing = future;
    return future;
  }

  Future<File?> _openFile() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, 'myune_music', 'logs'));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final file = File(p.join(dir.path, 'network.log'));
      if (await file.exists() && await file.length() > _maxBytes) {
        await file.writeAsString(
          '==== 日志超过上限，已重写于 ${DateTime.now().toIso8601String()} ====\n',
          mode: FileMode.write,
        );
      }
      _file = file;
      return file;
    } catch (_) {
      return null;
    }
  }

  /// 追加一行日志。任意线程 / 任意时机调用都安全。
  void write(String message) {
    _pending.add('${DateTime.now().toIso8601String()} $message');
    unawaited(_flush());
  }

  Future<void> _flush() async {
    if (_flushing) return;
    _flushing = true;
    try {
      final file = await _ensureFile();
      if (file == null) {
        _pending.clear();
        return;
      }
      while (_pending.isNotEmpty) {
        final batch = _pending.take(50).join('\n');
        _pending.removeRange(0, _pending.length < 50 ? _pending.length : 50);
        try {
          await file.writeAsString('$batch\n', mode: FileMode.writeOnlyAppend);
        } catch (_) {
          _pending.clear();
          return;
        }
      }
    } finally {
      _flushing = false;
    }
  }
}
