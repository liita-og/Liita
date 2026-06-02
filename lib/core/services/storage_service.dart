import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:liita/core/models/user_profile.dart';

/// Persistent key-value store backed by flutter_secure_storage.
///
/// Stores:
///   - [_kOnboardingDone] — boolean flag, set once on first onboarding
///   - [_kProfile]        — JSON-encoded [UserProfile], updated on save
///
/// The null-profile guard is enforced here: [isOnboardingComplete] returns
/// false if the profile is missing even if the flag is set, ensuring the
/// router always redirects to onboarding in that case.
class StorageService {
  StorageService._();

  static final StorageService instance = StorageService._();

  static const _kOnboardingDone = 'has_completed_onboarding';
  static const _kProfile = 'local_user_profile';

  static const _storageOptions = AndroidOptions(encryptedSharedPreferences: true);
  static final _storage = FlutterSecureStorage(aOptions: _storageOptions);

  // ---------------------------------------------------------------------------
  // Onboarding flag
  // ---------------------------------------------------------------------------

  /// Returns true only if the onboarding flag is set AND a valid profile
  /// exists in storage. A missing profile always redirects to onboarding.
  Future<bool> isOnboardingComplete() async {
    try {
      final flag = await _storage.read(key: _kOnboardingDone);
      if (flag != 'true') return false;
      // Null-profile guard: flag alone is not enough
      final profile = await loadProfile();
      return profile != null;
    } catch (e) {
      debugPrint('[StorageService] isOnboardingComplete error: $e');
      return false;
    }
  }

  /// Marks onboarding as complete and persists the profile atomically.
  Future<void> completeOnboarding(UserProfile profile) async {
    try {
      await Future.wait([
        _storage.write(key: _kOnboardingDone, value: 'true'),
        _storage.write(key: _kProfile, value: jsonEncode(profile.toJson())),
      ]);
      debugPrint('[StorageService] Onboarding complete, profile saved.');
    } catch (e) {
      debugPrint('[StorageService] completeOnboarding error: $e');
      rethrow;
    }
  }

  /// Clears all persisted state — called when user starts a "New Flight".
  Future<void> clearAll() async {
    try {
      await Future.wait([
        _storage.delete(key: _kOnboardingDone),
        _storage.delete(key: _kProfile),
      ]);
      debugPrint('[StorageService] Cleared all persistent state.');
    } catch (e) {
      debugPrint('[StorageService] clearAll error: $e');
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Profile
  // ---------------------------------------------------------------------------

  /// Loads and deserialises the stored [UserProfile], or null if absent.
  Future<UserProfile?> loadProfile() async {
    try {
      final raw = await _storage.read(key: _kProfile);
      if (raw == null) return null;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return UserProfile.fromJson(map);
    } catch (e) {
      debugPrint('[StorageService] loadProfile error: $e');
      return null;
    }
  }

  /// Persists an updated [profile] without touching the onboarding flag.
  Future<void> saveProfile(UserProfile profile) async {
    try {
      await _storage.write(
        key: _kProfile,
        value: jsonEncode(profile.toJson()),
      );
    } catch (e) {
      debugPrint('[StorageService] saveProfile error: $e');
    }
  }
}
