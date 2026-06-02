import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:liita/core/models/mesh_packet.dart';
import 'package:liita/core/models/user_profile.dart';
import 'package:liita/core/services/mesh_service.dart';
import 'package:uuid/uuid.dart';

/// Duty-cycle scan modes.
enum _ScanMode { foreground, background, continuous }

/// Mock implementation of [MeshService] for emulator and UI testing.
///
/// Simulates realistic peer discovery, incoming waves, and chat auto-replies
/// so the app feels alive without real BLE hardware. Generates 5-8 fake peers
/// that appear gradually over 10-20 seconds, then triggers spontaneous waves
/// and responds to outgoing packets with appropriate delays.
///
/// ## Duty-cycle behaviour
/// - [_ScanMode.foreground]: 5 s scan window / 10 s pause
/// - [_ScanMode.background]: 3 s scan window / 20 s pause
/// - [_ScanMode.continuous]: always scanning (no pause)
///
/// During a paused window, peer emission and packet delivery are suppressed
/// but the underlying peer list and timers remain intact so no data is lost.
class MockMeshService implements MeshService {
  MockMeshService();

  // ---------------------------------------------------------------------------
  // Bot data
  // ---------------------------------------------------------------------------

  static const _names = [
    'Aisha', 'Marcus', 'Yuki', 'Sofia', 'Raj', 'Emma', 'Diego', 'Priya',
    'Liam', 'Mei', 'Omar', 'Sarah', 'Jin', 'Aaliya', 'Noah', 'Luna',
    'Kai', 'Zara', 'Ethan', 'Mia',
  ];

  static const _occupations = [
    'Software Engineer', 'Designer', 'Teacher', 'Doctor', 'Photographer',
    'Writer', 'Student', 'Entrepreneur', 'Chef', 'Musician',
  ];

  static const _seatLetters = ['A', 'B', 'C', 'D', 'E', 'F'];

  static const _icebreakerData = <List<String>>[
    ["What's your go-to travel snack?", 'Dark chocolate always', 'Trail mix forever'],
    ['Window or aisle, and why?', 'Window - I love the views', 'Aisle - easy escape'],
    ["Best city you've ever visited?", 'Tokyo blew my mind', 'Barcelona vibes'],
    ['What are you binge-watching?', 'The Bear, so good', 'Still on Severance'],
    ['If this flight had a theme song?', 'Come Fly With Me', 'Fly Me to the Moon'],
    ['One thing on your bucket list?', 'Northern Lights', 'Scuba in Maldives'],
    ['Coffee or tea at 30,000 feet?', 'Coffee, black', 'Green tea always'],
    ["What's your hidden talent?", 'I can juggle', 'Origami master'],
    ['If you could teleport anywhere?', 'A beach in Bali', 'Paris cafe'],
    ['Describe your vibe in 3 words', 'Curious, chill, bold', 'Adventurous, warm, witty'],
  ];

  static const _autoReplies = [
    'Hey! Nice to connect',
    'This flight is going to be fun!',
    'Where are you headed?',
    'Have you tried the snacks yet?',
    'Love your icebreaker answer!',
    'Small world! Great to meet you',
    'Any good movie recommendations?',
    'First time on this route?',
  ];

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  final _random = Random();
  final _uuid = const Uuid();

  bool _isRunning = false;
  UserProfile? _localProfile;

  final _peerController = StreamController<UserProfile>.broadcast();
  final _packetController = StreamController<MeshPacket>.broadcast();
  final _peerCountController = StreamController<int>.broadcast();

  final _discoveredPeerIds = <String>{};
  final _discoveredProfiles = <String, UserProfile>{};
  final _activeTimers = <Timer>[];

  // ---------------------------------------------------------------------------
  // Duty-cycle state
  // ---------------------------------------------------------------------------

  _ScanMode _scanMode = _ScanMode.foreground;

  /// True when the duty-cycle is in its "active scan" window.
  /// Always true in [_ScanMode.continuous].
  bool _scanWindowActive = true;

  Timer? _dutyCycleTimer;

  /// Foreground: 5 s on, 10 s off.
  static const _fgScanOn = Duration(seconds: 5);
  static const _fgScanOff = Duration(seconds: 10);

  /// Background: 3 s on, 20 s off.
  static const _bgScanOn = Duration(seconds: 3);
  static const _bgScanOff = Duration(seconds: 20);

  // ---------------------------------------------------------------------------
  // MeshService interface
  // ---------------------------------------------------------------------------

  @override
  bool get isRunning => _isRunning;

  @override
  Stream<UserProfile> get discoveredPeers => _peerController.stream;

  @override
  Stream<MeshPacket> get incomingPackets => _packetController.stream;

  @override
  Stream<int> get activePeerCount => _peerCountController.stream;

