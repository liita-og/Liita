// App-wide constants for the Liita BLE mesh app

class AppConstants {
  AppConstants._();

  // BLE
  static const String bleServiceUuid = '6E400001-B5A3-F393-E0A9-E50E24DCCA9E';
  static const String bleProfileCharUuid = '6E400002-B5A3-F393-E0A9-E50E24DCCA9E';

  // Mesh
  static const int defaultTtl = 8;
  static const int dedupCacheMaxAgeMs = 600000; // 10 minutes
  static const int stalePeerTimeoutMs = 300000; // 5 minutes
  static const int photoChunkTimeoutMs = 300000; // 5 minutes
  static const int photoChunkSize = 400; // bytes

  // Validation
  static const int maxNameLength = 20;
  static const int minAge = 18;
  static const int maxAge = 99;
  static const int maxSeatLength = 4;
  static const int maxOccupationLength = 30;
  static const int maxIcebreakerAnswerLength = 60;
  static const int maxBroadcastLength = 200;

  // Database
  /// Maximum number of broadcast messages fetched in a single query.
  static const int kBroadcastQueryLimit = 200;

  // BLE Scan Response
  static const int scanResponseNameBytes = 20;
  static const int scanResponseAgeBytes = 1;
  static const int scanResponseSeatBytes = 4;
  static const int scanResponseVersionBytes = 1;
  static const int scanResponseTotalBytes = 26;

  // Crypto
  static const String hkdfSalt = 'liita-v1';
  static const int aesKeyLength = 32;
  static const int gcmNonceLength = 12;

  // Platform Channels
  static const String meshMethodChannel = 'com.liita.app/mesh';
  static const String peersEventChannel = 'com.liita.app/peers';
  static const String packetsEventChannel = 'com.liita.app/packets';

  // Secure Storage Keys
  static const String keyDeviceId = 'liita_device_id';
  static const String keyPrivateKey = 'liita_private_key';
  static const String keyPublicKey = 'liita_public_key';
  static const String keyProfileJson = 'liita_profile';
  static const String keyOnboardingComplete = 'liita_onboarding_complete';
  static const String keyBlockList = 'liita_block_list';
}

class IcebreakerPrompts {
  IcebreakerPrompts._();

  static const List<String> prompts = [
    "What's your go-to travel snack?",
    "Window or aisle, and why?",
    "Best city you've ever visited?",
    "What are you binge-watching right now?",
    "If this flight had a theme song, what would it be?",
    "One thing on your bucket list?",
    "Coffee or tea at 30,000 feet?",
    "What's your hidden talent?",
    "If you could teleport anywhere right now?",
    "Describe your vibe in 3 words",
  ];
}
