import 'package:liita/core/models/mesh_packet.dart';
import 'package:liita/core/models/user_profile.dart';

/// Abstract interface for the Liita BLE mesh networking layer.
///
/// Implementations handle peer discovery, packet routing, and lifecycle
/// management. Use [MockMeshService] for emulator/testing environments and
/// [FlutterMeshService] for real BLE hardware via platform channels.
abstract class MeshService {
  /// Starts the mesh network, advertising [localProfile] to nearby peers
  /// and beginning the discovery process.
  Future<void> startMesh(UserProfile localProfile);

  /// Stops the mesh network, tearing down all connections and timers.
  Future<void> stopMesh();

  /// Stream of peer profiles discovered on the mesh.
  ///
  /// Emits a [UserProfile] each time a new peer is found. Consumers should
  /// maintain their own set if deduplication is needed.
  Stream<UserProfile> get discoveredPeers;

  /// Stream of incoming packets (waves, messages, broadcasts) from peers.
  Stream<MeshPacket> get incomingPackets;

  /// Sends a [packet] over the mesh to the designated receiver.
  Future<void> sendPacket(MeshPacket packet);

  /// Whether the mesh is currently running.
  bool get isRunning;

  /// Stream that emits the current number of active (discovered) peers
  /// whenever the count changes.
  Stream<int> get activePeerCount;

  // ---------------------------------------------------------------------------
  // Duty-cycle control
  // ---------------------------------------------------------------------------

  /// Switch to foreground duty cycle: scan for 5 s, pause for 10 s, repeat.
  ///
  /// Call this when the app returns to the foreground from background.
  Future<void> setForegroundMode();

  /// Switch to background duty cycle: scan for 3 s, pause for 20 s, repeat.
  ///
  /// Call this when the app moves to [AppLifecycleState.paused] or
  /// [AppLifecycleState.hidden].
  Future<void> setBackgroundMode();

  /// Override to continuous scanning — no duty-cycling pauses.
  ///
  /// Call this when a chat conversation is actively open so messages
  /// are received in real time.
  Future<void> setContinuousMode();
}
