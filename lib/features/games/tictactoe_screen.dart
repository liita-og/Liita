import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:liita/core/theme/app_theme.dart';
import 'package:liita/core/providers/providers.dart';
import 'package:liita/core/providers/game_provider.dart';
import 'package:liita/core/models/game_message.dart';

class TicTacToeScreen extends ConsumerStatefulWidget {
  const TicTacToeScreen({super.key});

  @override
  ConsumerState<TicTacToeScreen> createState() => _TicTacToeScreenState();
}

class _TicTacToeScreenState extends ConsumerState<TicTacToeScreen> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ticTacToeProvider);

    // ── Opponent disconnect detection ─────────────────────────────────────────
    // Watch the live peer list. If the opponent disappears while game is active
    // (no winner yet, not already flagged), mark them as disconnected.
    ref.listen(peersProvider, (_, peersAsync) {
      final gs = ref.read(ticTacToeProvider);
      if (gs == null || gs.winner != null || gs.opponentDisconnected) return;
      peersAsync.whenData((peers) {
        final stillThere = peers.any((p) => p.deviceId == gs.opponentId);
        if (!stillThere) {
          ref.read(ticTacToeProvider.notifier).markDisconnected();
        }
      });
    });

    if (state == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
            onPressed: () => context.pop(),
          ),
        ),
        body: const Center(
          child: Text(
            'Game not found or ended',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    final isFinished = state.winner != null;
    final isDisconnected = state.opponentDisconnected;
    final myMarker = state.isChallenger ? 'X' : 'O';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        automaticallyImplyLeading: false, // no back during active play
        centerTitle: true,
        title: Text(
          'Tic Tac Toe  vs  ${state.opponentName}',
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 18),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── Disconnect banner ─────────────────────────────────────────
            if (isDisconnected)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.wifi_off_rounded, color: AppColors.error, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${state.opponentName} disconnected',
                        style: const TextStyle(color: AppColors.error, fontSize: 13),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        ref.read(ticTacToeProvider.notifier).reset();
                        if (context.canPop()) {
                          context.pop();
                        } else {
                          context.go('/games');
                        }
                      },
                      child: const Text(
                        'Exit',
                        style: TextStyle(color: AppColors.error, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 20),

            // ── Marker & turn indicator ───────────────────────────────────
            Text(
              'You are $myMarker',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isDisconnected
                  ? 'Opponent left the game'
                  : (isFinished
                      ? 'Game Over'
                      : (state.isMyTurn
                          ? 'Your turn'
                          : "${state.opponentName}'s turn")),
              style: TextStyle(
                color: (state.isMyTurn && !isFinished && !isDisconnected)
                    ? AppColors.primary
                    : AppColors.textTertiary,
                fontSize: 16,
              ),
            ),

            const Spacer(),

            // ── Grid ─────────────────────────────────────────────────────
            Opacity(
              opacity: (isFinished || isDisconnected) ? 0.5 : 1.0,
              child: Center(
                child: SizedBox(
                  width: MediaQuery.of(context).size.width * 0.7,
                  height: MediaQuery.of(context).size.width * 0.7,
                  child: GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                    ),
                    itemCount: 9,
                    itemBuilder: (context, index) {
                      final cell = state.board[index];
                      final canTap =
                          !isFinished && !isDisconnected && state.isMyTurn && cell.isEmpty;
                      return GestureDetector(
                        onTap: canTap
                            ? () {
                                ref.read(ticTacToeProvider.notifier).applyMove(index);
                                ref.read(appControllerProvider).sendGameMessage(
                                  state.opponentId,
                                  GameMessage(
                                    gameId: state.gameId,
                                    gameType: GameType.ticTacToe,
                                    type: GameMessageType.move,
                                    payload: {'index': index},
                                  ),
                                );
                              }
                            : null,
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.glassBorder),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            cell,
                            style: TextStyle(
                              fontSize: 48,
                              fontWeight: FontWeight.bold,
                              color: cell == 'X' ? AppColors.primary : Colors.deepOrange,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),

            const Spacer(),

            // ── Result area ───────────────────────────────────────────────
            if (isFinished && !isDisconnected)
              Column(
                children: [
                  Text(
                    state.winner == 'draw'
                        ? 'Draw'
                        : (state.winner == myMarker ? 'You win!' : 'You lose!'),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Exit
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.surfaceLight,
                          foregroundColor: AppColors.textPrimary,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999)),
                        ),
                        onPressed: () {
                          ref.read(ticTacToeProvider.notifier).reset();
                          if (context.canPop()) {
                            context.pop();
                          } else {
                            context.go('/games');
                          }
                        },
                        child: const Text('Exit'),
                      ),
                      const SizedBox(width: 16),
                      // Play Again
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.textOnPrimary,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999)),
                        ),
                        onPressed: () {
                          final opponentId = state.opponentId;
                          final opponentName = state.opponentName;
                          final newGameId = const Uuid().v4();
                          ref.read(appControllerProvider).sendGameMessage(
                            opponentId,
                            GameMessage(
                              gameId: newGameId,
                              gameType: GameType.ticTacToe,
                              type: GameMessageType.invite,
                              payload: {},
                            ),
                          );
                          ref.read(ticTacToeProvider.notifier).startGame(
                            opponentId,
                            opponentName,
                            newGameId,
                          );
                        },
                        child: const Text('Play Again'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
