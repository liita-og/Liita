/// Identifies which game a [GameMessage] belongs to, so [AppController]
/// can dispatch each packet to the correct game notifier.
enum GameType {
  ticTacToe('ttt', 'Tic Tac Toe'),
  trivia('trivia', 'Cabin Trivia');

  /// Compact wire code sent inside the packet JSON.
  final String code;

  /// Human-readable name for UI (e.g. invite dialogs).
  final String label;

  const GameType(this.code, this.label);

  static GameType fromCode(String code) => GameType.values.firstWhere(
        (e) => e.code == code,
        orElse: () => throw ArgumentError('Unknown GameType code: $code'),
      );
}

enum GameMessageType {
  invite,    // challenger → opponent: "want to play?"
  accept,    // opponent → challenger: "yes"
  decline,   // opponent → challenger: "no" (or busy)
  move,      // tic-tac-toe: a board move
  question,  // trivia: host → guesser
  answer,    // trivia: guesser → host
  result,    // trivia: host → guesser
  end,       // either party: game over
}

class GameMessage {
  final String gameId;
  final GameType gameType;
  final GameMessageType type;
  final Map<String, dynamic> payload;

  const GameMessage({
    required this.gameId,
    required this.gameType,
    required this.type,
    required this.payload,
  });

  Map<String, dynamic> toJson() => {
        'gameId': gameId,
        'gameType': gameType.code,
        'type': type.name,
        'payload': payload,
      };

  factory GameMessage.fromJson(Map<String, dynamic> json) => GameMessage(
        gameId: json['gameId'] as String,
        // Backward-compat: packets without gameType are legacy Tic-Tac-Toe.
        gameType: json['gameType'] != null
            ? GameType.fromCode(json['gameType'] as String)
            : GameType.ticTacToe,
        type: GameMessageType.values.byName(json['type'] as String),
        payload: Map<String, dynamic>.from(json['payload'] as Map),
      );
}
