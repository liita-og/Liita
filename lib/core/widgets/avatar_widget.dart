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
    final safeName = displayName.trim().isEmpty ? '?' : displayName;
    final initials = _initials(safeName);
    final colorIndex = safeName.codeUnitAt(0) % AppColors.avatarColors.length;
    final bgColor = AppColors.avatarColors[colorIndex];

    final resolvedPhotoPath = photoPath ?? profile?.photoHash;

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
            child: resolvedPhotoPath != null && resolvedPhotoPath.isNotEmpty
                ? ClipOval(
                    child: Image.file(
                      File(resolvedPhotoPath),
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
          if (showWaveBadge)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.background, width: 2),
                ),
                child: Icon(
                  Icons.waving_hand_rounded,
                  color: AppColors.textOnPrimary,
                  size: size * 0.25,
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
