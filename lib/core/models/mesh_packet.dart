/// Represents a packet in the Liita BLE mesh network.
///
/// Packets are the fundamental unit of communication — they carry waves,
/// messages, profile syncs, and more. Each packet has a TTL (starting at 8)
/// for relay control and a unique [packetId] for deduplication.
class MeshPacket {
  final String packetId;
  final String originId;
  final String destinationId;
  final int ttl;
  final PayloadType payloadType;
  final String data;
  final int timestamp;

  const MeshPacket({
    required this.packetId,
    required this.originId,
    required this.destinationId,
    this.ttl = 8,
    required this.payloadType,
    this.data = '',
    required this.timestamp,
  });

  /// Whether this is a broadcast packet (destination is '*').
  bool get isBroadcast => destinationId == '*';

  MeshPacket copyWith({
    String? packetId,
    String? originId,
    String? destinationId,
    int? ttl,
    PayloadType? payloadType,
    String? data,
    int? timestamp,
  }) {
    return MeshPacket(
      packetId: packetId ?? this.packetId,
      originId: originId ?? this.originId,
      destinationId: destinationId ?? this.destinationId,
      ttl: ttl ?? this.ttl,
      payloadType: payloadType ?? this.payloadType,
      data: data ?? this.data,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  Map<String, dynamic> toJson() => {
    'p': packetId,
    'o': originId,
    'd': destinationId,
    'l': ttl,
    'y': payloadType.code,
    'a': data,
    't': timestamp,
  };

  factory MeshPacket.fromJson(Map<String, dynamic> json) => MeshPacket(
    packetId: json['p'] as String,
    originId: json['o'] as String,
    destinationId: json['d'] as String,
    ttl: json['l'] as int? ?? 8,
    payloadType: PayloadType.fromCode(json['y'] as String),
    data: json['a'] as String? ?? '',
    timestamp: json['t'] as int,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MeshPacket && packetId == other.packetId;

  @override
  int get hashCode => packetId.hashCode;

  @override
  String toString() =>
      'MeshPacket(${payloadType.code}: $originId→$destinationId, ttl=$ttl)';
}

/// Payload types for mesh packets — single-char codes for compact BLE transmission.
enum PayloadType {
  wave('w'),
  waveAccept('a'),
  text('t'),
  profileSync('p'),
  photoChunk('c'),
  broadcast('b'),
  ack('k'),
  game('g');

  final String code;
  const PayloadType(this.code);

  static PayloadType fromCode(String code) {
    return PayloadType.values.firstWhere(
      (e) => e.code == code,
      orElse: () => throw ArgumentError('Unknown PayloadType code: $code'),
    );
  }
}
