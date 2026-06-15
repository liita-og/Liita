import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:liita/core/theme/app_theme.dart';
import 'package:liita/core/providers/providers.dart';
import 'package:liita/core/providers/game_provider.dart';
import 'package:liita/core/models/game_message.dart';
import 'package:liita/core/widgets/avatar_widget.dart';

class MatchesScreen extends ConsumerWidget {
  const MatchesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matchesAsync = ref.watch(matchesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Connections',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Mutual waves',
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── List ────────────────────────────────────────────────────────
            Expanded(
              child: matchesAsync.when(
                data: (matchIds) {
                  if (matchIds.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 80),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                shape: BoxShape.circle,
                                border: Border.all(color: AppColors.glassBorder, width: 1),
                              ),
                              child: const Icon(
                                Icons.people_outline_rounded,
                                color: AppColors.textTertiary,
                                size: 24,
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'No connections yet',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Wave at someone on the Radar to get a connection',
                              style: TextStyle(
                                color: AppColors.textTertiary,
                                fontSize: 13,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 100),
                    itemCount: matchIds.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) => _MatchTile(peerId: matchIds[i]),
                  );
                },
                loading: () => const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.textTertiary,
                    strokeWidth: 1.5,
                  ),
                ),
                error: (e, _) => Center(
                  child: Text('$e', style: const TextStyle(color: AppColors.error, fontSize: 13)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MatchTile extends ConsumerWidget {
  final String peerId;

  const _MatchTile({required this.peerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(matchProfileProvider(peerId));

    return profileAsync.when(
      data: (profile) {
        if (profile == null) return const SizedBox.shrink();
        final matchId = _deriveMatchId(
          ref.read(localProfileProvider)?.deviceId ?? '',
          peerId,
        );
        return GestureDetector(
          onTap: () => context.push(
            '/chat/$matchId?name=${Uri.encodeComponent(profile.name)}',
          ),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.glassBorder, width: 1),
            ),
            child: Row(
              children: [
                AvatarWidget(profile: profile, size: 48),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.name,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                // ── Action buttons ───────────────────────────────────────
                IconButton(
                  icon: const Icon(Icons.sports_esports_outlined, color: AppColors.textSecondary),
                  tooltip: 'Play a game',
                  onPressed: () => _showGamePicker(context, ref, peerId, profile.name),
                ),
                IconButton(
                  icon: const Icon(Icons.chat_bubble_outline_rounded, color: AppColors.primary),
                  onPressed: () => context.push(
                    '/chat/$matchId?name=${Uri.encodeComponent(profile.name)}',
                  ),
                ),
              ],
            ),
          ),
        );
      },
      loading: () => Container(
        height: 72,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  String _deriveMatchId(String a, String b) {
    final sorted = [a, b]..sort();
    return sorted.join(':');
  }
}

// ---------------------------------------------------------------------------
// Game-picker bottom sheet (shown when the game icon is tapped in MatchTile)
// ---------------------------------------------------------------------------

void _showGamePicker(
  BuildContext context,
  WidgetRef ref,
  String peerId,
  String peerName,
) {
  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _GamePickerSheet(peerId: peerId, peerName: peerName, ref: ref),
  );
}

class _GameEntry {
  final String title;
  final IconData icon;
  final bool available;
  final String routePath;
  final GameType gameType;
  const _GameEntry(
    this.title,
    this.icon, {
    this.available = false,
    this.routePath = '',
    this.gameType = GameType.ticTacToe,
  });
}

const _availableGames = [
  _GameEntry('Tic-Tac-Toe', Icons.grid_3x3_rounded, available: true, routePath: '/games/tictactoe', gameType: GameType.ticTacToe),
  _GameEntry('Cabin Trivia', Icons.help_outline_rounded, available: true, routePath: '/games/trivia', gameType: GameType.trivia),
  _GameEntry('Word Chain', Icons.link_rounded),
  _GameEntry('Chess', Icons.sports_esports_outlined),
  _GameEntry('Battleship', Icons.radar_rounded),
];

class _GamePickerSheet extends StatelessWidget {
  final String peerId;
  final String peerName;
  final WidgetRef ref;

  const _GamePickerSheet({
    required this.peerId,
    required this.peerName,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
            child: Text(
              'Play with $peerName',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Text(
              'Choose a game',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
            ),
          ),
          ...List.generate(_availableGames.length, (i) {
            final g = _availableGames[i];
            return ListTile(
              leading: Icon(
                g.icon,
                color: g.available ? AppColors.primary : AppColors.textTertiary,
              ),
              title: Text(
                g.title,
                style: TextStyle(
                  color: g.available ? AppColors.textPrimary : AppColors.textSecondary,
                  fontSize: 15,
                ),
              ),
              trailing: g.available
                  ? const Icon(Icons.chevron_right_rounded, color: AppColors.primary)
                  : Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'Coming Soon',
                        style: TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
              onTap: g.available
                  ? () {
                      Navigator.pop(context);
                      final gameId = const Uuid().v4();
                      ref.read(appControllerProvider).sendGameMessage(
                        peerId,
                        GameMessage(
                          gameId: gameId,
                          gameType: g.gameType,
                          type: GameMessageType.invite,
                          payload: {},
                        ),
                      );
                      switch (g.gameType) {
                        case GameType.ticTacToe:
                          ref.read(ticTacToeProvider.notifier).startGame(peerId, peerName, gameId);
                          break;
                        case GameType.trivia:
                          ref.read(triviaGameProvider.notifier).startGame(peerId, peerName, gameId);
                          break;
                      }
                      context.push(g.routePath);
                    }
                  : null,
            );
          }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
