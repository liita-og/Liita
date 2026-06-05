import 'dart:io';
import 'package:flutter/material.dart';
import 'package:liita/core/theme/app_theme.dart';
import 'package:liita/core/models/user_profile.dart';

/// Reusable avatar widget — monochrome initials-based, matching Figma design.
class AvatarWidget extends StatelessWidget {
  final UserProfile? profile;
  final String? name;
  final double size;
  final String? photoPath;
  final bool showOnlineDot;
  final bool showWaveBadge;
  final VoidCallback? onTap;

  const AvatarWidget({
    super.key,
    this.profile,
    this.name,
    this.size = 56,
    this.photoPath,
    this.showOnlineDot = false,
    this.showWaveBadge = false,
    this.onTap,
  }) : assert(profile != null || name != null, 'Either profile or name must be provided');

  @override
  Widget build(BuildContext context) {
    final displayName = profile?.name ?? name ?? '?';
    final initials = _initials(displayName);
    final colorIndex = displayName.codeUnitAt(0) % AppColors.avatarColors.length;
    final bgColor = AppColors.avatarColors[colorIndex];

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
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.04),
                width: 1,
              ),
            ),
            child: (photoPath ?? profile?.photoHash) != null
                ? ClipOval(
                    child: Image.file(
                      File((photoPath ?? profile?.photoHash)!),
                      width: size,
                      height: size,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _InitialText(initials: initials, size: size),
                    ),
                  )
                : _InitialText(initials: initials, size: size),
          ),
          if (showOnlineDot)
            Positioned(
              right: 1,
              bottom: 1,
              child: Container(
                width: size * 0.2,
                height: size * 0.2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.textSecondary,
                  border: Border.all(color: AppColors.background, width: 1.5),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }
}

class _InitialText extends StatelessWidget {
  final String initials;
  final double size;

  const _InitialText({required this.initials, required this.size});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        initials,
        style: TextStyle(
          color: const Color(0xFFFAFAFA),
          fontSize: size * 0.35,
          fontWeight: FontWeight.w500,
          letterSpacing: 0,
        ),
      ),
    );
  }
}
