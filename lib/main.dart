import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liita/core/theme/app_theme.dart';
import 'package:liita/core/services/database_service.dart';
import 'package:liita/core/services/crypto_service.dart';
import 'package:liita/core/services/storage_service.dart';
import 'package:liita/core/models/user_profile.dart';
import 'package:liita/core/providers/providers.dart';
import 'package:liita/router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize DatabaseService
  final db = DatabaseService();
  await db.initialize();

  // Initialize CryptoService
  final crypto = CryptoServiceImpl();
  await crypto.initialize();

  // Read onboarding state and stored profile from secure storage BEFORE runApp.
  // This guarantees the router gets the right initial location synchronously.
  final storage = StorageService.instance;
  final bool isOnboarded = await storage.isOnboardingComplete();
  final UserProfile? storedProfile = isOnboarded ? await storage.loadProfile() : null;

  debugPrint('[main] isOnboarded=$isOnboarded, profile=${storedProfile?.name}');

  runApp(
    ProviderScope(
      overrides: [
        databaseServiceProvider.overrideWithValue(db),
        cryptoServiceProvider.overrideWithValue(crypto),
        // Seed the onboarding flag from storage
        onboardingCompleteProvider.overrideWith((ref) => isOnboarded && storedProfile != null),
        // Seed the local profile from storage (null if not onboarded)
        localProfileProvider.overrideWith((ref) => storedProfile),
      ],
      child: const LiitaApp(),
    ),
  );
}

class LiitaApp extends ConsumerWidget {
  const LiitaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Liita',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      routerConfig: router,
    );
  }
}
