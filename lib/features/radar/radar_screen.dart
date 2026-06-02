import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:liita/core/theme/app_theme.dart';
import 'package:liita/core/models/mesh_packet.dart';
import 'package:liita/core/models/user_profile.dart';
import 'package:liita/core/providers/providers.dart';
import 'package:liita/core/widgets/avatar_widget.dart';

/// Passenger discovery screen — scrollable 2-column grid of nearby travelers.
///
/// Each card shows the peer's avatar, name, seat badge, occupation, and a
/// preview of their icebreaker answer. Tapping a card opens a detail overlay
/// with a Wave button. The overlay can be dismissed via the X button in the
/// top-right corner or by tapping the scrim behind it.
class RadarScreen extends ConsumerStatefulWidget {
  const RadarScreen({super.key});

  @override
  ConsumerState<RadarScreen> createState() => _RadarScreenState();
}

class _RadarScreenState extends ConsumerState<RadarScreen>
    with SingleTickerProviderStateMixin {
  UserProfile? _selectedPeer;

  // Subtle entrance animation for the overlay card
  late AnimationController _overlayAnim;
  late Animation<double> _overlayScale;
  late Animation<double> _overlayOpacity;

  @override
  void initState() {
    super.initState();
    _overlayAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _overlayScale = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: _overlayAnim, curve: Curves.easeOutCubic),
    );
    _overlayOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _overlayAnim, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _overlayAnim.dispose();
    super.dispose();
  }

  void _openPeer(UserProfile peer) {
    setState(() => _selectedPeer = peer);
    _overlayAnim.forward(from: 0);
  }

  Future<void> _closePeer() async {
    await _overlayAnim.reverse();
    if (mounted) setState(() => _selectedPeer = null);
  }

  void _onWave(UserProfile peer) {
    final localProfile = ref.read(localProfileProvider);
    if (localProfile == null) return;

    ref.read(wavedAtProvider.notifier).update((s) => {...s, peer.deviceId});

    ref.read(meshServiceProvider).sendPacket(
      MeshPacket(
        packetId: const Uuid().v4(),
        originId: localProfile.deviceId,
        destinationId: peer.deviceId,
        payloadType: PayloadType.wave,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ),
    );

    _closePeer();
  }

  @override
  Widget build(BuildContext context) {
    final peersAsync = ref.watch(peersProvider);
    final peerCount = ref.watch(activePeerCountProvider);
    final wavedAt = ref.watch(wavedAtProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby Passengers'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: _ScanStatusChip(peerCount: peerCount),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Main content
          peersAsync.when(
            loading: () => const _ShimmerGrid(),
            error: (_, __) => const _EmptyState(
              icon: Icons.wifi_off_rounded,
              message: 'Could not connect to mesh',
            ),
            data: (peers) {
              if (peers.isEmpty) {
                return const _EmptyState(
                  icon: Icons.people_outline_rounded,
                  message: 'Scanning for nearby travelers...',
                  showSpinner: true,
                );
              }
              return _PassengerGrid(
                peers: peers,
                wavedAt: wavedAt,
                onTap: _openPeer,
              );
            },
          ),

          // Peer detail overlay
          if (_selectedPeer != null)
            _PeerDetailOverlay(
              peer: _selectedPeer!,
              hasWaved: wavedAt.contains(_selectedPeer!.deviceId),
              scaleAnim: _overlayScale,
              opacityAnim: _overlayOpacity,
              onWave: () => _onWave(_selectedPeer!),
              onClose: _closePeer,
            ),
        ],
      ),
    );
  }
}

// =============================================================================
// Scan status chip
// =============================================================================

class _ScanStatusChip extends StatelessWidget {
  final AsyncValue<int> peerCount;

