import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:liita/core/theme/app_theme.dart';
import 'package:liita/core/providers/providers.dart';
import 'package:liita/core/providers/game_provider.dart';
import 'package:liita/core/models/game_message.dart';
import 'package:liita/core/widgets/avatar_widget.dart';

// ---------------------------------------------------------------------------
// Game catalogue
// ---------------------------------------------------------------------------

class _Game {
  final String title;
  final String description;
  final IconData icon;
  final bool available;

  const _Game(this.title, this.description, this.icon, {this.available = false});
}

const _games = [
  _Game(
    'Tic-Tac-Toe',
    'Classic, now at 30,000 feet',
    Icons.grid_3x3_rounded,
    available: true,
  ),
  _Game('Trivia', 'Test your knowledge against the cabin', Icons.help_outline_rounded),
  _Game('Word Chain', 'Keep the chain going or lose', Icons.link_rounded),
  _Game('Chess', 'A game of strategy and patience', Icons.sports_esports_outlined),
  _Game('Battleship', 'Sink the fleet', Icons.radar_rounded),
];

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class GamesScreen extends ConsumerWidget {
  const GamesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 16, 24, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Games',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.5,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Play with your connections',
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 100),
                itemCount: _games.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final game = _games[i];
                  return _GameCard(
                    game: game,
                    onTap: game.available
                        ? () => _showMatchPicker(context, ref, game)
                        : null,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Opens a bottom sheet listing the user's mutual connections so they can
  /// pick who to challenge for [game].
  void _showMatchPicker(BuildContext context, WidgetRef ref, _Game game) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (ctx) => _MatchPickerSheet(game: game),
    );
  }
}

// ---------------------------------------------------------------------------
// Game card
// ---------------------------------------------------------------------------

class _GameCard extends StatelessWidget {
  final _Game game;
  final VoidCallback? onTap;

  const _GameCard({required this.game, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: game.available ? AppColors.primary.withValues(alpha: 0.25) : AppColors.glassBorder,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: game.available
                    ? AppColors.primary.withValues(alpha: 0.12)
                    : AppColors.surfaceLight,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.glassBorder, width: 1),
              ),
              child: Icon(
                game.icon,
                color: game.available ? AppColors.primary : AppColors.textTertiary,
                size: 18,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    game.title,
                    style: TextStyle(
                      color: game.available ? AppColors.textPrimary : AppColors.textSecondary,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    game.description,
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            if (!game.available)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
              )
            else
              const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Match-picker bottom sheet
// ---------------------------------------------------------------------------

class _MatchPickerSheet extends ConsumerWidget {
  final _Game game;

  const _MatchPickerSheet({required this.game});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matchesAsync = ref.watch(matchesProvider);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
            child: Text(
              'Challenge someone to ${game.title}',
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
              'Pick a connection to invite',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
            ),
          ),
          matchesAsync.when(
            data: (matchIds) {
              if (matchIds.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: Text(
                      'No connections yet — wave at someone first!',
                      style: TextStyle(color: AppColors.textTertiary, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              return ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.5,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  itemCount: matchIds.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                  itemBuilder: (context, i) =>
                      _PeerRow(peerId: matchIds[i], game: game),
                ),
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: CircularProgressIndicator(
                  color: AppColors.textTertiary,
                  strokeWidth: 1.5,
                ),
              ),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(32),
              child: Text('$e', style: const TextStyle(color: AppColors.error)),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Individual peer row inside the sheet
// ---------------------------------------------------------------------------

class _PeerRow extends ConsumerWidget {
  final String peerId;
  final _Game game;

  const _PeerRow({required this.peerId, required this.game});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(matchProfileProvider(peerId));

    return profileAsync.when(
      data: (profile) {
        if (profile == null) return const SizedBox.shrink();
        return ListTile(
          leading: AvatarWidget(profile: profile, size: 40),
          title: Text(
            profile.name,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
          ),
          trailing: const Icon(Icons.send_rounded, color: AppColors.primary, size: 20),
          onTap: () {
            Navigator.pop(context); // close sheet
            final gameId = const Uuid().v4();
            ref.read(appControllerProvider).sendGameMessage(
              peerId,
              GameMessage(
                gameId: gameId,
                type: GameMessageType.invite,
                payload: {},
              ),
            );
            ref.read(ticTacToeProvider.notifier).startGame(peerId, profile.name, gameId);
            context.push('/games/tictactoe');
          },
        );
      },
      loading: () => const SizedBox(height: 56),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
