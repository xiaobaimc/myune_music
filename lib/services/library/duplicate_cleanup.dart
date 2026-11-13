import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../network/google_drive_client.dart';
import '../network/remote_media_registry.dart';
import '../network/remote_source.dart';

/// 一条待删除曲目。只允许来自去重分组的候选，避免误伤非重复歌曲。
class DuplicateCleanupItem {
  const DuplicateCleanupItem({required this.filePath, required this.title});

  final String filePath;
  final String title;
}

/// 源文件被处理成了什么结果。
enum SourceFileAction {
  /// 用户没打开「同时删除源文件」，只从音乐库移除。
  notRequested,

  /// 已移入某个可恢复的回收站。
  recycled,

  /// 源文件本来就不存在，只从音乐库移除。
  notFound,

  /// 该网络源不支持删除源文件，只从音乐库移除并明确告知用户。
  unsupported,

  /// 删除失败，这首歌保留在音乐库里，不让它「库里没了、文件还在」。
  failed,
}

class DuplicateCleanupDetail {
  const DuplicateCleanupDetail({
    required this.filePath,
    required this.title,
    required this.action,
    required this.message,
  });

  final String filePath;
  final String title;
  final SourceFileAction action;
  final String message;

  bool get canRemoveFromLibrary => action != SourceFileAction.failed;
  bool get recycled => action == SourceFileAction.recycled;
}

class DuplicateCleanupResult {
  const DuplicateCleanupResult(this.details);

  final List<DuplicateCleanupDetail> details;

  /// 允许从音乐库移除的路径。删除失败的不移除，避免源文件还在却从
  /// 软件里消失，之后重新扫描又被加回来。
  Set<String> get pathsToRemove => <String>{
        for (final detail in details)
          if (detail.canRemoveFromLibrary) detail.filePath,
      };

  int get recycledCount =>
      details.where((detail) => detail.recycled).length;

  int get failedCount => details
      .where((detail) => detail.action == SourceFileAction.failed)
      .length;

  int get unsupportedCount => details
      .where((detail) => detail.action == SourceFileAction.unsupported)
      .length;
}

/// 去重「勾选并删除」的源文件处理。
///
/// 三条路径：
/// * 本地文件 → Windows 系统回收站；PowerShell 不可用 / 失败时自动回退到
///   `<Documents>/myune_music/trash/`（附 manifest，可手动恢复）。
/// * Google Drive → `files.delete`，语义是移入 Drive 网页端的回收站。
/// * WebDAV / FTP → 明确标记「不支持删除源文件」，只从音乐库移除。
///
/// 任何一步都**不做永久删除**，且每条路径都会给出可展示的结果说明。
class DuplicateCleanup {
  DuplicateCleanup._();

  static Future<DuplicateCleanupResult> run({
    required List<DuplicateCleanupItem> items,
    required bool deleteSourceFiles,
  }) async {
    if (!deleteSourceFiles) {
      return DuplicateCleanupResult(<DuplicateCleanupDetail>[
        for (final item in items)
          DuplicateCleanupDetail(
            filePath: item.filePath,
            title: item.title,
            action: SourceFileAction.notRequested,
            message: '仅从音乐库移除，源文件保留',
          ),
      ]);
    }

    await RemoteSourceStore.instance.load();

    final local = <DuplicateCleanupItem>[];
    final drive = <DuplicateCleanupItem>[];
    final others = <DuplicateCleanupItem>[];
    for (final item in items) {
      if (!_isNetwork(item.filePath)) {
        local.add(item);
      } else if (_driveInfo(item.filePath) != null) {
        drive.add(item);
      } else {
        others.add(item);
      }
    }

    final details = <DuplicateCleanupDetail>[];
    for (final item in others) {
      details.add(
        DuplicateCleanupDetail(
          filePath: item.filePath,
          title: item.title,
          action: SourceFileAction.unsupported,
          message: 'WebDAV / FTP 暂不支持删除源文件，已仅从音乐库移除',
        ),
      );
    }
    if (local.isNotEmpty) {
      details.addAll(await _recycleLocal(local));
    }
    for (final item in drive) {
      details.add(await _recycleDrive(item));
    }
    return DuplicateCleanupResult(details);
  }

  static bool _isNetwork(String value) =>
      RemoteMediaRegistry.isNetwork(value) || value.contains('://');

