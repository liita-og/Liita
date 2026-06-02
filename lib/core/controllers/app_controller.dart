import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'package:liita/core/models/mesh_packet.dart';
import 'package:liita/core/models/match_event.dart';
import 'package:liita/core/models/chat_message.dart';
import 'package:liita/core/models/broadcast_message.dart';
import 'package:liita/core/models/user_profile.dart';
import 'package:liita/core/services/database_service.dart';
import 'package:liita/core/services/mesh_service.dart';
import 'package:liita/core/services/crypto_service.dart';
import 'package:liita/core/services/notification_service.dart';

/// Central packet routing engine for the Liita BLE mesh network.
///
/// Subscribes to [MeshService.incomingPackets], applies dedup-first processing,
/// routes each [PayloadType] to the correct handler, persists results via
/// [DatabaseService], and fires notifications via [NotificationService].
///
/// **Regression contracts:**
/// 1. Every incoming packet is dedup-checked FIRST — duplicate packets are
///    silently dropped before any handler executes.
/// 2. Packets whose [originId] equals the local device are silently dropped —
///    the controller never processes its own originated packets.
/// 3. Wave receipt triggers notification; mutual wave auto-creates match.
/// 4. Text messages are decrypted (when a shared key exists) before storage.
/// 5. Broadcast packets are stored and displayed regardless of destination.
class AppController {
  final DatabaseService _db;
  final MeshService _mesh;
  final CryptoService _crypto;
  final NotificationService _notifications;

  /// The local device's unique ID. Set once on [initialize].
  String _localDeviceId = '';

  /// In-memory peer name cache to avoid DB lookups on every notification.
  final Map<String, String> _peerNameCache = {};

  /// Stream subscriptions to clean up on [dispose].
  StreamSubscription<MeshPacket>? _packetSub;
  StreamSubscription<UserProfile>? _peerSub;

  static const _uuid = Uuid();

  AppController({
    required DatabaseService db,
    required MeshService mesh,
    required CryptoService crypto,
    required NotificationService notifications,
  })  : _db = db,
        _mesh = mesh,
        _crypto = crypto,
        _notifications = notifications;

  // ===========================================================================
  // LIFECYCLE
  // ===========================================================================

  /// Initializes the controller: caches the local device ID, starts listening
  /// to incoming packets and discovered peers.
  ///
  /// Must be called once after the mesh service is started.
  Future<void> initialize(String localDeviceId) async {
    _localDeviceId = localDeviceId;

    // Subscribe to discovered peers for name cache
    _peerSub = _mesh.discoveredPeers.listen(_onPeerDiscovered);

    // Subscribe to incoming packets — the core routing loop
    _packetSub = _mesh.incomingPackets.listen(_onPacketReceived);
  }

  /// Tears down all subscriptions. Safe to call multiple times.
  void dispose() {
    _packetSub?.cancel();
    _packetSub = null;
    _peerSub?.cancel();
    _peerSub = null;
    _peerNameCache.clear();
  }

  // ===========================================================================
  // INBOUND ROUTING — THE CORE LOOP
  // ===========================================================================

  /// Entry point for every incoming packet from the mesh.
  ///
  /// Enforces the two regression invariants before dispatching:
  /// 1. Drop if originId == localDeviceId (never process own packets).
  /// 2. Drop if packetId already seen (dedup-first).
  Future<void> _onPacketReceived(MeshPacket packet) async {
    try {
      // ── CONTRACT 1: Never process own originated packets ──
      if (packet.originId == _localDeviceId) return;

      // ── CONTRACT 2: Dedup check FIRST ──
      final alreadySeen = await _db.isPacketSeen(packet.packetId);
      if (alreadySeen) return;

      // Mark as seen immediately to prevent re-processing from relay loops
      await _db.markPacketSeen(packet.packetId);

      // Route to the correct handler based on payload type
      switch (packet.payloadType) {
        case PayloadType.wave:
          await _handleWave(packet);
        case PayloadType.waveAccept:
          await _handleWaveAccept(packet);
        case PayloadType.text:
          await _handleText(packet);
        case PayloadType.profileSync:
          await _handleProfileSync(packet);
        case PayloadType.photoChunk:
          await _handlePhotoChunk(packet);
        case PayloadType.broadcast:
          await _handleBroadcast(packet);
        case PayloadType.ack:
          await _handleAck(packet);
        case PayloadType.game:
          _handleGame(packet);
      }
    } catch (e, st) {
      debugPrint('AppController: error processing packet ${packet.packetId}: $e');
      debugPrint('$st');
    }
  }

  // ===========================================================================
  // HANDLER: WAVE (incoming wave from another peer)
  // ===========================================================================