  @override
  Future<void> startMesh(UserProfile localProfile) async {
    debugPrint('[MockMesh] startMesh called, _isRunning=$_isRunning');
    if (_isRunning) {
      debugPrint('[MockMesh] Already running, returning early');
      return;
    }

    _localProfile = localProfile;
    _isRunning = true;

    // Start foreground duty-cycle by default
    _applyDutyCycle();

    final peerCount = 5 + _random.nextInt(4);
    final shuffledNames = List<String>.from(_names)..shuffle(_random);
    final selectedNames = shuffledNames.take(peerCount).toList();

    debugPrint('[MockMesh] Will spawn $peerCount peers: $selectedNames');

    var cumulativeDelay = Duration.zero;
    for (var i = 0; i < selectedNames.length; i++) {
      final name = selectedNames[i];
      final delayMs = 2000 + _random.nextInt(2001);
      cumulativeDelay += Duration(milliseconds: delayMs);

      final capturedDelay = cumulativeDelay;
      final timer = Timer(capturedDelay, () {
        if (!_isRunning) return;

        final profile = _generateProfile(name, localProfile.seatNumber);
        _discoveredPeerIds.add(profile.deviceId);
        _discoveredProfiles[profile.deviceId] = profile;

        debugPrint('[MockMesh] Emitting peer: ${profile.name} '
            '(seat ${profile.seatNumber}) after ${capturedDelay.inMilliseconds}ms');

        // Only emit if in active scan window — suppressed during pauses
        if (_scanWindowActive && !_peerController.isClosed) {
          _peerController.add(profile);
        }
        if (_scanWindowActive && !_peerCountController.isClosed) {
          _peerCountController.add(_discoveredPeerIds.length);
        }
      });
      _activeTimers.add(timer);
    }

    // Schedule spontaneous waves after all peers have appeared
    final spontaneousWaveDelay =
        cumulativeDelay + Duration(seconds: 15 + _random.nextInt(16));

    final waveTimer = Timer(spontaneousWaveDelay, () {
      if (!_isRunning) return;
      _simulateSpontaneousWaves();
    });
    _activeTimers.add(waveTimer);

    debugPrint('[MockMesh] Setup complete, ${_activeTimers.length} timers queued');
  }

  @override
  Future<void> stopMesh() async {
    debugPrint('[MockMesh] stopMesh called');
    _isRunning = false;
    _dutyCycleTimer?.cancel();
    _dutyCycleTimer = null;
    for (final timer in _activeTimers) {
      timer.cancel();
    }
    _activeTimers.clear();
    _discoveredPeerIds.clear();
    _discoveredProfiles.clear();
    _localProfile = null;
    _scanWindowActive = true;
    if (!_peerCountController.isClosed) {
      _peerCountController.add(0);
    }
  }

