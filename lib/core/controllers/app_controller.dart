import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
import 'package:liita/core/services/storage_service.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:liita/core/models/game_message.dart';
import 'package:liita/core/providers/game_provider.dart';

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
  final Ref _ref;

  /// The local device's unique ID. Set once on [initialize].
  String _localDeviceId = '';

  bool _initialized = false;

  /// Called when a new match is created. UI layer sets this to update Riverpod state.
  void Function(String peerId)? _onMatchCreated;
  final List<String> _pendingMatches = [];

  set onMatchCreated(void Function(String peerId)? callback) {
    _onMatchCreated = callback;
    if (callback != null) {
      for (final peerId in _pendingMatches) {
        callback(peerId);
      }
      _pendingMatches.clear();
    }
  }

  void Function(String peerId)? get onMatchCreated => _onMatchCreated;

  /// In-memory peer name cache to avoid DB lookups on every notification.
  final Map<String, String> _peerNameCache = {};

  /// Stream subscriptions to clean up on [dispose].
  StreamSubscription<MeshPacket>? _packetSub;
  StreamSubscription<UserProfile>? _peerSub;

  final List<MeshPacket> _incomingQueue = [];
  bool _isProcessingQueue = false;

  static const _uuid = Uuid();

  AppController({
    required DatabaseService db,
    required MeshService mesh,
    required CryptoService crypto,
    required NotificationService notifications,
    required Ref ref,
  })  : _db = db,
        _mesh = mesh,
        _crypto = crypto,
        _notifications = notifications,
        _ref = ref;

  // ===========================================================================
  // LIFECYCLE
  // ===========================================================================

  /// Initializes the controller: caches the local device ID, starts listening
  /// to incoming packets and discovered peers.
  ///
  /// Must be called once after the mesh service is started.
  Future<void> initialize(String localDeviceId) async {
    if (_initialized) return;
    _initialized = true;
    _localDeviceId = localDeviceId;

    _peerSub = _mesh.discoveredPeers.listen(_onPeerDiscovered);
    // RC-7: Handle stream errors to prevent silent subscription termination.
    _packetSub = _mesh.incomingPackets.listen(
      _enqueuePacket,
      onError: (Object e, StackTrace st) {
        debugPrint('AppController: incomingPackets stream error (subscription preserved): $e\n$st');
        // Do NOT cancel — the stream error handler keeps the subscription alive.
      },
      cancelOnError: false,  // Critical: keep listening after errors
    );
  }

  /// Tears down all subscriptions. Safe to call multiple times.
  void dispose() {
    _packetSub?.cancel();
    _packetSub = null;
    _peerSub?.cancel();
    _peerSub = null;
    _peerNameCache.clear();
    _incomingQueue.clear();
    _isProcessingQueue = false;
  }

  // ===========================================================================
  // INBOUND ROUTING — THE CORE LOOP
  // ===========================================================================

  void _enqueuePacket(MeshPacket packet) {
    _incomingQueue.add(packet);
    _processQueue();
  }

  Future<void> _processQueue() async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;

    try {
      while (_incomingQueue.isNotEmpty) {
        final packet = _incomingQueue.removeAt(0);
        await _onPacketReceived(packet);
      }
    } finally {
      _isProcessingQueue = false;
    }
  }

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
      // RC-9: Use an atomic markIfUnseen that returns false if already recorded.
      // This eliminates the TOCTOU window between isPacketSeen and markPacketSeen.
      final isNew = await _db.markPacketSeenIfNew(packet.packetId);
      if (!isNew) return;

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
    final senderName = await _getPeerName(packet.originId);
    await _notifications.showWaveNotification(senderName);

    // Update wavedByProvider through a new callback if we have one, or just update state directly from UI.
    // We will fire a general callback if needed, but since AppController doesn't have ref,
    // we assume UI polling or stream handles it.

    // Store their public key from the wave data field (needed for key exchange)
    if (packet.data.isNotEmpty) {
      await _storeRemotePublicKey(packet.originId, packet.data);
    }

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

    // RC-14 FIX: Record as waveReceived — they waved (accepted) us.
    await _db.insertMatchEvent(MatchEvent(
      eventId: _uuid.v4(),
      eventType: MatchEventType.waveReceived,
      actorId: packet.originId,
      targetId: _localDeviceId,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    ));

    // Extract and store their public key from the data field if present
    if (packet.data.isNotEmpty) {
      await _storeRemotePublicKey(packet.originId, packet.data);
    }

    // Create the match
    await _createMatch(packet.originId);
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
      packetId: const Uuid().v4(),
      originId: _localDeviceId,
      destinationId: packet.originId,
      payloadType: PayloadType.ack,
      data: message.messageId,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    ));

    // Fire notification
    final senderName = await _getPeerName(packet.originId);
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
      final senderName = await _getPeerName(packet.originId);
      await _db.insertBroadcast(BroadcastMessage(
        messageId: const Uuid().v4(),
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
  // HANDLER: GAME (Phase 2 placeholder -> Implemented for TicTacToe)
  // ===========================================================================

  /// Routes incoming game packets to the respective providers.
  Future<void> _handleGame(MeshPacket packet) async {
    try {
      final gm = GameMessage.fromJson(jsonDecode(packet.data));
      final notifier = _ref.read(ticTacToeProvider.notifier);

      switch (gm.type) {
        case GameMessageType.invite:
          // If already in a game, auto-decline (busy).
          if (_ref.read(ticTacToeProvider) != null) {
            await sendGameMessage(
              packet.originId,
              GameMessage(
                gameId: gm.gameId,
                type: GameMessageType.decline,
                payload: {'reason': 'busy'},
              ),
            );
            break;
          }
          _ref.read(pendingGameInviteProvider.notifier).state = PendingGameInvite(
            gameId: gm.gameId,
            peerId: packet.originId,
            peerName: await _getPeerName(packet.originId),
          );
          break;
        case GameMessageType.accept:
          notifier.onInviteAccepted(
            gm.gameId, 
            packet.originId,
            await _getPeerName(packet.originId)
          );
          break;
        case GameMessageType.decline:
          notifier.reset();
          break;
        case GameMessageType.move:
          notifier.onMoveReceived(gm.payload['index'] as int);
          break;
        case GameMessageType.end:
          notifier.reset();
          break;
      }
    } catch (e) {
      debugPrint('[AppController] _handleGame error: $e');
    }
  }

  // ===========================================================================
  // OUTBOUND ACTIONS (called by UI)
  // ===========================================================================

  Future<void> sendGameMessage(String peerId, GameMessage gm) async {
    await _mesh.sendPacket(MeshPacket(
      packetId: const Uuid().v4(),
      originId: _localDeviceId,
      destinationId: peerId,
      payloadType: PayloadType.game,
      data: jsonEncode(gm.toJson()),
      timestamp: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  /// Sends a wave to [targetId]. Records a WAVE_SENT event and transmits
  /// the wave packet over the mesh.
  ///
  /// The wave packet's data field contains the local user's public key
  /// (Base64) to enable key exchange on match creation.
  Future<void> sendWave(String targetId) async {
    // RC-10: Log the suppressed re-wave so stale DB state is diagnosable.
    if (await _db.hasWaveSent(_localDeviceId, targetId)) {
      debugPrint('AppController.sendWave: suppressed duplicate wave to $targetId (already in DB)');
      return;
    }

    if (await _db.isBlocked(_localDeviceId, targetId)) return;

    await _db.insertMatchEvent(MatchEvent(
      eventId: _uuid.v4(),
      eventType: MatchEventType.waveSent,
      actorId: _localDeviceId,
      targetId: targetId,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    ));

    // RC-11: If key export fails, abort the wave rather than sending an empty key.
    // An empty key permanently breaks E2E encryption for this match.
    String publicKeyBase64;
    try {
      final pubKey = await _crypto.getPublicKey();
      publicKeyBase64 = await _crypto.exportPublicKey(pubKey);
    } catch (e, st) {
      debugPrint('AppController.sendWave: key export failed — wave aborted: $e\n$st');
      // Roll back the WAVE_SENT event we just inserted since the wave wasn't sent.
      await _db.deleteMatchEvent(eventType: MatchEventType.waveSent, actorId: _localDeviceId, targetId: targetId);
      return;
    }

    // Send wave packet
    await _mesh.sendPacket(MeshPacket(
      packetId: const Uuid().v4(),
      originId: _localDeviceId,
      destinationId: targetId,
      payloadType: PayloadType.wave,
      data: publicKeyBase64,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    ));

    // Race-condition fix: if they already waved at us before this wave was
    // recorded, send a waveAccept immediately so their device can create the
    // match without waiting for another round-trip.
    final theyAlreadyWaved = await _db.hasWaveFrom(targetId, _localDeviceId);
    if (theyAlreadyWaved) {
      debugPrint('AppController.sendWave: mutual wave detected, sending waveAccept to $targetId');
      await _sendWaveAccept(targetId, publicKeyBase64);
      await _createMatch(targetId);
    }
  }

  /// Sends a waveAccept packet to [targetId], carrying our public key.
  /// Called when a mutual wave is detected at send-time (race-condition fix).
  Future<void> _sendWaveAccept(String targetId, String publicKeyBase64) async {
    await _mesh.sendPacket(MeshPacket(
      packetId: const Uuid().v4(),
      originId: _localDeviceId,
      destinationId: targetId,
      payloadType: PayloadType.waveAccept,
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
      messageId: const Uuid().v4(),
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
      packetId: const Uuid().v4(),
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
      eventId: const Uuid().v4(),
      eventType: MatchEventType.blocked,
      actorId: _localDeviceId,
      targetId: peerId,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  /// Reports a peer. Inserts a REPORTED event (also blocks).
  Future<void> reportPeer(String peerId) async {
    await _db.insertMatchEvent(MatchEvent(
      eventId: const Uuid().v4(),
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

    // Guard: don't create a duplicate match
    final existingMatch = await _db.hasMatchCreated(_localDeviceId, peerId);
    if (existingMatch) return;

    // Record MATCH_CREATED for both sides
    await _db.insertMatchEvent(MatchEvent(
      eventId: const Uuid().v4(),
      eventType: MatchEventType.matchCreated,
      actorId: _localDeviceId,
      targetId: peerId,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    ));

    // Attempt key derivation if we have the remote public key
    await _deriveAndStoreSharedKey(peerId, matchId);

    // Notify the matches stream so matchesProvider updates live.
    _db.notifyMatchesChanged(_localDeviceId);

    // Fire match notification
    final peerName = await _getPeerName(peerId);
    await _notifications.showMatchNotification(peerName);
    
    if (_onMatchCreated == null) {
      debugPrint('[AppController] WARNING: onMatchCreated is null at match creation time. Queueing peerId: $peerId');
      _pendingMatches.add(peerId);
    } else {
      _onMatchCreated?.call(peerId);
    }

    // Send our photo to the new match in chunks
    _sendPhotoChunks(peerId);
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

  /// Returns the cached peer name, or "Someone" as fallback if missing.
  Future<String> _getPeerName(String deviceId) async {
    if (_peerNameCache.containsKey(deviceId)) {
      return _peerNameCache[deviceId]!;
    }
    final profile = await _db.getProfile(deviceId);
    if (profile != null && profile.name.isNotEmpty) {
      _peerNameCache[deviceId] = profile.name;
      return profile.name;
    }
    return 'Someone';
  }

  /// Slices the local profile photo into small chunks and transmits them to [targetId].
  Future<void> _sendPhotoChunks(String targetId) async {
    try {
      final profile = await StorageService.instance.loadProfile();
      if (profile == null || profile.photoHash == null) return;
      
      final file = File(profile.photoHash!);
      if (!file.existsSync()) return;

      final bytes = await file.readAsBytes();
      final base64Photo = base64Encode(bytes);
      
      final chunkSize = 200;
      final totalChunks = (base64Photo.length / chunkSize).ceil();
      
      for (int i = 0; i < totalChunks; i++) {
        final start = i * chunkSize;
        final end = (start + chunkSize < base64Photo.length) 
            ? start + chunkSize 
            : base64Photo.length;
        final chunkData = base64Photo.substring(start, end);
        
        final payload = {
          'photoHash': profile.photoHash,
          'chunkIndex': i,
          'totalChunks': totalChunks,
          'data': chunkData,
        };

        await _mesh.sendPacket(MeshPacket(
          packetId: const Uuid().v4(),
          originId: _localDeviceId,
          destinationId: targetId,
          payloadType: PayloadType.photoChunk,
          data: jsonEncode(payload),
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ));
        
        await Future.delayed(const Duration(milliseconds: 50));
      }
    } catch (e) {
      debugPrint('AppController: failed to send photo chunks: $e');
    }
  }

  /// Prunes stale dedup entries and photo chunks. Should be called
  /// periodically (e.g. via a timer every 5 minutes).
  Future<void> runMaintenance() async {
    await _db.pruneDedup();
    await _db.pruneStaleChunks();
  }
}
