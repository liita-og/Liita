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
  return AppController(
    db: ref.watch(databaseServiceProvider),
    mesh: ref.watch(meshServiceProvider),
    crypto: ref.watch(cryptoServiceProvider),
    notifications: ref.watch(notificationServiceProvider),
  );
});

// ---------------------------------------------------------------------------
// Local profile state
// ---------------------------------------------------------------------------

final localProfileProvider = StateProvider<UserProfile?>((ref) => null);

final onboardingCompleteProvider = StateProvider<bool>((ref) => false);

// ---------------------------------------------------------------------------
// Peers (live from mesh)
// ---------------------------------------------------------------------------

final peersProvider = StreamProvider<List<UserProfile>>((ref) {
  final mesh = ref.watch(meshServiceProvider);
  final peers = <String, UserProfile>{};

  return mesh.discoveredPeers.map((newPeer) {
    peers[newPeer.deviceId] = newPeer;
    return peers.values.toList();
  });
});

final activePeerCountProvider = StreamProvider<int>((ref) {
  return ref.watch(meshServiceProvider).activePeerCount;
});

// ---------------------------------------------------------------------------
// Matches
// ---------------------------------------------------------------------------

final matchesProvider = FutureProvider<List<String>>((ref) async {
  final localProfile = ref.watch(localProfileProvider);
  if (localProfile == null) return [];
  final db = ref.watch(databaseServiceProvider);
  return db.getMatches(localProfile.deviceId);
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
