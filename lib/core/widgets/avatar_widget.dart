import 'package:flutter/material.dart';
import 'package:liita/core/theme/app_theme.dart';

/// Reusable avatar widget — shows colored initials or a profile photo
class AvatarWidget extends StatelessWidget {
  final String name;
  final double size;
  final String? photoPath;
  final bool showOnlineDot;
  final bool showWaveBadge;
  final VoidCallback? onTap;

  const AvatarWidget({
    super.key,
    required this.name,
    this.size = 56,
    this.photoPath,
    this.showOnlineDot = false,
    this.showWaveBadge = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final colorIndex = name.hashCode.abs() % _avatarColors.length;
    final bgColor = _avatarColors[colorIndex];

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: bgColor,
              boxShadow: [
                BoxShadow(
                  color: bgColor.withValues(alpha: 0.4),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: photoPath != null
                ? ClipOval(
                    child: Image.asset(
                      photoPath!,
                      width: size,
                      height: size,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _InitialText(
                        initial: initial,
                        size: size,
                      ),
                    ),
                  )
                : _InitialText(initial: initial, size: size),
          ),
          // Online dot
          if (showOnlineDot)
            Positioned(
              right: 2,
              bottom: 2,
              child: Container(
                width: size * 0.22,
                height: size * 0.22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.success,
                  border: Border.all(
                    color: AppColors.background,
                    width: 2,
                  ),
                ),
              ),
            ),
          // Wave badge
          if (showWaveBadge)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.wave,
                ),
                child: Icon(
                  Icons.waving_hand_rounded,
                  size: size * 0.22,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }

  static const List<Color> _avatarColors = [
    Color(0xFF6366F1), // Indigo
    Color(0xFF06B6D4), // Cyan
    Color(0xFFF472B6), // Pink
    Color(0xFF10B981), // Emerald
    Color(0xFFF59E0B), // Amber
    Color(0xFFA855F7), // Purple
    Color(0xFF14B8A6), // Teal
    Color(0xFFEF4444), // Red
    Color(0xFF8B5CF6), // Violet
    Color(0xFF0EA5E9), // Sky
    Color(0xFFFBBF24), // Gold
    Color(0xFF34D399), // Mint
  ];
}

class _InitialText extends StatelessWidget {
  final String initial;
  final double size;

  const _InitialText({required this.initial, required this.size});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.4,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      ),
    );
  }
}
