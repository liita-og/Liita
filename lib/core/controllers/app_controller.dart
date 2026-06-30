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
import 'package:liita/core/providers/alert_provider.dart';

/// A reliable unicast packet awaiting acknowledgement from its destination.
class _PendingSend {
  final MeshPacket packet;
  final String? messageId; // text only: flips the chat "delivered" flag on ACK
  int attempts;
  int nextRetryAtMs;
  _PendingSend(this.packet, this.messageId, this.attempts, this.nextRetryAtMs);
}

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

  // ── Reliable delivery (ARQ) ──
  // Unicast packets awaiting an ACK from their destination, keyed by packetId.
  // The mesh is best-effort, so each reliable packet is retransmitted (with the
  // same packetId, which the receiver dedups) until it is acknowledged or the
  // attempt budget is exhausted.
  final Map<String, _PendingSend> _pendingSends = {};
  Timer? _retryTimer;
  bool _isRetrying = false;
  static const int _retryBaseMs = 3000; // grows linearly per attempt
  static const int _retryMaxAttempts = 5;

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
    _retryTimer?.cancel();
    _retryTimer = null;
    _pendingSends.clear();
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
  /// Invariants:
  /// 1. Drop if originId == localDeviceId (never process own packets).
  /// 2. ACK every reliable unicast addressed to us — including duplicates — so
  ///    the sender's retransmit loop terminates even if an earlier ACK was lost.
  /// 3. Run the handler only on first sighting (dedup) — process exactly once.
  Future<void> _onPacketReceived(MeshPacket packet) async {
    try {
      // ── CONTRACT 1: Never process own originated packets ──
      if (packet.originId == _localDeviceId) return;

      // ── ACK-ALWAYS: reliable unicast addressed to us is acknowledged on
      // every receipt, before the dedup gate, so retransmitted duplicates
      // (whose original ACK was lost) still get acknowledged.
      if (packet.destinationId == _localDeviceId &&
          _isReliable(packet.payloadType)) {
        await _sendAck(packet.packetId, packet.originId);
      }

      // ── CONTRACT 3: Dedup — process exactly once.
      // RC-9: atomic markIfUnseen returns false if already recorded.
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
          await _handleGame(packet);
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

    // Store their public key from the wave data field (needed for key exchange)
    if (packet.data.isNotEmpty) {
      await _storeRemotePublicKey(packet.originId, packet.data);
    }

    // Check for mutual wave → auto-create match (which fires the "connected"
    // notification). Otherwise, notify that this peer waved at us.
    final weWavedFirst = await _db.hasWaveSent(_localDeviceId, packet.originId);
    if (weWavedFirst) {
      await _createMatch(packet.originId);
    } else {
      final senderName = await _getPeerName(packet.originId);
      await _notifications.showWaveNotification(senderName);
      // Surface an in-app banner too (complements the system notification).
      _ref.read(incomingAlertProvider.notifier).state = RadarAlert(
        kind: RadarAlertKind.wave,
        peerId: packet.originId,
        peerName: senderName,
      );
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
    final sharedKey = await _getOrDeriveSharedKey(packet.originId, matchId);
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

    // (The ACK is sent centrally in _onPacketReceived for all reliable types.)

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

  /// Resolves a reliable send: the ACK's data carries the original packetId.
  /// Clears it from the retransmit table and, for text, flips the delivered flag.
  Future<void> _handleAck(MeshPacket packet) async {
    final ackedPacketId = packet.data;
    if (ackedPacketId.isEmpty) return;
    final pending = _pendingSends.remove(ackedPacketId);
    if (pending?.messageId != null) {
      await _db.markDelivered(pending!.messageId!);
    }
    if (_pendingSends.isEmpty) {
      _retryTimer?.cancel();
      _retryTimer = null;
    }
  }

  // ===========================================================================
  // HANDLER: GAME (Phase 2 placeholder -> Implemented for TicTacToe)
  // ===========================================================================

  /// Routes incoming game packets to the correct game handler by gameType.
  Future<void> _handleGame(MeshPacket packet) async {
    try {
      final gm = GameMessage.fromJson(jsonDecode(packet.data));
      switch (gm.gameType) {
        case GameType.ticTacToe:
          await _handleTicTacToe(gm, packet.originId);
        case GameType.trivia:
          await _handleTrivia(gm, packet.originId);
          break;
      }
    } catch (e) {
      debugPrint('[AppController] _handleGame error: $e');
    }
  }

  /// Handles all Tic-Tac-Toe game messages.
  Future<void> _handleTicTacToe(GameMessage gm, String originId) async {
    final notifier = _ref.read(ticTacToeProvider.notifier);

    switch (gm.type) {
      case GameMessageType.invite:
        // Auto-decline (busy) only if a game is genuinely in progress — a
        // finished game (winner set) or one whose opponent disconnected must
        // not block a new invite (including a "Play Again" from the same
        // peer), or rematches/new challenges get silently declined forever.
        final tttState = _ref.read(ticTacToeProvider);
        if (tttState != null &&
            tttState.winner == null &&
            !tttState.opponentDisconnected) {
          await sendGameMessage(
            originId,
            GameMessage(
              gameId: gm.gameId,
              gameType: GameType.ticTacToe,
              type: GameMessageType.decline,
              payload: {'reason': 'busy'},
            ),
          );
          break;
        }
        _ref.read(pendingGameInviteProvider.notifier).state = PendingGameInvite(
          gameId: gm.gameId,
          gameType: GameType.ticTacToe,
          peerId: originId,
          peerName: await _getPeerName(originId),
        );
        break;
      case GameMessageType.accept:
        notifier.onInviteAccepted(
          gm.gameId,
          originId,
          await _getPeerName(originId),
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
      case GameMessageType.question:
      case GameMessageType.answer:
      case GameMessageType.result:
        break; // Not used by Tic-Tac-Toe.
    }
  }

  /// Handles all Cabin Trivia game messages.
  Future<void> _handleTrivia(GameMessage gm, String originId) async {
    final notifier = _ref.read(triviaGameProvider.notifier);

    switch (gm.type) {
      case GameMessageType.invite:
        // Auto-decline (busy) only if a trivia game is genuinely in progress
        // — a finished game must not block a new invite/rematch.
        final triviaState = _ref.read(triviaGameProvider);
        if (triviaState != null && triviaState.phase != TriviaPhase.finished) {
          await sendGameMessage(
            originId,
            GameMessage(
              gameId: gm.gameId,
              gameType: GameType.trivia,
              type: GameMessageType.decline,
              payload: {'reason': 'busy'},
            ),
          );
          break;
        }
        _ref.read(pendingGameInviteProvider.notifier).state = PendingGameInvite(
          gameId: gm.gameId,
          gameType: GameType.trivia,
          peerId: originId,
          peerName: await _getPeerName(originId),
        );
        break;

      case GameMessageType.accept:
        // HOST receives this — transition to answering and send first question.
        final firstQuestion = notifier.onAcceptReceived();
        if (firstQuestion != null) {
          // Strip the correct-answer index before it goes over the wire — the
          // opponent must not learn it until the result is revealed.
          final sanitized = Map<String, dynamic>.from(firstQuestion)
            ..remove('answer');
          await sendGameMessage(
            originId,
            GameMessage(
              gameId: gm.gameId,
              gameType: GameType.trivia,
              type: GameMessageType.question,
              payload: {
                'question': sanitized,
                'index': 0,
              },
            ),
          );
        }
        break;

      case GameMessageType.decline:
        notifier.reset();
        break;

      case GameMessageType.question:
        // OPPONENT receives this.
        final question = Map<String, dynamic>.from(
            gm.payload['question'] as Map<String, dynamic>);
        final index = gm.payload['index'] as int;
        notifier.onQuestionReceived(question, index);
        break;

      case GameMessageType.answer:
        // HOST receives opponent's answer. Try to score.
        final selectedIndex = gm.payload['selectedIndex'] as int;
        final resultPayload = notifier.onAnswerReceived(selectedIndex);
        if (resultPayload != null) {
          await sendGameMessage(
            originId,
            GameMessage(
              gameId: gm.gameId,
              gameType: GameType.trivia,
              type: GameMessageType.result,
              payload: resultPayload,
            ),
          );
        }
        break;

      case GameMessageType.result:
        // OPPONENT receives scored result from host.
        notifier.onResultReceived(
          correctIndex: gm.payload['correctIndex'] as int,
          hostScore: gm.payload['hostScore'] as int,
          opponentScore: gm.payload['opponentScore'] as int,
          hostAnswerIndex: gm.payload['hostAnswerIndex'] as int,
          opponentAnswerIndex: gm.payload['opponentAnswerIndex'] as int,
        );
        break;

      case GameMessageType.end:
        notifier.onGameEnded(
          hostScore: gm.payload['hostScore'] as int,
          opponentScore: gm.payload['opponentScore'] as int,
        );
        break;

      case GameMessageType.move:
        break; // Not used by Trivia.
    }
  }

  // ===========================================================================
  // RELIABLE DELIVERY (ARQ) — used for unicast wave/waveAccept/text
  // ===========================================================================

  /// Payload types that are delivered reliably (sender retransmits until ACKed,
  /// receiver ACKs every receipt). Broadcast/profileSync/photoChunk/game and the
  /// ack itself are excluded.
  static bool _isReliable(PayloadType t) =>
      t == PayloadType.wave ||
      t == PayloadType.waveAccept ||
      t == PayloadType.text;

  /// Sends [packet] and keeps retransmitting it (same packetId — the receiver
  /// dedups, so it is processed once but ACKed every time) until the
  /// destination acknowledges it or the attempt budget is exhausted.
  Future<void> _sendReliable(MeshPacket packet, {String? messageId}) async {
    _pendingSends[packet.packetId] = _PendingSend(
      packet,
      messageId,
      1,
      DateTime.now().millisecondsSinceEpoch + _retryBaseMs,
    );
    _retryTimer ??=
        Timer.periodic(const Duration(seconds: 1), (_) => _runRetries());
    await _mesh.sendPacket(packet);
  }

  Future<void> _runRetries() async {
    if (_isRetrying) return;
    _isRetrying = true;
    try {
      if (_pendingSends.isEmpty) {
        _retryTimer?.cancel();
        _retryTimer = null;
        return;
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final id in _pendingSends.keys.toList()) {
        final p = _pendingSends[id];
        if (p == null || now < p.nextRetryAtMs) continue;
        if (p.attempts >= _retryMaxAttempts) {
          _pendingSends.remove(id);
          debugPrint(
              'AppController: reliable ${p.packet.payloadType.name} ${id.substring(0, 8)} unacked after ${p.attempts} attempts — giving up');
          continue;
        }
        p.attempts++;
        p.nextRetryAtMs = now + _retryBaseMs * p.attempts;
        await _mesh.sendPacket(p.packet);
      }
    } finally {
      _isRetrying = false;
    }
  }

  /// Acknowledges receipt of [packetId] back to its origin (fire-and-forget;
  /// ACKs are not themselves ARQ'd — a lost ACK is recovered by the sender's
  /// next retransmit, which is ACKed again).
  Future<void> _sendAck(String packetId, String toId) async {
    await _mesh.sendPacket(MeshPacket(
      packetId: _uuid.v4(),
      originId: _localDeviceId,
      destinationId: toId,
      payloadType: PayloadType.ack,
      data: packetId,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    ));
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

    // Send wave packet (reliable — retransmitted until the peer ACKs).
    await _sendReliable(MeshPacket(
      packetId: _uuid.v4(),
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
    await _sendReliable(MeshPacket(
      packetId: _uuid.v4(),
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
    final sharedKey = await _getOrDeriveSharedKey(peerId, matchId);
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

    // Send over mesh (encrypted payload), reliably — retransmitted until the
    // peer ACKs, at which point the message is flagged delivered.
    await _sendReliable(
      MeshPacket(
        packetId: _uuid.v4(),
        originId: _localDeviceId,
        destinationId: peerId,
        payloadType: PayloadType.text,
        data: dataPayload,
        timestamp: message.timestamp,
      ),
      messageId: message.messageId,
    );
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

    // Fire match notification + in-app banner
    final peerName = await _getPeerName(peerId);
    await _notifications.showMatchNotification(peerName);
    _ref.read(incomingAlertProvider.notifier).state = RadarAlert(
      kind: RadarAlertKind.match,
      peerId: peerId,
      peerName: peerName,
      matchId: matchId,
    );

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

  /// Returns the shared key for [matchId], deriving it on demand from the
  /// peer's stored public key if it isn't already available. This self-heals
  /// the case where the in-memory key cache is cold after a restart (or secure
  /// storage failed to return a persisted key) — derivation is deterministic,
  /// so it reconstructs the identical key from the DB-persisted peer pubkey and
  /// our private key.
  Future<Uint8List?> _getOrDeriveSharedKey(String peerId, String matchId) async {
    var key = await _crypto.getSharedKey(matchId);
    if (key == null) {
      await _deriveAndStoreSharedKey(peerId, matchId);
      key = await _crypto.getSharedKey(matchId);
    }
    return key;
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
