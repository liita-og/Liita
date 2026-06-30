import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:liita/core/models/mesh_packet.dart';
import 'package:liita/core/models/user_profile.dart';
import 'package:liita/core/services/mesh_service.dart';

/// Real [MeshService] implementation that bridges to native BLE mesh code
/// via Flutter platform channels.
///
/// Uses a [MethodChannel] for request/response calls (start, stop, send) and
/// two [EventChannel]s for continuous streams (peer discovery, incoming
/// packets). The native side is expected to handle the actual BLE advertising,
/// scanning, GATT server/client, and mesh routing.
class FlutterMeshService implements MeshService {
  FlutterMeshService();

  // ---------------------------------------------------------------------------
  // Platform channels
  // ---------------------------------------------------------------------------

  static const _methodChannel = MethodChannel('com.liita.app/mesh');
  static const _peersEventChannel = EventChannel('com.liita.app/peers');
  static const _packetsEventChannel = EventChannel('com.liita.app/packets');
  static const _presenceEventChannel = EventChannel('com.liita.app/presence');

  /// How long a peer can go unseen (no scan hit, no profile re-read) before
  /// being considered out of range and expired from the live peer list.
  static const _presenceTimeout = Duration(seconds: 30);
  static const _presenceSweepInterval = Duration(seconds: 5);

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  bool _isRunning = false;

  final _discoveredDeviceIds = <String>{};

  final _peerCountController = StreamController<int>.broadcast();

  StreamSubscription<UserProfile>? _peerCountSubscription;

  // Lazily initialised broadcast stream from the packets event channel.
  Stream<MeshPacket>? _packetsStream;

  // Peer discovery hub. Every peer ever discovered is accumulated in
  // [_knownPeers] and re-broadcast through [_peersHub]. This is what makes the
  // radar populate reliably: the discovery EventChannel is a broadcast stream
  // that does NOT replay past events, and startMesh() attaches an internal
  // peer-count listener immediately — so a peer discovered before the radar
  // screen subscribes (e.g. during the splash screen) would otherwise be lost.
  // By replaying [_knownPeers] to every new subscriber, timing stops mattering.
  final Map<String, UserProfile> _knownPeers = {};
  StreamController<UserProfile>? _peersHub;

  // ---------------------------------------------------------------------------
  // Presence / out-of-range expiry
  // ---------------------------------------------------------------------------
  //
  // A peer is "seen" either via a full profile push (discoveredPeers) or a
  // lightweight presence heartbeat from native scan hits (no GATT connect — see
  // MeshForegroundService.onPeerSeen). A periodic sweep expires anyone not seen
  // within _presenceTimeout, so peers that genuinely went out of range disappear
  // from the live list — while peers still in range keep refreshing their
  // last-seen time via the heartbeat and never expire.
  final Map<String, DateTime> _lastSeenAt = {};
  StreamSubscription<dynamic>? _presenceSub;
  Timer? _presenceSweepTimer;
  final _expiredController = StreamController<String>.broadcast();

  // ---------------------------------------------------------------------------
  // MeshService interface
  // ---------------------------------------------------------------------------

  @override
  bool get isRunning => _isRunning;

  @override
  Stream<UserProfile> get discoveredPeers {
    // Start the single underlying EventChannel subscription once, feeding the
    // hub and accumulating every peer seen.
    if (_peersHub == null) {
      _peersHub = StreamController<UserProfile>.broadcast();
      _peersEventChannel.receiveBroadcastStream().listen(
        (dynamic event) {
          try {
            final peer = UserProfile.fromJson(_decodeEvent(event));
            _knownPeers[peer.deviceId] = peer;
            _lastSeenAt[peer.deviceId] = DateTime.now();
            if (!_peersHub!.isClosed) _peersHub!.add(peer);
          } catch (e, st) {
            debugPrint('FlutterMeshService: peer parse error (dropped): $e\n$st');
          }
        },
        onError: (Object e, StackTrace st) {
          debugPrint('FlutterMeshService: discoveredPeers stream error: $e');
        },
      );
    }

    // Each subscriber first receives the peers already known (replay), then all
    // live updates. This is the key to reliable discovery for late subscribers.
    return Stream<UserProfile>.multi((controller) {
      for (final peer in _knownPeers.values) {
        controller.add(peer);
      }
      final sub = _peersHub!.stream.listen(
        controller.add,
        onError: controller.addError,
      );
      controller.onCancel = sub.cancel;
    });
  }

  @override
  Stream<MeshPacket> get incomingPackets {
    _packetsStream ??= _packetsEventChannel
        .receiveBroadcastStream()
        .where((dynamic event) => event != null)
        .map<MeshPacket?>((dynamic event) {
          // RC-7: Catch parse errors per-packet; return null rather than
          // throwing into the stream (which terminates broadcast subscriptions).
          try {
            final json = _decodeEvent(event);
            return MeshPacket.fromJson(json);
          } catch (e, st) {
            debugPrint('FlutterMeshService: packet parse error (packet dropped): $e\n$st');
            return null;
          }
        })
        .where((packet) => packet != null)
        .cast<MeshPacket>()
        .asBroadcastStream();
    return _packetsStream!;
  }

