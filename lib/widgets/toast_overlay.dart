import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import '../services/notification_service.dart';
import 'toast_notification_widget.dart';

class _ToastEntry {
  final AppNotification notification;
  final AnimationController controller;
  bool isExiting = false;

  _ToastEntry({required this.notification, required this.controller});
}

class ToastOverlay extends StatefulWidget {
  const ToastOverlay({super.key});

  @override
  State<ToastOverlay> createState() => _ToastOverlayState();
}

class _ToastOverlayState extends State<ToastOverlay>
    with TickerProviderStateMixin {
  static const Duration _animationDuration = Duration(milliseconds: 300);

  final Map<String, _ToastEntry> _entries = {};
  NotificationService? _service;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newService = context.read<NotificationService>();
    if (_service != newService) {
      _service?.removeListener(_onServiceChanged);
      _service = newService;
      _service!.addListener(_onServiceChanged);
      // 初始同步
      _onServiceChanged();
    }
  }

  @override
  void dispose() {
    _service?.removeListener(_onServiceChanged);
    for (final entry in _entries.values) {
      entry.controller.dispose();
    }
    _entries.clear();
    super.dispose();
  }

  void _onServiceChanged() {
    if (!mounted) return;

    final service = _service!;
    final currentIds = service.notifications.map((n) => n.id).toSet();

    // 创建动画控制器并播放进场动画
    for (final notification in service.notifications) {
      if (_entries.containsKey(notification.id)) {
        _entries[notification.id]!.notification.count = notification.count;
      } else {
        final controller = AnimationController(
          vsync: this,
          duration: _animationDuration,
        );
        _entries[notification.id] = _ToastEntry(
          notification: notification,
          controller: controller,
        );
        controller.forward();
      }
    }

    // 播放退场动画后再从 entries 中移除
    for (final id in _entries.keys.toList()) {
      if (!currentIds.contains(id) && !_entries[id]!.isExiting) {
        final entry = _entries[id]!;
        entry.isExiting = true;
        entry.controller.reverse().then((_) {
          if (mounted) {
            setState(() {
              _entries.remove(id);
              entry.controller.dispose();
            });
          }
        });
      }
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_entries.isEmpty) return const SizedBox.shrink();

    // 按照添加顺序排列，新的在下面
    final sortedEntries = _entries.values.toList();

    return Positioned(
      right: 12,
      bottom: 80,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: sortedEntries.map((entry) {
          return ToastNotificationWidget(
            key: ValueKey(entry.notification.id),
            notification: entry.notification,
            animation: entry.controller,
            onDismiss: () => _service?.dismiss(entry.notification.id),
            onHoverStart: () => _service?.pauseTimer(entry.notification.id),
            onHoverEnd: () => _service?.resumeTimer(entry.notification.id),
          );
        }).toList(),
      ),
    );
  }
}
