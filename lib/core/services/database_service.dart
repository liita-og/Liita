import 'dart:async';

import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
// ignore: depend_on_referenced_packages
import 'package:path/path.dart' as p;

import 'package:liita/core/models/user_profile.dart';
import 'package:liita/core/models/match_event.dart';
import 'package:liita/core/models/chat_message.dart';
import 'package:liita/core/models/broadcast_message.dart';
import 'package:liita/core/utils/constants.dart';

/// SQLite database service for all local persistence in the Liita BLE mesh app.
///
/// Provides CRUD for profiles, match events, encrypted messages, photo chunks,
/// packet deduplication, and broadcast messages. Exposes reactive [Stream]s for
/// chat messages and broadcasts via [StreamController]s that re-query on
/// every insert — no timer-based polling.
class DatabaseService {
  static const String _dbName = 'liita.db';
  static const int _dbVersion = 1;

  Database? _db;

  final Map<String, StreamController<List<ChatMessage>>> _messageControllers =
      {};
  StreamController<List<BroadcastMessage>>? _broadcastController;
  StreamController<List<String>>? _matchesController;

  /// Opens (or creates) the database and runs the schema migration.
  Future<void> initialize() async {
    if (_db != null && _db!.isOpen) return;

    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, _dbName);

    _db = await openDatabase(
      dbPath,
      version: _dbVersion,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    final batch = db.batch();

    batch.execute('''
      CREATE TABLE profiles (
        device_id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        age INTEGER NOT NULL,
        seat_number TEXT NOT NULL,
        occupation TEXT NOT NULL,
        photo_hash TEXT,
        version INTEGER NOT NULL DEFAULT 1,
        public_key TEXT NOT NULL,
        icebreaker_prompt TEXT NOT NULL DEFAULT '',
        icebreaker_answer TEXT NOT NULL DEFAULT '',
        last_seen INTEGER NOT NULL
      )
    ''');

    batch.execute('''
      CREATE TABLE match_events (
        event_id TEXT PRIMARY KEY,
        event_type TEXT NOT NULL,
        actor_id TEXT NOT NULL,
        target_id TEXT NOT NULL,
        timestamp INTEGER NOT NULL
      )
    ''');
    batch.execute('''
      CREATE INDEX idx_match_events_actors
        ON match_events(actor_id, target_id)
    ''');

    batch.execute('''
      CREATE TABLE messages (
        message_id TEXT PRIMARY KEY,
        match_id TEXT NOT NULL,
        from_id TEXT NOT NULL,
        to_id TEXT NOT NULL,
        ciphertext TEXT NOT NULL,
        nonce TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        delivered INTEGER NOT NULL DEFAULT 0,
        is_read INTEGER NOT NULL DEFAULT 0
      )
    ''');
    batch.execute('''
      CREATE INDEX idx_messages_match
        ON messages(match_id, timestamp)
    ''');

    batch.execute('''
      CREATE TABLE photo_chunks (
        photo_hash TEXT NOT NULL,
        chunk_index INTEGER NOT NULL,
        total_chunks INTEGER NOT NULL,
        data TEXT NOT NULL,
        received_at INTEGER NOT NULL,
        PRIMARY KEY (photo_hash, chunk_index)
      )
    ''');

    batch.execute('''
      CREATE TABLE packet_dedup (
        packet_id TEXT PRIMARY KEY,
        received_at INTEGER NOT NULL
      )
    ''');

    batch.execute('''
      CREATE TABLE broadcast_messages (
        message_id TEXT PRIMARY KEY,
        from_id TEXT NOT NULL,
        sender_name TEXT NOT NULL,
        seat_number TEXT NOT NULL,
        text TEXT NOT NULL,
        timestamp INTEGER NOT NULL
      )
    ''');
    batch.execute('''
      CREATE INDEX idx_broadcast_timestamp
        ON broadcast_messages(timestamp)
    ''');

    await batch.commit(noResult: true);
  }

  Database get _database {
    final db = _db;
    if (db == null || !db.isOpen) {
      throw StateError(
        'DatabaseService not initialised. Call initialize() first.',
      );
    }
    return db;
  }

  // ===========================================================================
  // PROFILES
  // ===========================================================================

