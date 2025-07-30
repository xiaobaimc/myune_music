import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class HoverOverlayControl extends StatefulWidget {
  final IconData icon;
  final Color iconColor;
  final WidgetBuilder overlayContentBuilder;
  final VoidCallback? onIconPressed;
  final void Function(PointerSignalEvent)? onPointerSignal;
  final BoxConstraints overlayConstraints;
  final Offset overlayOffset;

  const HoverOverlayControl({
    required this.icon,
    required this.iconColor,
    required this.overlayContentBuilder,
    required this.overlayOffset,
    this.onIconPressed,
    this.onPointerSignal,
    this.overlayConstraints = const BoxConstraints(maxWidth: 240),
    super.key,
  });

  @override
  HoverOverlayControlState createState() => HoverOverlayControlState();
}

class HoverOverlayControlState extends State<HoverOverlayControl> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _isHovering = false;

  void _showOverlay() {
    if (_overlayEntry != null) return;
    _overlayEntry = OverlayEntry(
      builder: (context) {
        // 浮层上的MouseRegion，用于当鼠标移入浮层时保持其可见
        return CompositedTransformFollower(
          link: _layerLink,
          offset: widget.overlayOffset,
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: widget.overlayConstraints,
              child: MouseRegion(
                onEnter: (_) => _setHovering(true),
                onExit: (_) => _setHovering(false),
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(6),
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  child: widget.overlayContentBuilder(context),
                ),
              ),
            ),
          ),
        );
      },
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _setHovering(bool hovering) {
    if (!mounted) return;
    _isHovering = hovering;
    if (!hovering) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (!_isHovering) _removeOverlay();
      });
    }
  }

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      // 监听悬浮在图标上的滚轮事件
      child: Listener(
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) {
            widget.onPointerSignal?.call(event);
            // 主动通知浮层UI进行重绘，以反映最新状态
            _overlayEntry?.markNeedsBuild();
          }
        },
        child: MouseRegion(
          onEnter: (_) {
            _setHovering(true);
            _showOverlay();
          },
          onExit: (_) => _setHovering(false),
          child: IconButton(
            icon: Icon(
              widget.icon,
              color: widget.iconColor.withAlpha(179),
              size: 24,
            ),
            onPressed: () {
              // 如果外部传入了点击事件的处理函数
              if (widget.onIconPressed != null) {
                // 先执行外部的函数
                widget.onIconPressed!();
                // 再主动刷新浮层，以确保UI同步
                _overlayEntry?.markNeedsBuild();
              } else {
                // 如果外部没有传入处理函数，就执行默认逻辑
                if (_overlayEntry == null) {
                  _showOverlay();
                } else {
                  _removeOverlay();
                }
              }
            },
          ),
        ),
      ),
    );
  }
}
