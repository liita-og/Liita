import 'dart:convert';
import 'dart:typed_data';

import 'package:liita/core/utils/constants.dart';

/// Represents a user's profile in the Liita mesh network.
///
/// This is the core identity model — each device has exactly one profile.
/// The [version] field increments on every profile update to enable
/// efficient BLE sync (peers only re-fetch if version is newer).
class UserProfile {
  final String deviceId;
  final String name;
  final int age;
  final String seatNumber;
  final String occupation;
  final String? photoHash;
  final int version;
  final String publicKey;
  final String icebreakerPrompt;
  final String icebreakerAnswer;

  const UserProfile({
    required this.deviceId,
    required this.name,
    required this.age,
    required this.seatNumber,
    required this.occupation,
    this.photoHash,
    this.version = 1,
    this.publicKey = '',
    this.icebreakerPrompt = '',
    this.icebreakerAnswer = '',
  });

  /// Validates all profile constraints. Returns null if valid, or error message.
  String? validate() {
    if (deviceId.isEmpty) return 'Device ID is required';
    if (name.isEmpty || name.length > AppConstants.maxNameLength) {
      return 'Name must be 1-${AppConstants.maxNameLength} characters';
    }
    if (age < AppConstants.minAge || age > AppConstants.maxAge) {
      return 'Age must be ${AppConstants.minAge}-${AppConstants.maxAge}';
    }
    if (seatNumber.isEmpty || seatNumber.length > AppConstants.maxSeatLength) {
      return 'Seat must be 1-${AppConstants.maxSeatLength} characters';
    }
    if (occupation.isEmpty ||
        occupation.length > AppConstants.maxOccupationLength) {
      return 'Occupation must be 1-${AppConstants.maxOccupationLength} characters';
    }
    if (icebreakerAnswer.length > AppConstants.maxIcebreakerAnswerLength) {
      return 'Icebreaker answer must be under ${AppConstants.maxIcebreakerAnswerLength} characters';
    }
    return null;
  }

  /// Packs profile into 26-byte BLE scan response format.
  /// Format: name(20B) | age(1B) | seat(4B) | version(1B)
  Uint8List toScanResponseBytes() {
    final bytes = Uint8List(AppConstants.scanResponseTotalBytes);
    final nameBytes = utf8.encode(
      name.padRight(AppConstants.scanResponseNameBytes),
    );
    bytes.setRange(
      0,
      AppConstants.scanResponseNameBytes,
      nameBytes.take(AppConstants.scanResponseNameBytes).toList(),
    );
    bytes[20] = age.clamp(0, 255);
    final seatBytes = utf8.encode(
      seatNumber.padRight(AppConstants.scanResponseSeatBytes),
    );
    bytes.setRange(
      21,
      25,
      seatBytes.take(AppConstants.scanResponseSeatBytes).toList(),
    );
    bytes[25] = version.clamp(0, 255);
    return bytes;
  }

  /// Parses a profile from 26-byte BLE scan response data.
  factory UserProfile.fromScanResponseBytes(Uint8List bytes, String deviceId) {
    if (bytes.length < AppConstants.scanResponseTotalBytes) {
      throw ArgumentError(
        'Scan response must be ${AppConstants.scanResponseTotalBytes} bytes',
      );
    }
    final name = utf8.decode(bytes.sublist(0, 20)).trim();
    final age = bytes[20];
    final seat = utf8.decode(bytes.sublist(21, 25)).trim();
    final version = bytes[25];
    return UserProfile(
      deviceId: deviceId,
      name: name,
      age: age,
      seatNumber: seat,
      occupation: '', // Not in scan response; fetched via profileSync
      version: version,
    );
  }

  UserProfile copyWith({
    String? deviceId,
    String? name,
    int? age,
    String? seatNumber,
    String? occupation,
    String? photoHash,
    int? version,
    String? publicKey,
    String? icebreakerPrompt,
    String? icebreakerAnswer,
  }) {
    return UserProfile(
      deviceId: deviceId ?? this.deviceId,
      name: name ?? this.name,
      age: age ?? this.age,
      seatNumber: seatNumber ?? this.seatNumber,
      occupation: occupation ?? this.occupation,
      photoHash: photoHash ?? this.photoHash,
      version: version ?? this.version,
      publicKey: publicKey ?? this.publicKey,
      icebreakerPrompt: icebreakerPrompt ?? this.icebreakerPrompt,
      icebreakerAnswer: icebreakerAnswer ?? this.icebreakerAnswer,
    );
  }

  Map<String, dynamic> toJson() => {
    'deviceId': deviceId,
    'name': name,
    'age': age,
    'seatNumber': seatNumber,
    'occupation': occupation,
    'photoHash': photoHash,
    'version': version,
    'publicKey': publicKey,
    'icebreakerPrompt': icebreakerPrompt,
    'icebreakerAnswer': icebreakerAnswer,
  };

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    deviceId: json['deviceId'] as String,
    name: json['name'] as String,
    age: json['age'] as int,
    seatNumber: json['seatNumber'] as String,
    occupation: json['occupation'] as String,
    photoHash: json['photoHash'] as String?,
    version: json['version'] as int? ?? 1,
    publicKey: json['publicKey'] as String? ?? '',
    icebreakerPrompt: json['icebreakerPrompt'] as String? ?? '',
    icebreakerAnswer: json['icebreakerAnswer'] as String? ?? '',
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserProfile &&
          deviceId == other.deviceId &&
          version == other.version;

  @override
  int get hashCode => deviceId.hashCode ^ version.hashCode;

  @override
  String toString() => 'UserProfile($name, seat=$seatNumber, v$version)';
}