  /// Insert or update a peer profile from BLE discovery.
  Future<void> upsertProfile(UserProfile profile) async {
    await _database.insert(
      'profiles',
      {
        'device_id': profile.deviceId,
        'name': profile.name,
        'age': profile.age,
        'seat_number': profile.seatNumber,
        'occupation': profile.occupation,
        'photo_hash': profile.photoHash,
        'version': profile.version,
        'public_key': profile.publicKey,
        'icebreaker_prompt': profile.icebreakerPrompt,
        'icebreaker_answer': profile.icebreakerAnswer,
        'last_seen': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get a single profile by device ID.
  Future<UserProfile?> getProfile(String deviceId) async {
    final rows = await _database.query(
      'profiles',
      where: 'device_id = ?',
      whereArgs: [deviceId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _profileFromRow(rows.first);
  }

  /// Get every stored profile.
  Future<List<UserProfile>> getAllProfiles() async {
    final rows = await _database.query('profiles', orderBy: 'last_seen DESC');
    return rows.map(_profileFromRow).toList();
  }

  /// Returns profiles whose `last_seen` is within [staleDurationMs] of now.
  Future<List<UserProfile>> getActivePeers({
    int staleDurationMs = 300000,
  }) async {
    final cutoff = DateTime.now().millisecondsSinceEpoch - staleDurationMs;
    final rows = await _database.query(
      'profiles',
      where: 'last_seen >= ?',
      whereArgs: [cutoff],
      orderBy: 'last_seen DESC',
    );
    return rows.map(_profileFromRow).toList();
  }

  /// Delete a profile by device ID.
  Future<void> deleteProfile(String deviceId) async {
    await _database.delete(
      'profiles',
      where: 'device_id = ?',
      whereArgs: [deviceId],
    );
  }

  UserProfile _profileFromRow(Map<String, dynamic> row) {
    return UserProfile(
      deviceId: row['device_id'] as String,
      name: row['name'] as String,
      age: row['age'] as int,
      seatNumber: row['seat_number'] as String,
      occupation: row['occupation'] as String,
      photoHash: row['photo_hash'] as String?,
      version: row['version'] as int? ?? 1,
      publicKey: row['public_key'] as String? ?? '',
      icebreakerPrompt: row['icebreaker_prompt'] as String? ?? '',
      icebreakerAnswer: row['icebreaker_answer'] as String? ?? '',
    );
  }

  // ===========================================================================
  // MATCH EVENTS
  // ===========================================================================

  /// Insert a match event (wave, block, report).
  Future<void> insertMatchEvent(MatchEvent event) async {
    await _database.insert(
      'match_events',
      event.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteMatchEvent({
    required MatchEventType eventType,
    required String actorId,
    required String targetId,
  }) async {
    await _database.delete(
      'match_events',
      where: 'event_type = ? AND actor_id = ? AND target_id = ?',
      whereArgs: [eventType.value, actorId, targetId],
    );
  }

  /// Returns `true` if [actorId] has sent a wave to [targetId].
  Future<bool> hasWaveSent(String actorId, String targetId) async {
    final rows = await _database.query(
      'match_events',
      where: 'actor_id = ? AND target_id = ? AND event_type = ?',
      whereArgs: [actorId, targetId, MatchEventType.waveSent.value],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Returns `true` if [fromId] has ever sent a wave **to** [toId].
  /// Used to detect the race-condition case where both devices wave at
  /// the same time: when A sends a wave to B, A checks whether B already
  /// waved at A (i.e. fromId = B, toId = A).
  ///
  /// Note: This method checks for `waveReceived` because from the perspective
  /// of the target device (`toId`), the event recorded is a wave received from the actor (`fromId`).
  Future<bool> hasWaveFrom(String fromId, String toId) async {
    // A waveReceived stored by [toId]'s device means [fromId] waved at [toId].
    // But on [fromId]'s device we look for the waveSent where the actor is
    // [fromId] and the target is [toId].
    final rows = await _database.query(
      'match_events',
      where: 'actor_id = ? AND target_id = ? AND event_type = ?',
      whereArgs: [fromId, toId, MatchEventType.waveReceived.value],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Returns device IDs of all confirmed matches (MATCH_CREATED events).
  Future<List<String>> getMatches(String localDeviceId) async {
    final matches = await _database.query(
      'match_events',
      columns: ['target_id'],
      where: 'actor_id = ? AND event_type = ?',
      whereArgs: [localDeviceId, MatchEventType.matchCreated.value],
    );

    final matched = <String>[];
    for (final row in matches) {
      final targetId = row['target_id'] as String;
      if (!await isBlocked(localDeviceId, targetId)) {
        matched.add(targetId);
      }
    }
    return matched;
  }

  /// Returns `true` if a MATCH_CREATED event exists between local and peer.
  Future<bool> hasMatchCreated(String localDeviceId, String peerId) async {
    final rows = await _database.query(
      'match_events',
      where: 'actor_id = ? AND target_id = ? AND event_type = ?',
      whereArgs: [localDeviceId, peerId, MatchEventType.matchCreated.value],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Returns `true` if either party has blocked the other.
  Future<bool> isBlocked(String deviceA, String deviceB) async {
    final rows = await _database.query(
      'match_events',
      where:
          '((actor_id = ? AND target_id = ?) OR (actor_id = ? AND target_id = ?)) '
          'AND event_type = ?',
      whereArgs: [
        deviceA, deviceB,
        deviceB, deviceA,
        MatchEventType.blocked.value,
      ],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  // ===========================================================================
  // MESSAGES
  // ===========================================================================

  /// Insert an encrypted chat message and notify stream listeners.
  Future<void> insertMessage(ChatMessage message) async {
    await _database.insert(
      'messages',
      message.toDbJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _notifyMessageListeners(message.matchId);
  }

  /// Get all messages for a match, ordered by timestamp.
  Future<List<ChatMessage>> getMessages(String matchId) async {
    final rows = await _database.query(
      'messages',
      where: 'match_id = ?',
      whereArgs: [matchId],
      orderBy: 'timestamp ASC',
    );
    return rows.map((r) => ChatMessage.fromDbJson(r)).toList();
  }

  /// Reactive stream of messages for a match.
  Stream<List<ChatMessage>> watchMessages(String matchId) {
    var controller = _messageControllers[matchId];
    if (controller == null || controller.isClosed) {
      controller = StreamController<List<ChatMessage>>.broadcast(
        onCancel: () {
          _messageControllers[matchId]?.close();
          _messageControllers.remove(matchId);
        },
      );
      _messageControllers[matchId] = controller;
    }
    getMessages(matchId).then((messages) {
      if (!controller!.isClosed) controller.add(messages);
    });
    return controller.stream;
  }

  Future<void> markDelivered(String messageId) async {
    await _database.update(
      'messages',
      {'delivered': 1},
      where: 'message_id = ?',
      whereArgs: [messageId],
    );
  }

  Future<void> markRead(String matchId) async {
    await _database.update(
      'messages',
      {'is_read': 1},
      where: 'match_id = ? AND is_read = 0',
      whereArgs: [matchId],
    );
    _notifyMessageListeners(matchId);
  }

  Future<int> getUnreadCount(String matchId) async {
    final result = await _database.rawQuery(
      'SELECT COUNT(*) AS cnt FROM messages WHERE match_id = ? AND is_read = 0',
      [matchId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> getTotalUnreadCount(String localDeviceId) async {
    final result = await _database.rawQuery(
      'SELECT COUNT(*) AS cnt FROM messages WHERE to_id = ? AND is_read = 0',
      [localDeviceId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  void _notifyMessageListeners(String matchId) {
    final controller = _messageControllers[matchId];
    if (controller != null && !controller.isClosed) {
      getMessages(matchId).then((messages) {
        if (!controller.isClosed) controller.add(messages);
      });
    }
  }

  // ===========================================================================
  // PHOTO CHUNKS
  // ===========================================================================

  Future<void> insertChunk(Map<String, dynamic> chunk) async {
    await _database.insert(
      'photo_chunks',
      chunk,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getChunks(String photoHash) async {
    return _database.query(
      'photo_chunks',
      where: 'photo_hash = ?',
      whereArgs: [photoHash],
      orderBy: 'chunk_index ASC',
    );
  }

  Future<void> deleteChunks(String photoHash) async {
    await _database.delete(
      'photo_chunks',
      where: 'photo_hash = ?',
      whereArgs: [photoHash],
    );
  }

  Future<void> pruneStaleChunks({int timeoutMs = 300000}) async {
    final cutoff = DateTime.now().millisecondsSinceEpoch - timeoutMs;
    await _database.delete(
      'photo_chunks',
      where: 'received_at < ?',
      whereArgs: [cutoff],
    );
  }

  // ===========================================================================
  // PACKET DEDUPLICATION
  // ===========================================================================

  Future<bool> isPacketSeen(String packetId) async {
    final rows = await _database.query(
      'packet_dedup',
      where: 'packet_id = ?',
      whereArgs: [packetId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> markPacketSeen(String packetId) async {
    await _database.insert(
      'packet_dedup',
      {
        'packet_id': packetId,
        'received_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Attempts to insert a packet ID into the dedup table.
  /// Returns `true` if the packet is new (was inserted), or `false` if it
  /// already existed.
  ///
  /// Note: SQLite's `INSERT OR IGNORE` returns the number of rows inserted.
  /// Therefore, `count > 0` correctly evaluates to true only for new packets.
  Future<bool> markPacketSeenIfNew(String packetId) async {
    final count = await _database.rawInsert(
      'INSERT OR IGNORE INTO packet_dedup (packet_id, received_at) VALUES (?, ?)',
      [packetId, DateTime.now().millisecondsSinceEpoch],
    );
    return count > 0;
  }

  Future<void> pruneDedup({int maxAgeMs = 600000}) async {
    final cutoff = DateTime.now().millisecondsSinceEpoch - maxAgeMs;
    await _database.delete(
      'packet_dedup',
      where: 'received_at < ?',
      whereArgs: [cutoff],
    );
  }

  // ===========================================================================
  // BROADCAST MESSAGES
  // ===========================================================================

  Future<void> insertBroadcast(BroadcastMessage message) async {
    await _database.insert(
      'broadcast_messages',
      message.toDbJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _notifyBroadcastListeners();
  }

  Future<List<BroadcastMessage>> getBroadcasts(int limit) async {
    final rows = await _database.query(
      'broadcast_messages',
      orderBy: 'timestamp ASC',
      limit: limit,
    );
    return rows.map((r) => BroadcastMessage.fromDbJson(r)).toList();
  }

  Stream<List<BroadcastMessage>> watchBroadcasts() {
    if (_broadcastController == null || _broadcastController!.isClosed) {
      _broadcastController = StreamController<List<BroadcastMessage>>.broadcast(
        onCancel: () {
          _broadcastController?.close();
          _broadcastController = null;
        },
      );
    }
    getBroadcasts(AppConstants.kBroadcastQueryLimit).then((messages) {
      if (_broadcastController != null && !_broadcastController!.isClosed) {
        _broadcastController!.add(messages);
      }
    });
    return _broadcastController!.stream;
  }

  void _notifyBroadcastListeners() {
    if (_broadcastController != null && !_broadcastController!.isClosed) {
      getBroadcasts(AppConstants.kBroadcastQueryLimit).then((messages) {
        if (_broadcastController != null && !_broadcastController!.isClosed) {
          _broadcastController!.add(messages);
        }
      });
    }
  }

  // ===========================================================================
  // MATCHES STREAM
  // ===========================================================================

  /// Reactive stream of matched peer device IDs.
  /// Emits the full current list whenever [notifyMatchesChanged] is called.
  Stream<List<String>> watchMatches(String localDeviceId) {
    if (_matchesController == null || _matchesController!.isClosed) {
      _matchesController = StreamController<List<String>>.broadcast(
        onCancel: () {
          _matchesController?.close();
          _matchesController = null;
        },
      );
    }
    // Emit initial value immediately.
    getMatches(localDeviceId).then((ids) {
      if (_matchesController != null && !_matchesController!.isClosed) {
        _matchesController!.add(ids);
      }
    });
    return _matchesController!.stream;
  }

  /// Call after inserting a matchCreated event to push updated list to listeners.
  void notifyMatchesChanged(String localDeviceId) {
    if (_matchesController != null && !_matchesController!.isClosed) {
      getMatches(localDeviceId).then((ids) {
        if (_matchesController != null && !_matchesController!.isClosed) {
          _matchesController!.add(ids);
        }
      });
    }
  }

  // ===========================================================================
  // LIFECYCLE
  // ===========================================================================

  Future<void> close() async {
    for (final controller in _messageControllers.values) {
      if (!controller.isClosed) await controller.close();
    }
    _messageControllers.clear();
    if (_broadcastController != null && !_broadcastController!.isClosed) {
      await _broadcastController!.close();
      _broadcastController = null;
    }
    if (_matchesController != null && !_matchesController!.isClosed) {
      await _matchesController!.close();
      _matchesController = null;
    }
    await _db?.close();
    _db = null;
  }
}
