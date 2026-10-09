import 'package:flutter/foundation.dart';

import '../page/setting/update_checker.dart';
import 'notification_service.dart';

class UpdateCheckService {
  // 启动后延迟一段时间再检查，避免与启动阶段的初始化争抢资源
  static const Duration startupDelay = Duration(seconds: 3);

  static Future<UpdateInfo?> runSilentCheck({
    required String currentVersion,
    required NotificationService notificationService,
    Duration delay = startupDelay,
    Future<UpdateCheckResult> Function(String currentVersion)? check,
  }) async {
    if (delay > Duration.zero) {
      await Future.delayed(delay);
    }

    final UpdateCheckResult result;
    try {
      final Future<UpdateCheckResult> Function(String) checkFn =
          check ?? UpdateChecker.checkForUpdates;
      result = await checkFn(currentVersion);
    } catch (e) {
      // 自动检查失败保持静默
      return null;
    }

    switch (result.type) {
      case UpdateCheckResultType.successUpdateAvailable:
        final updateInfo = result.updateInfo;
        if (updateInfo == null) return null;

        notificationService.info(
          '发现新版本 ${_displayVersion(updateInfo.latestVersion)}',
        );
        return updateInfo;
      case UpdateCheckResultType.successNoUpdate:
        // notificationService.info('今日无事可做');
        return null;
      case UpdateCheckResultType.error:
        // 自动检查失败保持静默，只写调试日志
        debugPrint('[UpdateCheck] 自动检查更新失败: ${result.errorMessage}');
        return null;
    }
  }

  static String _displayVersion(String version) {
    final trimmed = version.trim();
    if (trimmed.isEmpty) return trimmed;
    return trimmed.startsWith('v') ? trimmed : 'v$trimmed';
  }
}
