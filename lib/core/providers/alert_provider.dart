import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The kind of in-app alert to surface as a top banner.
enum RadarAlertKind { wave, match }

/// A transient in-app alert (someone waved / a new match) shown as a top banner
/// in addition to the system notification. Tapping it navigates: a wave → Radar,
/// a match → that peer's chat.
class RadarAlert {
  final RadarAlertKind kind;
  final String peerId;
  final String peerName;

  /// Set for matches — the derived chat id, used to open the conversation.
  final String? matchId;

  const RadarAlert({
    required this.kind,
    required this.peerId,
    required this.peerName,
    this.matchId,
  });
}

/// Holds the latest alert. [AppController] sets it on wave/match; the global
/// banner watches it and clears it back to null once shown/dismissed.
///
/// Lives in its own file (not providers.dart) so [AppController] can write to it
/// without creating an app_controller ↔ providers import cycle.
final incomingAlertProvider = StateProvider<RadarAlert?>((ref) => null);
