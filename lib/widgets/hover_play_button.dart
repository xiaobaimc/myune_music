import 'package:flutter/material.dart';

class HoverPlayButton extends StatelessWidget {
  final bool visible;
  final VoidCallback onPressed;
  final String tooltip;
  final double size;

  const HoverPlayButton({
    super.key,
    required this.visible,
    required this.onPressed,
    this.tooltip = '播放',
    this.size = 36,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ExcludeSemantics(
      excluding: !visible,
      child: IgnorePointer(
        ignoring: !visible,
        child: Focus(
          canRequestFocus: visible,
          descendantsAreFocusable: visible,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            child: Tooltip(
              message: tooltip,
              child: Material(
                color: colorScheme.primary,
                elevation: 3,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  mouseCursor: SystemMouseCursors.click,
                  onTap: onPressed,
                  child: SizedBox(
                    width: size,
                    height: size,
                    child: Icon(
                      Icons.play_arrow_rounded,
                      size: size * 0.62,
                      color: colorScheme.onPrimary,
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

class HoverPlayRegion extends StatefulWidget {
  final Widget Function(BuildContext context, bool hovered) builder;
  final MouseCursor cursor;

  const HoverPlayRegion({
    super.key,
    required this.builder,
    this.cursor = SystemMouseCursors.click,
  });

  @override
  State<HoverPlayRegion> createState() => _HoverPlayRegionState();
}

class _HoverPlayRegionState extends State<HoverPlayRegion> {
  bool _hovered = false;

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.cursor,
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: widget.builder(context, _hovered),
    );
  }
}
