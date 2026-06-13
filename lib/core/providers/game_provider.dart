import 'package:flutter_riverpod/flutter_riverpod.dart';

class TicTacToeState {
  final String gameId;
  final String opponentId;
  final String opponentName;
  final bool isChallenger;
  final List<String> board;
  final bool isMyTurn;
  final String? winner;
  final bool opponentDisconnected;

  const TicTacToeState({
    required this.gameId,
    required this.opponentId,
    required this.opponentName,
    required this.isChallenger,
    required this.board,
    required this.isMyTurn,
    this.winner,
    this.opponentDisconnected = false,
  });

  TicTacToeState copyWith({
    String? gameId,
    String? opponentId,
    String? opponentName,
    bool? isChallenger,
    List<String>? board,
    bool? isMyTurn,
    String? winner,
    bool? opponentDisconnected,
  }) {
    return TicTacToeState(
      gameId: gameId ?? this.gameId,
      opponentId: opponentId ?? this.opponentId,
      opponentName: opponentName ?? this.opponentName,
      isChallenger: isChallenger ?? this.isChallenger,
      board: board ?? this.board,
      isMyTurn: isMyTurn ?? this.isMyTurn,
      winner: winner ?? this.winner,
      opponentDisconnected: opponentDisconnected ?? this.opponentDisconnected,
    );
  }

  String? checkWinner() {
    const lines = [
      [0, 1, 2], [3, 4, 5], [6, 7, 8],
      [0, 3, 6], [1, 4, 7], [2, 5, 8],
      [0, 4, 8], [2, 4, 6],
    ];
    for (final line in lines) {
      final a = board[line[0]], b = board[line[1]], c = board[line[2]];
      if (a.isNotEmpty && a == b && b == c) return a;
    }
    if (board.every((cell) => cell.isNotEmpty)) return 'draw';
    return null;
  }
}

class PendingGameInvite {
  final String gameId;
  final String peerId;
  final String peerName;

  const PendingGameInvite({
    required this.gameId,
    required this.peerId,
    required this.peerName,
  });
}

final pendingGameInviteProvider = StateProvider<PendingGameInvite?>((ref) => null);

final ticTacToeProvider = StateNotifierProvider<TicTacToeNotifier, TicTacToeState?>((ref) {
  return TicTacToeNotifier(ref);
});

class TicTacToeNotifier extends StateNotifier<TicTacToeState?> {
  TicTacToeNotifier(this._ref) : super(null);
  
  // ignore: unused_field
  final Ref _ref;

  void startGame(String opponentId, String opponentName, String gameId) {
    state = TicTacToeState(
      gameId: gameId,
      opponentId: opponentId,
      opponentName: opponentName,
      isChallenger: true,
      board: List.filled(9, ''),
      isMyTurn: false, // Waiting for the opponent to accept; isMyTurn → true in onInviteAccepted
    );
  }

  /// Called when the opponent's device is no longer visible on the mesh.
  void markDisconnected() {
    if (state != null && state!.winner == null) {
      state = state!.copyWith(opponentDisconnected: true);
    }
  }

  void onInviteAccepted(String gameId, String opponentId, String opponentName) {
    // If I sent the invite, my state is already populated, I just know it's accepted.
    // If I received the invite, I am O, and it's X's turn (opponent).
    if (state != null && state!.gameId == gameId) {
      // I am challenger, it was accepted. X goes first, so it's my turn.
      state = state!.copyWith(isMyTurn: true);
    } else {
      // I am the opponent accepting.
      state = TicTacToeState(
        gameId: gameId,
        opponentId: opponentId,
        opponentName: opponentName,
        isChallenger: false,
        board: List.filled(9, ''),
        isMyTurn: false, // X (challenger) goes first
      );
    }
  }

  void onMoveReceived(int index) {
    if (state == null) return;
    
    final currentBoard = List<String>.from(state!.board);
    final opponentMarker = state!.isChallenger ? 'O' : 'X';
    
    if (currentBoard[index].isEmpty) {
      currentBoard[index] = opponentMarker;
      state = state!.copyWith(
        board: currentBoard,
        isMyTurn: true,
      );
      
      final winner = state!.checkWinner();
      if (winner != null) {
        state = state!.copyWith(winner: winner);
      }
    }
  }

  void applyMove(int index) {
    if (state == null || !state!.isMyTurn) return;
    
    final currentBoard = List<String>.from(state!.board);
    final myMarker = state!.isChallenger ? 'X' : 'O';
    
    if (currentBoard[index].isEmpty) {
      currentBoard[index] = myMarker;
      state = state!.copyWith(
        board: currentBoard,
        isMyTurn: false,
      );
      
      final winner = state!.checkWinner();
      if (winner != null) {
        state = state!.copyWith(winner: winner);
      }
    }
  }

  void reset() {
    state = null;
  }
}
