import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Service for displaying local notifications and triggering haptic feedback
/// when mesh events occur (waves, matches, messages).
///
/// Uses [flutter_local_notifications] for the notification UI and
/// [HapticFeedback] for tactile cues so users feel each interaction.
class NotificationService {
  NotificationService();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  // ---------------------------------------------------------------------------
  // Notification channel constants
  // ---------------------------------------------------------------------------

  static const _channelId = 'liita_notifications';
  static const _channelName = 'Liita';
  static const _channelDescription = 'Liita mesh networking notifications';

  // ---------------------------------------------------------------------------
  // Notification IDs (auto-increment to avoid replacing previous notifications)
  // ---------------------------------------------------------------------------

  int _nextId = 0;
  int get _id => _nextId++;

  // ---------------------------------------------------------------------------
  // Initialization
  // ---------------------------------------------------------------------------

  /// Sets up notification channels for both Android and iOS.
  ///
  /// Must be called once at app startup before showing any notifications.
  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    await _plugin.initialize(initSettings);
    _initialized = true;
  }

  // ---------------------------------------------------------------------------
  // Notification methods
  // ---------------------------------------------------------------------------

  /// Shows a notification when someone waves at the local user.
  ///
  /// Triggers a **light** haptic tap.
  Future<void> showWaveNotification(String senderName) async {
    HapticFeedback.lightImpact();

    await _showNotification(
      title: 'Someone waved at you!',
      body: '$senderName wants to connect',
    );
  }

  /// Shows a notification when a mutual wave creates a match.
  ///
  /// Triggers a **heavy** haptic tap to celebrate the connection.
  Future<void> showMatchNotification(String peerName) async {
    HapticFeedback.heavyImpact();

    await _showNotification(
      title: "You're connected!",
      body: 'You and $peerName are now connected',
    );
  }

  /// Shows a notification for an incoming text message.
  ///
  /// Triggers a **medium** haptic tap.
  Future<void> showMessageNotification(
    String senderName,
    String preview,
  ) async {
    HapticFeedback.mediumImpact();

    await _showNotification(
      title: 'New message',
      body: '$senderName: $preview',
    );
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  Future<void> _showNotification({
    required String title,
    required String body,
  }) async {
    if (!_initialized) {
      await initialize();
    }

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );

    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    await _plugin.show(_id, title, body, details);
  }
}
