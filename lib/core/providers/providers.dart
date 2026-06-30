import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liita/core/models/user_profile.dart';
import 'package:liita/core/models/chat_message.dart';
import 'package:liita/core/models/broadcast_message.dart';
import 'package:liita/core/controllers/app_controller.dart';
import 'package:liita/core/services/database_service.dart';
import 'package:liita/core/services/mesh_service.dart';
import 'package:liita/core/services/mesh_service_flutter.dart';
import 'package:liita/core/services/crypto_service.dart';
import 'package:liita/core/services/notification_service.dart';
import 'package:liita/core/services/storage_service.dart';

// ---------------------------------------------------------------------------
// Core service singletons
// ---------------------------------------------------------------------------

final databaseServiceProvider = Provider<DatabaseService>((ref) {
  return DatabaseService();
});

final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService.instance;
});

final meshServiceProvider = Provider<MeshService>((ref) {
  return FlutterMeshService();
});

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService();
});

final cryptoServiceProvider = Provider<CryptoService>((ref) {
  return CryptoServiceImpl();
});

final appControllerProvider = Provider<AppController>((ref) {
  final controller = AppController(
    db: ref.read(databaseServiceProvider),
    mesh: ref.read(meshServiceProvider),
    crypto: ref.read(cryptoServiceProvider),
    notifications: ref.read(notificationServiceProvider),
    ref: ref,
  );
  ref.onDispose(controller.dispose);
  return controller;
});

// ---------------------------------------------------------------------------
// Local profile state
// ---------------------------------------------------------------------------

final localProfileProvider = StateProvider<UserProfile?>((ref) => null);

final onboardingCompleteProvider = StateProvider<bool>((ref) => false);

// ---------------------------------------------------------------------------
// Peers (live from mesh)
// ---------------------------------------------------------------------------

/// Live (currently in-range) discovered peers. A peer is added/updated on
/// every profile push and removed when [MeshService.peerExpired] fires (no
/// scan/profile activity for the presence timeout — i.e. genuinely out of
/// range). Peers the local user has waved at are kept visible regardless via
/// [wavedPeerProfilesProvider], merged in by the radar screen — this provider
/// only reflects current reachability.
final peersProvider = StreamProvider<List<UserProfile>>((ref) {
  final mesh = ref.watch(meshServiceProvider);
  final peers = <String, UserProfile>{};
  final controller = StreamController<List<UserProfile>>();

  final addSub = mesh.discoveredPeers.listen((newPeer) {
    peers[newPeer.deviceId] = newPeer;
    if (!controller.isClosed) controller.add(peers.values.toList());
  });
  final expireSub = mesh.peerExpired.listen((deviceId) {
    if (peers.remove(deviceId) != null && !controller.isClosed) {
      controller.add(peers.values.toList());
    }
  });

  ref.onDispose(() {
    addSub.cancel();
    expireSub.cancel();
    controller.close();
  });

  return controller.stream;
});

final activePeerCountProvider = StreamProvider<int>((ref) {
  return ref.watch(meshServiceProvider).activePeerCount;
});

/// Profiles of peers the local user has waved at, loaded from the DB so their
/// radar card persists even after the peer goes offline or the app restarts.
/// Recomputes whenever [wavedAtProvider] changes.
final wavedPeerProfilesProvider = FutureProvider<List<UserProfile>>((ref) async {
  final wavedIds = ref.watch(wavedAtProvider);
  if (wavedIds.isEmpty) return const <UserProfile>[];
  final db = ref.watch(databaseServiceProvider);
  final profiles = <UserProfile>[];
  for (final id in wavedIds) {
    final p = await db.getProfile(id);
    if (p != null) profiles.add(p);
  }
  return profiles;
});

// ---------------------------------------------------------------------------
// Matches
// ---------------------------------------------------------------------------

final matchesProvider = StreamProvider<List<String>>((ref) {
  final localProfile = ref.watch(localProfileProvider);
  if (localProfile == null) return const Stream.empty();
  final db = ref.watch(databaseServiceProvider);
  return db.watchMatches(localProfile.deviceId);
});

final matchProfileProvider =
    FutureProvider.family<UserProfile?, String>((ref, deviceId) async {
  final db = ref.watch(databaseServiceProvider);
  return db.getProfile(deviceId);
});

// ---------------------------------------------------------------------------
// Messages
// ---------------------------------------------------------------------------

final messagesProvider =
    StreamProvider.family<List<ChatMessage>, String>((ref, matchId) {
  final db = ref.watch(databaseServiceProvider);
  return db.watchMessages(matchId);
});

final unreadCountProvider =
    FutureProvider.family<int, String>((ref, matchId) async {
  final db = ref.watch(databaseServiceProvider);
  return db.getUnreadCount(matchId);
});

final totalUnreadProvider = FutureProvider<int>((ref) async {
  final localProfile = ref.watch(localProfileProvider);
  if (localProfile == null) return 0;
  final db = ref.watch(databaseServiceProvider);
  return db.getTotalUnreadCount(localProfile.deviceId);
});

// ---------------------------------------------------------------------------
// Broadcast (Lounge)
// ---------------------------------------------------------------------------

final broadcastsProvider = StreamProvider<List<BroadcastMessage>>((ref) {
  final db = ref.watch(databaseServiceProvider);
  return db.watchBroadcasts();
});

// ---------------------------------------------------------------------------
// Wave tracking
// ---------------------------------------------------------------------------

/// Tracks deviceIds the local user has waved at (in-memory for UI state).
final wavedAtProvider = StateProvider<Set<String>>((ref) => {});

/// Tracks deviceIds that have waved at the local user.
final wavedByProvider = StateProvider<Set<String>>((ref) => {});

/// Tracks matched deviceIds (for celebration animation trigger).
final newMatchProvider = StateProvider<String?>((ref) => null);

// ---------------------------------------------------------------------------
// Navigation state
// ---------------------------------------------------------------------------

final selectedTabProvider = StateProvider<int>((ref) => 0);