  @override
  Future<void> sendPacket(MeshPacket packet) async {
    if (!_isRunning) return;

    switch (packet.payloadType) {
      case PayloadType.wave:
        _handleOutgoingWave(packet);
      case PayloadType.text:
        _handleOutgoingText(packet);
      case PayloadType.broadcast:
        _handleOutgoingBroadcast(packet);
      default:
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // Duty-cycle control (MeshService interface)
  // ---------------------------------------------------------------------------

  @override
  Future<void> setForegroundMode() async {
    if (_scanMode == _ScanMode.foreground) return;
    debugPrint('[MockMesh] setForegroundMode: 5s on / 10s off');
    _scanMode = _ScanMode.foreground;
    _restartDutyCycle();
  }

  @override
  Future<void> setBackgroundMode() async {
    if (_scanMode == _ScanMode.background) return;
    debugPrint('[MockMesh] setBackgroundMode: 3s on / 20s off');
    _scanMode = _ScanMode.background;
    _restartDutyCycle();
  }

  @override
  Future<void> setContinuousMode() async {
    if (_scanMode == _ScanMode.continuous) return;
    debugPrint('[MockMesh] setContinuousMode: always on');
    _scanMode = _ScanMode.continuous;
    _dutyCycleTimer?.cancel();
    _dutyCycleTimer = null;
    _scanWindowActive = true;
  }

  // ---------------------------------------------------------------------------
  // Duty-cycle internals
  // ---------------------------------------------------------------------------

  void _restartDutyCycle() {
    _dutyCycleTimer?.cancel();
    _dutyCycleTimer = null;
    if (_isRunning) _applyDutyCycle();
  }

  /// Starts the duty-cycle state machine for the current [_scanMode].
  /// Cycles: active scan window → pause window → active scan window → …
  void _applyDutyCycle() {
    if (_scanMode == _ScanMode.continuous) {
      _scanWindowActive = true;
      return;
    }

    _enterScanOn();
  }

  void _enterScanOn() {
    _scanWindowActive = true;
    final onDuration = _scanMode == _ScanMode.foreground ? _fgScanOn : _bgScanOn;
    debugPrint('[MockMesh] Duty-cycle: scan ON for ${onDuration.inSeconds}s');
    _dutyCycleTimer = Timer(onDuration, _enterScanOff);
  }

  void _enterScanOff() {
    _scanWindowActive = false;
    final offDuration = _scanMode == _ScanMode.foreground ? _fgScanOff : _bgScanOff;
    debugPrint('[MockMesh] Duty-cycle: scan OFF for ${offDuration.inSeconds}s');
    _dutyCycleTimer = Timer(offDuration, () {
      if (_isRunning) _enterScanOn();
    });
  }

  // ---------------------------------------------------------------------------
  // Profile generation
  // ---------------------------------------------------------------------------

  UserProfile _generateProfile(String name, String localSeat) {
    final localRow = _parseSeatRow(localSeat);
    final rowOffset = _random.nextInt(31) - 15;
    final seatRow = (localRow + rowOffset).clamp(1, 40);
    final seatLetter = _seatLetters[_random.nextInt(_seatLetters.length)];
    final icebreaker = _icebreakerData[_random.nextInt(_icebreakerData.length)];

    return UserProfile(
      deviceId: _uuid.v4(),
      name: name,
      age: 22 + _random.nextInt(34),
      seatNumber: '$seatRow$seatLetter',
      occupation: _occupations[_random.nextInt(_occupations.length)],
      icebreakerPrompt: icebreaker[0],
      icebreakerAnswer: icebreaker[1 + _random.nextInt(icebreaker.length - 1)],
    );
  }

  int _parseSeatRow(String seat) {
    final digits = seat.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(digits) ?? 20;
  }

  // ---------------------------------------------------------------------------
  // Packet simulation
  // ---------------------------------------------------------------------------

  void _simulateSpontaneousWaves() {
    if (_discoveredProfiles.isEmpty || _localProfile == null) return;

    final peerIds = _discoveredProfiles.keys.toList()..shuffle(_random);
    final waveCount = 1 + _random.nextInt(2);

    for (var i = 0; i < waveCount && i < peerIds.length; i++) {
      final delayMs = _random.nextInt(5000);
      final peerId = peerIds[i];
      final timer = Timer(Duration(milliseconds: delayMs), () {
        if (!_isRunning || _packetController.isClosed) return;
        if (!_scanWindowActive) return; // suppressed during duty-cycle pause
        debugPrint('[MockMesh] Spontaneous wave from ${_discoveredProfiles[peerId]?.name}');
        _packetController.add(MeshPacket(
          packetId: _uuid.v4(),
          originId: peerId,
          destinationId: _localProfile!.deviceId,
          payloadType: PayloadType.wave,
          data: '',
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ));
      });
      _activeTimers.add(timer);
    }
  }

  void _handleOutgoingWave(MeshPacket packet) {
    debugPrint('[MockMesh] Outgoing wave to ${packet.destinationId}');
    final acceptDelayMs = 1000 + _random.nextInt(1001);
    final acceptTimer = Timer(Duration(milliseconds: acceptDelayMs), () {
      if (!_isRunning || _packetController.isClosed) return;
      debugPrint('[MockMesh] Bot sending waveAccept back');

      _packetController.add(MeshPacket(
        packetId: _uuid.v4(),
        originId: packet.destinationId,
        destinationId: packet.originId,
        payloadType: PayloadType.waveAccept,
        data: '',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ));

      // Mutual wave so AppController detects a match
      final waveBackTimer = Timer(const Duration(milliseconds: 300), () {
        if (!_isRunning || _packetController.isClosed) return;
        debugPrint('[MockMesh] Bot sending wave back (mutual)');
        _packetController.add(MeshPacket(
          packetId: _uuid.v4(),
          originId: packet.destinationId,
          destinationId: packet.originId,
          payloadType: PayloadType.wave,
          data: '',
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ));
      });
      _activeTimers.add(waveBackTimer);

      // Bot sends greeting after match
      final greetDelayMs = 2000 + _random.nextInt(1001);
      final greetTimer = Timer(Duration(milliseconds: greetDelayMs), () {
        if (!_isRunning || _packetController.isClosed) return;
        const greetings = [
          'Hey! Nice to meet you',
          'Hi there! Where are you headed?',
          'Hey! This flight just got interesting',
          'Hello! Love your icebreaker answer!',
          'Hi! First time on this route?',
        ];
        final greeting = greetings[_random.nextInt(greetings.length)];
        debugPrint('[MockMesh] Bot sending greeting: $greeting');
        _packetController.add(MeshPacket(
          packetId: _uuid.v4(),
          originId: packet.destinationId,
          destinationId: packet.originId,
          payloadType: PayloadType.text,
          data: greeting,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ));
      });
      _activeTimers.add(greetTimer);
    });
    _activeTimers.add(acceptTimer);
  }

  void _handleOutgoingText(MeshPacket packet) {
    final delayMs = 1500 + _random.nextInt(2001);
    final timer = Timer(Duration(milliseconds: delayMs), () {
      if (!_isRunning || _packetController.isClosed) return;
      final reply = _autoReplies[_random.nextInt(_autoReplies.length)];
      _packetController.add(MeshPacket(
        packetId: _uuid.v4(),
        originId: packet.destinationId,
        destinationId: packet.originId,
        payloadType: PayloadType.text,
        data: reply,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ));
    });
    _activeTimers.add(timer);
  }

  void _handleOutgoingBroadcast(MeshPacket packet) {
    if (!_packetController.isClosed) {
      _packetController.add(packet);
    }
  }

  void dispose() {
    stopMesh();
    _peerController.close();
    _packetController.close();
    _peerCountController.close();
  }
}
