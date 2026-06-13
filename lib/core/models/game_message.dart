enum GameMessageType { invite, accept, decline, move, end }

class GameMessage {
  final String gameId;
  final GameMessageType type;
  final Map<String, dynamic> payload;

  const GameMessage({
    required this.gameId,
    required this.type,
    required this.payload,
  });

  Map<String, dynamic> toJson() => {
    'gameId': gameId,
    'type': type.name,
    'payload': payload,
  };

  factory GameMessage.fromJson(Map<String, dynamic> json) => GameMessage(
    gameId: json['gameId'] as String,
    type: GameMessageType.values.byName(json['type'] as String),
    payload: Map<String, dynamic>.from(json['payload'] as Map),
  );
}