  /// 从代理 token 里解出 Google Drive 网络源与远端路径。
  /// `proto` 是唯一可信的类型标记；`s` 是网络源 id，`p` 是 `gd/<fileId>/<名称>`。
  static ({RemoteSource source, String path})? _driveInfo(String filePath) {
    final target = RemoteMediaRegistry.decodeTarget(filePath);
    if (target == null) return null;
    final protocol = (target['proto'] ?? '').toString().toLowerCase();
    if (protocol != 'gdrive' &&
        protocol != 'drive' &&
        protocol != 'googledrive') {
      return null;
    }
    final remotePath = (target['p'] ?? '').toString();
    if (remotePath.isEmpty) return null;
    final source = RemoteSourceStore.instance.byId(
      (target['s'] ?? '').toString(),
    );
    if (source == null || !source.isGoogleDrive) return null;
    return (source: source, path: remotePath);
  }

  static Future<DuplicateCleanupDetail> _recycleDrive(
    DuplicateCleanupItem item,
  ) async {
    final info = _driveInfo(item.filePath);
    if (info == null) {
      return DuplicateCleanupDetail(
        filePath: item.filePath,
        title: item.title,
        action: SourceFileAction.unsupported,
        message: '无法解析网络媒体来源，已仅从音乐库移除',
      );
    }
    try {
      await GoogleDriveClient(info.source).deleteEntry(info.path);
      return DuplicateCleanupDetail(
        filePath: item.filePath,
        title: item.title,
        action: SourceFileAction.recycled,
        message: '已移入 Google Drive 回收站（可在 Drive 网页端恢复）',
      );
    } catch (error) {
      return DuplicateCleanupDetail(
        filePath: item.filePath,
        title: item.title,
        action: SourceFileAction.failed,
        message: '删除云端文件失败：$error',
      );
    }
  }

  static Future<List<DuplicateCleanupDetail>> _recycleLocal(
    List<DuplicateCleanupItem> items,
  ) async {
    final existing = <DuplicateCleanupItem>[];
    final details = <DuplicateCleanupDetail>[];
    for (final item in items) {
      if (await File(item.filePath).exists()) {
        existing.add(item);
      } else {
        details.add(
          DuplicateCleanupDetail(
            filePath: item.filePath,
            title: item.title,
            action: SourceFileAction.notFound,
            message: '源文件已不存在，已仅从音乐库移除',
          ),
        );
      }
    }
    if (existing.isEmpty) return details;

    final systemResult = await _trySystemRecycleBin(
      existing.map((item) => item.filePath).toList(growable: false),
    );
    final fallback = <DuplicateCleanupItem>[];
    if (systemResult == null) {
      // PowerShell 整体不可用（被策略禁用、超时、缺少程序集等）。
      fallback.addAll(existing);
    } else {
      for (final item in existing) {
        final outcome = systemResult[item.filePath];
        if (outcome == 'OK') {
          details.add(
            DuplicateCleanupDetail(
              filePath: item.filePath,
              title: item.title,
              action: SourceFileAction.recycled,
              message: '已移入 Windows 回收站',
            ),
          );
        } else if (outcome == 'MISSING') {
          details.add(
            DuplicateCleanupDetail(
              filePath: item.filePath,
              title: item.title,
              action: SourceFileAction.notFound,
              message: '源文件已不存在，已仅从音乐库移除',
            ),
          );
        } else {
          fallback.add(item);
        }
      }
    }

    for (final item in fallback) {
      try {
        final target = await _moveToAppTrash(item.filePath, item.title);
        details.add(
          DuplicateCleanupDetail(
            filePath: item.filePath,
            title: item.title,
            action: SourceFileAction.recycled,
            message: '系统回收站不可用，已移入应用回收站：$target',
          ),
        );
      } catch (error) {
        details.add(
          DuplicateCleanupDetail(
            filePath: item.filePath,
            title: item.title,
            action: SourceFileAction.failed,
            message: '删除源文件失败：$error（已保留在音乐库中）',
          ),
        );
      }
    }
    return details;
  }

