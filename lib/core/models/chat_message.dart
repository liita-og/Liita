/// An encrypted chat message between two matched peers.
///
/// Messages are end-to-end encrypted with AES-GCM. The [ciphertext] and
/// [nonce] are Base64-encoded. The [matchId] is derived by sorting both
/// device IDs and joining with ':'.
class ChatMessage {
  final String messageId;
  final String matchId;
  final String fromId;
  final String toId;
  final String ciphertext;
  final String nonce;
  final int timestamp;
  final bool delivered;
  final bool isRead;

  const ChatMessage({
    required this.messageId,
    required this.matchId,
    required this.fromId,
    required this.toId,
    required this.ciphertext,
    required this.nonce,
    required this.timestamp,
    this.delivered = false,
    this.isRead = false,
  });

  /// Derives a stable matchId from two device IDs.
  /// Always sorts alphabetically and joins with ':'.
  static String deriveMatchId(String deviceA, String deviceB) {
    final sorted = [deviceA, deviceB]..sort();
    return sorted.join(':');
  }

  ChatMessage copyWith({
    String? messageId,
    String? matchId,
    String? fromId,
    String? toId,
    String? ciphertext,
    String? nonce,
    int? timestamp,
    bool? delivered,
    bool? isRead,
  }) {
    return ChatMessage(
      messageId: messageId ?? this.messageId,
      matchId: matchId ?? this.matchId,
      fromId: fromId ?? this.fromId,
      toId: toId ?? this.toId,
      ciphertext: ciphertext ?? this.ciphertext,
      nonce: nonce ?? this.nonce,
      timestamp: timestamp ?? this.timestamp,
      delivered: delivered ?? this.delivered,
      isRead: isRead ?? this.isRead,
    );
  }

  /// JSON for network/packet serialization (camelCase).
  Map<String, dynamic> toJson() => {
    'messageId': messageId,
    'matchId': matchId,
    'fromId': fromId,
    'toId': toId,
    'ciphertext': ciphertext,
    'nonce': nonce,
    'timestamp': timestamp,
    'delivered': delivered,
    'isRead': isRead,
  };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    messageId: json['messageId'] as String,
    matchId: json['matchId'] as String,
    fromId: json['fromId'] as String,
    toId: json['toId'] as String,
    ciphertext: json['ciphertext'] as String,
    nonce: json['nonce'] as String,
    timestamp: json['timestamp'] as int,
    delivered: json['delivered'] == true,
    isRead: json['isRead'] == true,
  );

  /// JSON for SQLite storage (snake_case column names).
  Map<String, dynamic> toDbJson() => {
    'message_id': messageId,
    'match_id': matchId,
    'from_id': fromId,
    'to_id': toId,
    'ciphertext': ciphertext,
    'nonce': nonce,
    'timestamp': timestamp,
    'delivered': delivered ? 1 : 0,
    'is_read': isRead ? 1 : 0,
  };

  factory ChatMessage.fromDbJson(Map<String, dynamic> row) => ChatMessage(
    messageId: row['message_id'] as String,
    matchId: row['match_id'] as String,
    fromId: row['from_id'] as String,
    toId: row['to_id'] as String,
    ciphertext: row['ciphertext'] as String,
    nonce: row['nonce'] as String,
    timestamp: row['timestamp'] as int,
    delivered: (row['delivered'] as int) == 1,
    isRead: (row['is_read'] as int) == 1,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatMessage && messageId == other.messageId;

  @override
  int get hashCode => messageId.hashCode;

  @override
  String toString() => 'ChatMessage($fromId→$toId, delivered=$delivered)';
}