  /// Records a WAVE_RECEIVED event, fires a notification, and checks if the
  /// local user had previously waved at this peer — if so, auto-creates a match.
  Future<void> _handleWave(MeshPacket packet) async {
    // Ignore waves from blocked peers
    if (await _db.isBlocked(_localDeviceId, packet.originId)) return;

    // Record the incoming wave
    await _db.insertMatchEvent(MatchEvent(
      eventId: _uuid.v4(),
      eventType: MatchEventType.waveReceived,
      actorId: packet.originId,
      targetId: _localDeviceId,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    ));

    // Fire notification
    final senderName = _getPeerName(packet.originId);
    await _notifications.showWaveNotification(senderName);

    // Check for mutual wave → auto-create match
    final weWavedFirst = await _db.hasWaveSent(_localDeviceId, packet.originId);
    if (weWavedFirst) {
      await _createMatch(packet.originId);
    }
  }

  // ===========================================================================
  // HANDLER: WAVE ACCEPT (peer accepted our wave → match)
  // ===========================================================================

  /// A waveAccept means the remote peer waved back at us.
  /// Record the event and create the match.
  Future<void> _handleWaveAccept(MeshPacket packet) async {
    if (await _db.isBlocked(_localDeviceId, packet.originId)) return;

    // Record as a WAVE_RECEIVED from their side (they waved back)
    await _db.insertMatchEvent(MatchEvent(
      eventId: _uuid.v4(),
      eventType: MatchEventType.waveSent,
      actorId: packet.originId,
      targetId: _localDeviceId,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    ));

    // Create the match
    await _createMatch(packet.originId);

    // Extract and store their public key from the data field if present
    if (packet.data.isNotEmpty) {
      await _storeRemotePublicKey(packet.originId, packet.data);
    }
  }

  // ===========================================================================
  // HANDLER: TEXT (encrypted chat message)
  // ===========================================================================

  /// Decrypts (if shared key exists) and stores the incoming text message.
  /// Fires a message notification.
  Future<void> _handleText(MeshPacket packet) async {
    if (await _db.isBlocked(_localDeviceId, packet.originId)) return;

    final matchId = ChatMessage.deriveMatchId(_localDeviceId, packet.originId);
    String plaintext = packet.data;

    // Attempt decryption with the shared key
    final sharedKey = await _crypto.getSharedKey(matchId);
    if (sharedKey != null && packet.data.isNotEmpty) {
      try {
        // The data field contains a JSON-encoded EncryptedPayload
        final payloadJson = jsonDecode(packet.data) as Map<String, dynamic>;
        final encrypted = EncryptedPayload.fromJson(payloadJson);
        plaintext = await _crypto.decrypt(encrypted, sharedKey);
      } catch (e) {
        // Decryption failed — store raw data (mock mode sends plaintext)
        debugPrint('AppController: decrypt failed, storing raw: $e');
        plaintext = packet.data;
      }
    }

    // Store the message
    final message = ChatMessage(
      messageId: _uuid.v4(),
      matchId: matchId,
      fromId: packet.originId,
      toId: _localDeviceId,
      ciphertext: plaintext,
      nonce: '',
      timestamp: packet.timestamp,
    );
    await _db.insertMessage(message);

    // Send ACK back to sender
    await _mesh.sendPacket(MeshPacket(
      packetId: _uuid.v4(),
      originId: _localDeviceId,
      destinationId: packet.originId,
      payloadType: PayloadType.ack,
      data: message.messageId,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    ));

    // Fire notification
    final senderName = _getPeerName(packet.originId);
    final preview = plaintext.length > 40
        ? '${plaintext.substring(0, 40)}...'
        : plaintext;
    await _notifications.showMessageNotification(senderName, preview);
  }

  // ===========================================================================
  // HANDLER: PROFILE SYNC
  // ===========================================================================

  /// Stores or updates the remote peer's full profile from a sync packet.
  Future<void> _handleProfileSync(MeshPacket packet) async {
    try {
      final json = jsonDecode(packet.data) as Map<String, dynamic>;
      final profile = UserProfile.fromJson(json);
      await _db.upsertProfile(profile);
      _peerNameCache[profile.deviceId] = profile.name;
    } catch (e) {
      debugPrint('AppController: profileSync parse failed: $e');
    }
  }

  // ===========================================================================
  // HANDLER: PHOTO CHUNK
  // ===========================================================================