  /// 调 PowerShell 把本地文件送进系统回收站。
  /// 路径走 UTF-8 临时文件、结果也写 UTF-8 文件，避免中文路径与控制台
  /// 编码把结果弄乱。返回 null 表示整批不可用，调用方会走应用回收站。
  static Future<Map<String, String>?> _trySystemRecycleBin(
    List<String> paths,
  ) async {
    if (!Platform.isWindows) return null;
    File? listFile;
    File? resultFile;
    try {
      final temp = await getTemporaryDirectory();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      listFile = File(p.join(temp.path, 'myune_recycle_$stamp.txt'));
      resultFile = File(p.join(temp.path, 'myune_recycle_${stamp}_out.txt'));
      await listFile.writeAsString(paths.join('\n'), encoding: utf8, flush: true);

      final listLiteral = _psQuote(listFile.path);
      final resultLiteral = _psQuote(resultFile.path);
      final script = '''
\$ErrorActionPreference = 'Stop'
try { Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction Stop } catch { }
\$lines = [System.IO.File]::ReadAllLines('$listLiteral', [System.Text.Encoding]::UTF8)
\$res = New-Object 'System.Collections.Generic.List[string]'
foreach (\$line in \$lines) {
  if ([string]::IsNullOrWhiteSpace(\$line)) { continue }
  try {
    if (-not (Test-Path -LiteralPath \$line -PathType Leaf)) {
      \$res.Add('MISSING|' + \$line)
      continue
    }
    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
      \$line,
      [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
      [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin,
      [Microsoft.VisualBasic.FileIO.UICancelOption]::DoNothing)
    \$res.Add('OK|' + \$line)
  } catch {
    \$msg = \$_.Exception.Message -replace '[\\r\\n|]', ' '
    \$res.Add('FAIL|' + \$line + '|' + \$msg)
  }
}
[System.IO.File]::WriteAllLines('$resultLiteral', \$res, (New-Object System.Text.UTF8Encoding(\$false)))
''';

      await Process.run(
        'powershell',
        <String>[
          '-NoProfile',
          '-NonInteractive',
          '-WindowStyle',
          'Hidden',
          '-Command',
          script,
        ],
      ).timeout(const Duration(seconds: 45));
      if (!await resultFile.exists()) return null;

      final lines = await resultFile.readAsLines(encoding: utf8);
      final outcomes = <String, String>{};
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        final parts = line.split('|');
        if (parts.length < 2) continue;
        final status = parts[0];
        final path = parts[1];
        outcomes[path] = (status == 'OK' || status == 'MISSING')
            ? status
            : 'FAIL:${parts.length > 2 ? parts.sublist(2).join('|') : status}';
      }
      return outcomes.isEmpty ? null : outcomes;
    } catch (_) {
      return null;
    } finally {
      // 失败也要清掉临时文件；这里不做任何删除用户文件的动作。
      try {
        if (listFile != null && await listFile.exists()) {
          await listFile.delete();
        }
      } catch (_) {}
      try {
        if (resultFile != null && await resultFile.exists()) {
          await resultFile.delete();
        }
      } catch (_) {}
    }
  }

  /// PowerShell 不可用时的兜底：把文件移到应用自己的回收站目录，
  /// 并写 manifest 记录原路径，用户可以手动恢复。
  static Future<String> _moveToAppTrash(String path, String title) async {
    final docs = await getApplicationDocumentsDirectory();
    final trash = Directory(p.join(docs.path, 'myune_music', 'trash'));
    if (!await trash.exists()) await trash.create(recursive: true);

    final file = File(path);
    if (!await file.exists()) throw StateError('源文件已不存在');
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final safeName = p.basename(path).replaceAll(
          RegExp(r'[<>:"/\\|?*]'),
          '_',
        );
    final target = p.join(trash.path, '${stamp}_$safeName');
    await file.rename(target);

    try {
      final manifest = File(p.join(trash.path, 'manifest.jsonl'));
      await manifest.writeAsString(
        '${jsonEncode(<String, dynamic>{
          'original': path,
          'moved': target,
          'title': title,
          'time': DateTime.now().toIso8601String(),
        })}\n',
        mode: FileMode.append,
        encoding: utf8,
      );
    } catch (_) {
      // manifest 写失败不影响文件已经安全移走这一事实。
    }
    return target;
  }

  /// PowerShell 单引号字符串里，单引号要写成两个。
  static String _psQuote(String value) => value.replaceAll("'", "''");
}
