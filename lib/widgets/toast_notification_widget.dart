import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import '../services/notification_service.dart';

class ToastNotificationWidget extends StatelessWidget {
  final AppNotification notification;
  final Animation<double> animation;
  final VoidCallback onDismiss;
  final VoidCallback onHoverStart;
  final VoidCallback onHoverEnd;

  const ToastNotificationWidget({
    super.key,
    required this.notification,
    required this.animation,
    required this.onDismiss,
    required this.onHoverStart,
    required this.onHoverEnd,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isError = notification.type == NotificationType.error;

    final backgroundColor = isError
        ? theme.colorScheme.error
        : theme.colorScheme.primary;
    final foregroundColor = isError
        ? theme.colorScheme.onError
        : theme.colorScheme.onPrimary;
    final icon = isError ? Icons.error_rounded : Icons.info_rounded;

    // 从右侧滑入 + 淡入
    final slideAnimation =
        Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero).animate(
          CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          ),
        );

    final fadeAnimation = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );

    return SlideTransition(
      position: slideAnimation,
      child: FadeTransition(
        opacity: fadeAnimation,
        child: MouseRegion(
          onEnter: (_) => onHoverStart(),
          onExit: (_) => onHoverEnd(),
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: IntrinsicWidth(
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    decoration: BoxDecoration(
                      color: backgroundColor,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, color: foregroundColor, size: 20),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            notification.count > 1
                                ? '${notification.message} (×${notification.count})'
                                : notification.message,
                            style: TextStyle(
                              color: foregroundColor,
                              fontSize: 13,
                            ),
                          ),
                        ),

                        if (isError) ...[
                          const SizedBox(width: 4),
                          _ActionButton(
                            label: '复制',
                            color: foregroundColor,
                            onPressed: () => Clipboard.setData(
                              ClipboardData(text: notification.message),
                            ),
                          ),
                        ],

                        const SizedBox(width: 4),

                        _ActionButton(
                          label: '关闭',
                          color: foregroundColor,
                          onPressed: onDismiss,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,

        mouseCursor: SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(4),
        splashColor: color.withValues(alpha: 0.2),
        highlightColor: color.withValues(alpha: 0.1),

        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: color.withValues(alpha: 0.25),
              width: 0.5,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
