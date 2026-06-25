import 'package:flutter/material.dart';

class InfoIcon extends StatelessWidget {
  const InfoIcon(
    this.message, {
    super.key,
    this.size = 20,
    this.icon = Icons.info_outline,
  });

  final String message;
  final double size;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final disabledColor = Theme.of(context).disabledColor;
    return Tooltip(
      message: message,
      child: Icon(icon, size: size, color: disabledColor),
    );
  }
}
