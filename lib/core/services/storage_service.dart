import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:liita/core/models/user_profile.dart';
import 'package:liita/core/utils/constants.dart';

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

  static const _storageOptions = AndroidOptions(encryptedSharedPreferences: true);
  static final _storage = FlutterSecureStorage(aOptions: _storageOptions);

  // ---------------------------------------------------------------------------
  // Onboarding flag
  // ---------------------------------------------------------------------------

  /// Returns true only if the onboarding flag is set AND a valid profile
  /// exists in storage. A missing profile always redirects to onboarding.
  Future<bool> isOnboardingComplete() async {
    try {
      final flag = await _storage.read(key: AppConstants.keyOnboardingComplete);
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
      await _storage.write(key: AppConstants.keyProfileJson, value: jsonEncode(profile.toJson()));
      await _storage.write(key: AppConstants.keyOnboardingComplete, value: 'true');
      debugPrint('[StorageService] Onboarding complete, profile saved.');
    } catch (e) {
      debugPrint('[StorageService] completeOnboarding error: $e');
      rethrow;
    }
  }

  /// Sets the onboarding flag without touching the profile.
  Future<void> setOnboardingComplete(bool complete) async {
    try {
      if (complete) {
        await _storage.write(key: AppConstants.keyOnboardingComplete, value: 'true');
      } else {
        await _storage.delete(key: AppConstants.keyOnboardingComplete);
      }
    } catch (e) {
      debugPrint('[StorageService] setOnboardingComplete error: $e');
    }
  }

  /// Clears all persisted state — called when user starts a "New Flight".
  Future<void> clearAll() async {
    try {
      await _storage.delete(key: AppConstants.keyOnboardingComplete);
      await _storage.delete(key: AppConstants.keyProfileJson);
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
      final raw = await _storage.read(key: AppConstants.keyProfileJson);
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
        key: AppConstants.keyProfileJson,
        value: jsonEncode(profile.toJson()),
      );
    } catch (e) {
      debugPrint('[StorageService] saveProfile error: $e');
      rethrow;
    }
  }
}
