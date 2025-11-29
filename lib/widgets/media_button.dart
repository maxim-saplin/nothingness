import 'package:flutter/material.dart';

class MediaButton extends StatelessWidget {
  final IconData icon;
  final double size;
  final bool isPrimary;
  final VoidCallback onTap;
  final Color? accentColor;
  final Color? inactiveBackgroundColor;
  final Color? inactiveIconColor;

  const MediaButton({
    super.key,
    required this.icon,
    required this.size,
    this.isPrimary = false,
    required this.onTap,
    this.accentColor,
    this.inactiveBackgroundColor,
    this.inactiveIconColor,
  });

  @override
  Widget build(BuildContext context) {
    final primaryColor = accentColor ?? const Color(0xFF00FF88);
    final secondaryBg =
        inactiveBackgroundColor ?? Colors.white.withAlpha(13);
    final secondaryIcon =
        inactiveIconColor ?? Colors.white70;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isPrimary
              ? primaryColor
              : secondaryBg,
          boxShadow: isPrimary
              ? [
                  BoxShadow(
                    color: primaryColor.withAlpha(77),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: Icon(
          icon,
          size: size * 0.5,
          color: isPrimary ? const Color(0xFF0A0A0F) : secondaryIcon,
        ),
      ),
    );
  }
}

