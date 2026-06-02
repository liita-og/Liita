/// Types of match events in the wave-to-match flow.
///
/// These map exactly to the architecture doc's event types.
/// Match derivation: mutual WAVE_SENT events with no BLOCKED event.
enum MatchEventType {
  waveSent('WAVE_SENT'),
  waveReceived('WAVE_RECEIVED'),
  matchCreated('MATCH_CREATED'),
  blocked('BLOCKED'),
  reported('REPORTED');

  final String value;
  const MatchEventType(this.value);

  static MatchEventType fromString(String value) {
    return MatchEventType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => throw ArgumentError('Unknown MatchEventType: $value'),
    );
  }
}

/// An append-only event recording wave/match/block actions between peers.
class MatchEvent {
  final String eventId;
  final MatchEventType eventType;
  final String actorId;
  final String targetId;
  final int timestamp;

  const MatchEvent({
    required this.eventId,
    required this.eventType,
    required this.actorId,
    required this.targetId,
    required this.timestamp,
  });

  factory MatchEvent.fromJson(Map<String, dynamic> json) {
    return MatchEvent(
      eventId: json['event_id'] as String,
      eventType: MatchEventType.fromString(json['event_type'] as String),
      actorId: json['actor_id'] as String,
      targetId: json['target_id'] as String,
      timestamp: json['timestamp'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'event_id': eventId,
      'event_type': eventType.value,
      'actor_id': actorId,
      'target_id': targetId,
      'timestamp': timestamp,
    };
  }

  @override
  String toString() =>
      'MatchEvent(${eventType.value}: $actorId→$targetId)';
}
