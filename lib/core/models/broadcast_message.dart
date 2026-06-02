/// A public broadcast message in the Lounge (flight-wide chat).
///
/// Broadcast messages are unencrypted and visible to all peers in mesh range.
class BroadcastMessage {
  final String messageId;
  final String fromId;
  final String senderName;
  final String seatNumber;
  final String text;
  final int timestamp;

  const BroadcastMessage({
    required this.messageId,
    required this.fromId,
    required this.senderName,
    required this.seatNumber,
    required this.text,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'messageId': messageId,
    'fromId': fromId,
    'senderName': senderName,
    'seatNumber': seatNumber,
    'text': text,
    'timestamp': timestamp,
  };

  factory BroadcastMessage.fromJson(Map<String, dynamic> json) =>
      BroadcastMessage(
        messageId: json['messageId'] as String,
        fromId: json['fromId'] as String,
        senderName: json['senderName'] as String,
        seatNumber: json['seatNumber'] as String,
        text: json['text'] as String,
        timestamp: json['timestamp'] as int,
      );

  /// SQLite storage format (snake_case).
  Map<String, dynamic> toDbJson() => {
    'message_id': messageId,
    'from_id': fromId,
    'sender_name': senderName,
    'seat_number': seatNumber,
    'text': text,
    'timestamp': timestamp,
  };

  factory BroadcastMessage.fromDbJson(Map<String, dynamic> row) =>
      BroadcastMessage(
        messageId: row['message_id'] as String,
        fromId: row['from_id'] as String,
        senderName: row['sender_name'] as String,
        seatNumber: row['seat_number'] as String,
        text: row['text'] as String,
        timestamp: row['timestamp'] as int,
      );

  @override
  String toString() => 'BroadcastMessage($senderName/$seatNumber: $text)';
}