  /// Stores an incoming photo chunk. When all chunks for a photo are received,
  /// the UI layer can reassemble them.
  Future<void> _handlePhotoChunk(MeshPacket packet) async {
    try {
      final json = jsonDecode(packet.data) as Map<String, dynamic>;
      await _db.insertChunk({
        'photo_hash': json['photoHash'] as String,
        'chunk_index': json['chunkIndex'] as int,
        'total_chunks': json['totalChunks'] as int,
        'data': json['data'] as String,
        'received_at': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      debugPrint('AppController: photoChunk parse failed: $e');
    }
  }

  // ===========================================================================
  // HANDLER: BROADCAST (lounge message)
  // ===========================================================================

  /// Stores a broadcast message for display in the Lounge.
  Future<void> _handleBroadcast(MeshPacket packet) async {
    try {
      final json = jsonDecode(packet.data) as Map<String, dynamic>;
      final message = BroadcastMessage.fromJson(json);
      await _db.insertBroadcast(message);
    } catch (e) {
      // Fallback: treat data as raw text with basic metadata
      final senderName = _getPeerName(packet.originId);
      await _db.insertBroadcast(BroadcastMessage(
        messageId: _uuid.v4(),
        fromId: packet.originId,
        senderName: senderName,
        seatNumber: '',
        text: packet.data,
        timestamp: packet.timestamp,
      ));
    }
  }

  // ===========================================================================
  // HANDLER: ACK (delivery confirmation)
  // ===========================================================================

  /// Marks the referenced message as delivered.
  Future<void> _handleAck(MeshPacket packet) async {
    final messageId = packet.data;
    if (messageId.isNotEmpty) {
      await _db.markDelivered(messageId);
    }
  }

  // ===========================================================================
  // HANDLER: GAME (Phase 2 placeholder)
  // ===========================================================================

  /// Placeholder for game packet routing. Will be implemented in Phase 2.
  void _handleGame(MeshPacket packet) {
    debugPrint('AppController: game packet received (not yet implemented)');
  }

  // ===========================================================================
  // OUTBOUND ACTIONS (called by UI)
  // ===========================================================================

  /// Sends a wave to [targetId]. Records a WAVE_SENT event and transmits
  /// the wave packet over the mesh.
  ///
  /// The wave packet's data field contains the local user's public key
  /// (Base64) to enable key exchange on match creation.
  Future<void> sendWave(String targetId) async {
    // Check if already waved
    if (await _db.hasWaveSent(_localDeviceId, targetId)) return;

    // Check if blocked
    if (await _db.isBlocked(_localDeviceId, targetId)) return;

    // Record outgoing wave
    await _db.insertMatchEvent(MatchEvent(
      eventId: _uuid.v4(),
      eventType: MatchEventType.waveSent,
      actorId: _localDeviceId,
      targetId: targetId,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    ));

    // Get public key for key exchange
    String publicKeyBase64 = '';
    try {
      final pubKey = await _crypto.getPublicKey();
      publicKeyBase64 = await _crypto.exportPublicKey(pubKey);
    } catch (e) {
      debugPrint('AppController: could not export public key: $e');
    }

    // Send wave packet
    await _mesh.sendPacket(MeshPacket(
      packetId: _uuid.v4(),
      originId: _localDeviceId,
      destinationId: targetId,
      payloadType: PayloadType.wave,
      data: publicKeyBase64,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  /// Sends an encrypted text message to a matched peer.
  ///
  /// If a shared AES key exists for this match, the message is encrypted
  /// with AES-256-GCM. Otherwise, sends plaintext (mock mode).
  Future<void> sendMessage(String matchId, String plaintext) async {
    // Derive the peer's device ID from the matchId
    final parts = matchId.split(':');
    final peerId = parts.firstWhere(
      (id) => id != _localDeviceId,
      orElse: () => parts.last,
    );

    // Attempt encryption
    String dataPayload = plaintext;
    String nonce = '';
    final sharedKey = await _crypto.getSharedKey(matchId);
    if (sharedKey != null) {
      try {
        final encrypted = await _crypto.encrypt(plaintext, sharedKey);
        dataPayload = jsonEncode(encrypted.toJson());
        nonce = encrypted.nonce;
      } catch (e) {
        debugPrint('AppController: encrypt failed, sending plaintext: $e');
      }
    }

    // Store locally
    final message = ChatMessage(
      messageId: _uuid.v4(),
      matchId: matchId,
      fromId: _localDeviceId,
      toId: peerId,
      ciphertext: plaintext, // Store plaintext locally for display
      nonce: nonce,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    await _db.insertMessage(message);

    // Send over mesh (encrypted payload)
    await _mesh.sendPacket(MeshPacket(
      packetId: _uuid.v4(),
      originId: _localDeviceId,
      destinationId: peerId,
      payloadType: PayloadType.text,
      data: dataPayload,
      timestamp: message.timestamp,
    ));
  }

  /// Sends a broadcast message to the Lounge (destination = '*').
  Future<void> sendBroadcast(String text, UserProfile localProfile) async {
    final message = BroadcastMessage(
      messageId: _uuid.v4(),
      fromId: _localDeviceId,
      senderName: localProfile.name,
      seatNumber: localProfile.seatNumber,
      text: text,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    // Store locally
    await _db.insertBroadcast(message);

    // Send over mesh
    await _mesh.sendPacket(MeshPacket(
      packetId: _uuid.v4(),
      originId: _localDeviceId,
      destinationId: '*',
      payloadType: PayloadType.broadcast,
      data: jsonEncode(message.toJson()),
      timestamp: message.timestamp,
    ));
  }

  /// Blocks a peer. Inserts a BLOCKED event and prevents further interaction.
  Future<void> blockPeer(String peerId) async {
    await _db.insertMatchEvent(MatchEvent(
      eventId: _uuid.v4(),
      eventType: MatchEventType.blocked,
      actorId: _localDeviceId,
      targetId: peerId,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  /// Reports a peer. Inserts a REPORTED event (also blocks).
  Future<void> reportPeer(String peerId) async {
    await _db.insertMatchEvent(MatchEvent(
      eventId: _uuid.v4(),
      eventType: MatchEventType.reported,
      actorId: _localDeviceId,
      targetId: peerId,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    ));
    // Block on report
    await blockPeer(peerId);
  }

  // ===========================================================================
  // INTERNAL HELPERS
  // ===========================================================================

  /// Creates a match between the local user and [peerId].
  /// Records a MATCH_CREATED event, derives the shared key, and fires
  /// a match notification.
  Future<void> _createMatch(String peerId) async {
    final matchId = ChatMessage.deriveMatchId(_localDeviceId, peerId);

    // Record MATCH_CREATED for both sides
    await _db.insertMatchEvent(MatchEvent(
      eventId: _uuid.v4(),
      eventType: MatchEventType.matchCreated,
      actorId: _localDeviceId,
      targetId: peerId,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    ));

    // Attempt key derivation if we have the remote public key
    await _deriveAndStoreSharedKey(peerId, matchId);

    // Fire match notification
    final peerName = _getPeerName(peerId);
    await _notifications.showMatchNotification(peerName);
  }

  /// Stores a remote peer's public key from a wave/waveAccept data field.
  Future<void> _storeRemotePublicKey(String peerId, String base64Key) async {
    try {
      // Update the profile's publicKey field
      final existing = await _db.getProfile(peerId);
      if (existing != null && existing.publicKey.isEmpty) {
        await _db.upsertProfile(existing.copyWith(publicKey: base64Key));
      }
    } catch (e) {
      debugPrint('AppController: storeRemotePublicKey failed: $e');
    }
  }

  /// Derives and stores the ECDH shared secret for encrypted messaging.
  Future<void> _deriveAndStoreSharedKey(
    String peerId,
    String matchId,
  ) async {
    try {
      // Check if we already have a shared key
      final existingKey = await _crypto.getSharedKey(matchId);
      if (existingKey != null) return;

      // Get the remote peer's public key
      final peerProfile = await _db.getProfile(peerId);
      if (peerProfile == null || peerProfile.publicKey.isEmpty) return;

      // Import their public key and derive the shared secret
      final theirPubKey = await _crypto.importPublicKey(peerProfile.publicKey);
      final myPrivKey = await _crypto.getOrCreatePrivateKey();
      final sharedSecret =
          await _crypto.deriveSharedSecret(myPrivKey, theirPubKey);

      // Store for future message encryption/decryption
      await _crypto.storeSharedKey(matchId, sharedSecret);
    } catch (e) {
      debugPrint('AppController: key derivation failed: $e');
    }
  }

  /// Cache discovered peer names for efficient notification rendering.
  void _onPeerDiscovered(UserProfile peer) {
    _peerNameCache[peer.deviceId] = peer.name;
    // Persist to DB for longer-term access — fire-and-forget with error handling
    _db.upsertProfile(peer).catchError((e) {
      debugPrint('AppController: upsertProfile failed for ${peer.deviceId}: $e');
    });
  }

  /// Returns the cached peer name, or a truncated device ID as fallback.
  String _getPeerName(String deviceId) {
    return _peerNameCache[deviceId] ??
        'Traveler ${deviceId.substring(0, 6)}';
  }

  /// Prunes stale dedup entries and photo chunks. Should be called
  /// periodically (e.g. via a timer every 5 minutes).
  Future<void> runMaintenance() async {
    await _db.pruneDedup();
    await _db.pruneStaleChunks();
  }
}