  @override
  Stream<int> get activePeerCount => _peerCountController.stream;

  @override
  Stream<String> get peerExpired => _expiredController.stream;

  @override
  Future<void> startMesh(UserProfile localProfile) async {
    if (_isRunning) return;

    // RC-8 + presence-of-real-success fix: the native side can legitimately
    // no-op a startMesh call (Bluetooth not yet enabled, e.g. right after
    // app launch before the radio finishes powering on). It always used to
    // ack the platform-channel call regardless, which made _isRunning = true
    // even though nothing actually started — silently defeating the
    // adapterState "on" self-heal retry in home_shell.dart for the rest of
    // the session. Now the native call reports real success/failure, and
    // _isRunning only flips true when the engine actually started, so a
    // later retry (once Bluetooth is confirmed on) can succeed.
    try {
      final started = await _methodChannel.invokeMethod<bool>(
        'startMesh',
        {'profileJson': jsonEncode(localProfile.toJson())},
      );
      _isRunning = started ?? false;
      if (!_isRunning) {
        debugPrint('FlutterMeshService.startMesh: native did not actually start '
            '(Bluetooth off or permissions missing) — caller should retry once ready');
        return;
      }
    } catch (e, st) {
      debugPrint('FlutterMeshService.startMesh failed: $e\n$st');
      _isRunning = false;
      rethrow;   // Surface the error to the caller (Riverpod provider / UI)
    }

    _discoveredDeviceIds.clear();

    // Track unique device IDs and emit updated peer counts.
    _peerCountSubscription = discoveredPeers.listen((profile) {
      if (_discoveredDeviceIds.add(profile.deviceId)) {
        _peerCountController.add(_discoveredDeviceIds.length);
      }
    });

    // Presence heartbeat from native scan hits — refresh last-seen without a
    // GATT reconnect, so peers still in range never expire.
    _presenceSub = _presenceEventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        final deviceId = event is String ? event : event?.toString();
        if (deviceId != null && deviceId.isNotEmpty) {
          _lastSeenAt[deviceId] = DateTime.now();
        }
      },
      onError: (Object e, StackTrace st) {
        debugPrint('FlutterMeshService: presence stream error: $e');
      },
    );

    // Periodic sweep: anyone unseen (no profile push, no heartbeat) for longer
    // than the presence timeout is out of range — remove and notify.
    _presenceSweepTimer?.cancel();
    _presenceSweepTimer = Timer.periodic(_presenceSweepInterval, (_) {
      final now = DateTime.now();
      final expired = _knownPeers.keys.where((id) {
        final lastSeen = _lastSeenAt[id];
        return lastSeen == null || now.difference(lastSeen) > _presenceTimeout;
      }).toList();
      for (final id in expired) {
        _knownPeers.remove(id);
        _lastSeenAt.remove(id);
        if (!_expiredController.isClosed) _expiredController.add(id);
      }
    });
  }

  @override
  Future<void> stopMesh() async {
    if (!_isRunning) return;

    await _methodChannel.invokeMethod<void>('stopMesh');
    _isRunning = false;

    await _peerCountSubscription?.cancel();
    _peerCountSubscription = null;
    _discoveredDeviceIds.clear();
    _peerCountController.add(0);

    await _presenceSub?.cancel();
    _presenceSub = null;
    _presenceSweepTimer?.cancel();
    _presenceSweepTimer = null;
    _lastSeenAt.clear();
  }

  @override
  Future<void> sendPacket(MeshPacket packet) async {
    if (!_isRunning) {
      // RC-8: Log the silent drop so bind races are diagnosable.
      debugPrint('FlutterMeshService.sendPacket: dropped — mesh not running (service bind may not have completed)');
      return;
    }

    await _methodChannel.invokeMethod<void>(
      'sendPacket',
      {'packetJson': jsonEncode(packet.toJson())},
    );
  }

  @override
  Future<void> setForegroundMode() async {
    if (!_isRunning) return;
    await _methodChannel.invokeMethod<void>('setForegroundMode');
  }

  @override
  Future<void> setBackgroundMode() async {
    if (!_isRunning) return;
    await _methodChannel.invokeMethod<void>('setBackgroundMode');
  }

  @override
  Future<void> setContinuousMode() async {
    if (!_isRunning) return;
    await _methodChannel.invokeMethod<void>('setContinuousMode');
  }

  // ---------------------------------------------------------------------------
  // Cleanup
  // ---------------------------------------------------------------------------

  /// Call when the service is permanently disposed.
  void dispose() {
    stopMesh();
    _peerCountController.close();
    _expiredController.close();
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Decodes a platform channel event into a JSON map.
  ///
  /// The native side may send either a [Map] (automatically decoded by
  /// Flutter's standard method codec) or a JSON [String].
  static Map<String, dynamic> _decodeEvent(dynamic event) {
    if (event is Map) {
      return Map<String, dynamic>.from(event);
    }
    if (event is String) {
      return jsonDecode(event) as Map<String, dynamic>;
    }
    throw FormatException(
      'Unexpected event type from platform channel: ${event.runtimeType}',
    );
  }
}
