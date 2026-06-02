import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liita/core/theme/app_theme.dart';

/// Games screen — placeholder for Phase 2 multiplayer games.
class GamesScreen extends ConsumerWidget {
  const GamesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Games')),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            children: [
              const SizedBox(height: AppSpacing.lg),
            // Coming soon header
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.surfaceLight,
                boxShadow: AppShadows.glow,
              ),
              child: const Icon(
                Icons.sports_esports_rounded,
                size: 48,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              'Games Coming Soon',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Play with fellow travelers\nwhile you fly together',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            // Game cards preview
            _GamePreviewCard(
              icon: Icons.grid_3x3_rounded,
              title: 'Tic-Tac-Toe',
              description: 'Classic game, now at 30,000 feet',
              color: AppColors.primary,
            ),
            const SizedBox(height: AppSpacing.md),
            _GamePreviewCard(
              icon: Icons.quiz_rounded,
              title: 'Trivia',
              description: 'Test your knowledge against the cabin',
              color: AppColors.wave,
            ),
            const SizedBox(height: AppSpacing.md),
            _GamePreviewCard(
              icon: Icons.emoji_events_rounded,
              title: 'Word Chain',
              description: 'Keep the chain going or lose!',
              color: AppColors.success,
            ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GamePreviewCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Color color;

  const _GamePreviewCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.lgAll,
        border: Border.all(
          color: AppColors.glassBorder,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.15),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                Text(
                  description,
                  style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: AppRadius.pillAll,
            ),
            child: const Text(
              'Soon',
              style: TextStyle(
                color: AppColors.textTertiary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
