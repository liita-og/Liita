import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:liita/core/theme/app_theme.dart';
import 'package:liita/core/models/user_profile.dart';
import 'package:liita/core/providers/providers.dart';
import 'package:liita/core/widgets/avatar_widget.dart';

/// Passenger discovery — stacked card deck (Figma design).
class RadarScreen extends ConsumerStatefulWidget {
  const RadarScreen({super.key});

  @override
  ConsumerState<RadarScreen> createState() => _RadarScreenState();
}

class _RadarScreenState extends ConsumerState<RadarScreen> {
  int _frontIndex = 0;

  void _nextCard(int total) {
    if (total == 0) return;
    setState(() => _frontIndex = (_frontIndex + 1) % total);
  }

  @override
  Widget build(BuildContext context) {
    final peersAsync = ref.watch(peersProvider);
    final localProfile = ref.watch(localProfileProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: peersAsync.when(
          data: (peers) => _buildContent(peers, localProfile),
          loading: () => _buildContent([], localProfile),
          error: (_, __) => _buildContent([], localProfile),
        ),
      ),
    );
  }

  Widget _buildContent(List<UserProfile> peers, UserProfile? localProfile) {
    return Column(
      children: [
        // ── Header ──────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              const Text(
                'Radar',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                peers.isEmpty ? 'no one nearby' : '${peers.length} nearby',
                style: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),

        // ── Card Stack ───────────────────────────────────────────────────────
        Expanded(
          child: peers.isEmpty
              ? const _EmptyState()
              : _CardStack(
                  peers: peers,
                  frontIndex: _frontIndex,
                  localProfile: localProfile,
                  onWave: (peer) => _sendWave(peer, localProfile),
                  onNext: () => _nextCard(peers.length),
                ),
        ),

        // ── Pagination dots ──────────────────────────────────────────────────
        if (peers.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                peers.length.clamp(0, 6),
                (i) {
                  final isActive =
                      i == _frontIndex % peers.length.clamp(1, 6);
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: isActive ? 16 : 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isActive
                          ? AppColors.textPrimary
                          : AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  );
                },
              ),
            ),
          ),

        // Space for floating tab bar
        const SizedBox(height: 84),
      ],
    );
  }

  Future<void> _sendWave(UserProfile peer, UserProfile? local) async {
    if (local == null) return;
    await ref.read(appControllerProvider).sendWave(peer.deviceId);
    ref.read(wavedAtProvider.notifier)
        .update((state) => {...state, peer.deviceId});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Wave sent to ${peer.name}'),
          backgroundColor: AppColors.surfaceLight,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
        ),
      );
    }
  }
}

// ── Card Stack ───────────────────────────────────────────────────────────────

class _CardStack extends StatelessWidget {
  final List<UserProfile> peers;
  final int frontIndex;
  final UserProfile? localProfile;
  final void Function(UserProfile) onWave;
  final VoidCallback onNext;

  const _CardStack({
    required this.peers,
    required this.frontIndex,
    required this.localProfile,
    required this.onWave,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final count = peers.length.clamp(0, 4);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          // Draw from back (highest stackPos) to front (stackPos == 0)
          for (int stackPos = count - 1; stackPos >= 0; stackPos--)
            _StackCard(
              peer: peers[(frontIndex + stackPos) % peers.length],
              isFront: stackPos == 0,
              scale: 1.0 - (stackPos * 0.04),
              translateY: stackPos * 28.0,
              opacity: 1.0 - (stackPos * 0.15),
              onWave: () => onWave(peers[frontIndex % peers.length]),
              onNext: onNext,
              stackDepth: stackPos,
            ),
        ],
      ),
    );
  }
}

class _StackCard extends StatelessWidget {
  final UserProfile peer;
  final bool isFront;
  final double scale;
  final double translateY;
  final double opacity;
  final VoidCallback onWave;
  final VoidCallback onNext;
  final int stackDepth;

  const _StackCard({
    required this.peer,
    required this.isFront,
    required this.scale,
    required this.translateY,
    required this.opacity,
    required this.onWave,
    required this.onNext,
    required this.stackDepth,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      transform: Matrix4.translationValues(0.0, translateY, 0.0)
        ..multiply(Matrix4.diagonal3Values(scale, scale, 1.0)),
      transformAlignment: Alignment.topCenter,
      child: Opacity(
        opacity: opacity,
        child: Container(
          width: double.infinity,
          height: 440,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.glassBorder, width: 1),
            boxShadow: isFront ? AppShadows.elevated : [],
          ),
          child: isFront
              ? _FrontCardContent(
                  peer: peer, onWave: onWave, onNext: onNext)
              : _BackCardContent(stackDepth: stackDepth),
        ),
      ),
    );
  }
}

class _FrontCardContent extends ConsumerWidget {
  final UserProfile peer;
  final VoidCallback onWave;
  final VoidCallback onNext;

  const _FrontCardContent({
    required this.peer,
    required this.onWave,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wavedPeers = ref.watch(wavedAtProvider);
    final hasWaved = wavedPeers.contains(peer.deviceId);
    
    final wavedByPeers = ref.watch(wavedByProvider);
    final isWavedBy = wavedByPeers.contains(peer.deviceId);
    
    // Check if this peer is already a connection.
    final matchesAsync = ref.watch(matchesProvider);
    final isMatched = matchesAsync.whenOrNull(data: (ids) => ids.contains(peer.deviceId)) ?? false;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Avatar + info ──
          Center(
            child: Column(
              children: [
                AvatarWidget(profile: peer, size: 80, showWaveBadge: isWavedBy),
                const SizedBox(height: 16),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        peer.name,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.3,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('·',
                          style: TextStyle(
                              color: AppColors.textTertiary,
                              fontSize: 16)),
                    ),
                    Text(
                      peer.seatNumber,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  peer.occupation,
                  style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),

          const Spacer(),

          // ── Icebreaker ──
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                peer.icebreakerPrompt,
                style: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '"${peer.icebreakerAnswer}"',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w300,
                  height: 1.5,
                ),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),

          const Spacer(),

          // ── Buttons ──
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: onNext,
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: AppColors.glassBorder, width: 1),
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      'Next',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              if (isMatched)
                Expanded(
                  flex: 2,
                  child: GestureDetector(
                    onTap: () => context.go('/matches'),
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        'Message',
                        style: TextStyle(
                          color: AppColors.textOnPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                )
              else
                Expanded(
                  flex: 2,
                  child: GestureDetector(
                    onTap: hasWaved ? null : onWave,
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: hasWaved ? AppColors.surface : AppColors.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        hasWaved ? 'Wave Sent' : 'Wave',
                        style: TextStyle(
                          color: hasWaved ? AppColors.textTertiary : AppColors.textOnPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BackCardContent extends StatelessWidget {
  final int stackDepth;

  const _BackCardContent({required this.stackDepth});

  @override
  Widget build(BuildContext context) {
    if (stackDepth == 1) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Opacity(
          opacity: 0.4,
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 100,
                    height: 14,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 70,
                    height: 11,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.glassBorder, width: 1),
            ),
            child: const Icon(
              Icons.wifi_tethering_rounded,
              color: AppColors.textTertiary,
              size: 28,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Scanning for passengers',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Keep the app open while we search',
            style: TextStyle(color: AppColors.textTertiary, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