  const _ScanStatusChip({required this.peerCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.10),
        borderRadius: AppRadius.pillAll,
        border: Border.all(
          color: AppColors.success.withValues(alpha: 0.20),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.success,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            peerCount.when(
              data: (c) => '$c nearby',
              loading: () => 'Scanning...',
              error: (_, __) => 'Offline',
            ),
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.success,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Passenger grid
// =============================================================================

class _PassengerGrid extends StatelessWidget {
  final List<UserProfile> peers;
  final Set<String> wavedAt;
  final ValueChanged<UserProfile> onTap;

  const _PassengerGrid({
    required this.peers,
    required this.wavedAt,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(AppSpacing.md),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: AppSpacing.sm,
        mainAxisSpacing: AppSpacing.sm,
        childAspectRatio: 0.78,
      ),
      itemCount: peers.length,
      itemBuilder: (context, index) {
        final peer = peers[index];
        return _PassengerCard(
          peer: peer,
          hasWaved: wavedAt.contains(peer.deviceId),
          onTap: () => onTap(peer),
        );
      },
    );
  }
}

// =============================================================================
// Passenger card
// =============================================================================

class _PassengerCard extends StatefulWidget {
  final UserProfile peer;
  final bool hasWaved;
  final VoidCallback onTap;

  const _PassengerCard({
    required this.peer,
    required this.hasWaved,
    required this.onTap,
  });

  @override
  State<_PassengerCard> createState() => _PassengerCardState();
}

class _PassengerCardState extends State<_PassengerCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _pressAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _pressAnim, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _pressAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final peer = widget.peer;

    return GestureDetector(
      onTapDown: (_) => _pressAnim.forward(),
      onTapUp: (_) {
        _pressAnim.reverse();
        widget.onTap();
      },
      onTapCancel: () => _pressAnim.reverse(),
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadius.lgAll,
            border: Border.all(
              color: widget.hasWaved
                  ? AppColors.wave.withValues(alpha: 0.35)
                  : AppColors.glassBorder,
              width: widget.hasWaved ? 1.5 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar + wave badge
                Center(
                  child: AvatarWidget(
                    name: peer.name,
                    size: 56,
                    showWaveBadge: widget.hasWaved,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),

                // Name
                Center(
                  child: Text(
                    peer.name,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 4),

                // Seat badge
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: AppRadius.pillAll,
                    ),
                    child: Text(
                      'Seat ${peer.seatNumber}',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),

                // Occupation
                Row(
                  children: [
                    const Icon(
                      Icons.work_outline_rounded,
                      size: 11,
                      color: AppColors.textTertiary,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        peer.occupation,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),

                // Icebreaker snippet
                if (peer.icebreakerAnswer.isNotEmpty)
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceLight,
                        borderRadius: AppRadius.smAll,
                      ),
                      child: Text(
                        '"${peer.icebreakerAnswer}"',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 10,
                          fontStyle: FontStyle.italic,
                          height: 1.4,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Empty / loading states
// =============================================================================

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final bool showSpinner;

  const _EmptyState({
    required this.icon,
    required this.message,
    this.showSpinner = false,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showSpinner)
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primary,
              ),
            )
          else
            Icon(icon, size: 48, color: AppColors.textTertiary),
          const SizedBox(height: AppSpacing.md),
          Text(
            message,
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ShimmerGrid extends StatefulWidget {
  const _ShimmerGrid();

  @override
  State<_ShimmerGrid> createState() => _ShimmerGridState();
}

class _ShimmerGridState extends State<_ShimmerGrid>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _shimmer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _shimmer = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shimmer,
      builder: (context, _) {
        return GridView.builder(
          padding: const EdgeInsets.all(AppSpacing.md),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: AppSpacing.sm,
            mainAxisSpacing: AppSpacing.sm,
            childAspectRatio: 0.78,
          ),
          itemCount: 6,
          itemBuilder: (_, __) => _ShimmerCard(opacity: _shimmer.value),
        );
      },
    );
  }
}

class _ShimmerCard extends StatelessWidget {
  final double opacity;
  const _ShimmerCard({required this.opacity});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.lgAll,
          border: Border.all(color: AppColors.glassBorder, width: 1),
        ),
      ),
    );
  }
}

// =============================================================================
// Peer detail overlay — Issue 3 fix: X button + tap-outside dismissal
// =============================================================================

class _PeerDetailOverlay extends StatelessWidget {
  final UserProfile peer;
  final bool hasWaved;
  final Animation<double> scaleAnim;
  final Animation<double> opacityAnim;
  final VoidCallback onWave;
  final VoidCallback onClose;

  const _PeerDetailOverlay({
    required this.peer,
    required this.hasWaved,
    required this.scaleAnim,
    required this.opacityAnim,
    required this.onWave,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: opacityAnim,
      child: GestureDetector(
        // Tap the dark scrim to dismiss
        onTap: onClose,
        behavior: HitTestBehavior.opaque,
        child: Container(
          color: Colors.black.withValues(alpha: 0.55),
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            // Absorb taps inside the card so they don't hit the scrim
            onTap: () {},
            child: ScaleTransition(
              scale: scaleAnim,
              alignment: Alignment.bottomCenter,
              child: Container(
                margin: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.xxl,
                  AppSpacing.md,
                  AppSpacing.md,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: AppRadius.xlAll,
                  border: Border.all(
                    color: AppColors.glassBorder,
                    width: 1,
                  ),
                  boxShadow: AppShadows.elevated,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Handle + X button row
                      Row(
                        children: [
                          const Spacer(),
                          Container(
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(
                              color: AppColors.divider,
                              borderRadius: AppRadius.pillAll,
                            ),
                          ),
                          const Spacer(),
                          // X close button (Issue 3 fix)
                          GestureDetector(
                            onTap: onClose,
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: AppColors.surfaceLight,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.glassBorder,
                                  width: 1,
                                ),
                              ),
                              child: const Icon(
                                Icons.close_rounded,
                                size: 16,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // Avatar
                      AvatarWidget(name: peer.name, size: 72),
                      const SizedBox(height: AppSpacing.sm),

                      // Name
                      Text(
                        peer.name,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: AppSpacing.xs),

                      // Meta
                      Text(
                        'Seat ${peer.seatNumber}  |  ${peer.occupation}  |  Age ${peer.age}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      // Icebreaker block
                      if (peer.icebreakerPrompt.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.md),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceLight,
                            borderRadius: AppRadius.mdAll,
                            border: Border.all(
                              color: AppColors.glassBorder,
                              width: 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                peer.icebreakerPrompt,
                                style: TextStyle(
                                  color: AppColors.primary.withValues(alpha: 0.85),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                peer.icebreakerAnswer,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.md),

                      // Wave button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: hasWaved ? null : onWave,
                          icon: Icon(
                            hasWaved
                                ? Icons.check_rounded
                                : Icons.waving_hand_rounded,
                            size: 20,
                          ),
                          label: Text(
                            hasWaved ? 'Waved' : 'Wave',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                hasWaved ? AppColors.surfaceLight : AppColors.wave,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: AppColors.surfaceLight,
                            disabledForegroundColor: AppColors.textSecondary,
                            shape: RoundedRectangleBorder(
                              borderRadius: AppRadius.mdAll,
                            ),
                          ),
                        ),
                      ),
                    ],
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
