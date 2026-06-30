import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liita/core/theme/app_theme.dart';
import 'package:liita/core/services/database_service.dart';
import 'package:liita/core/services/crypto_service.dart';
import 'package:liita/core/services/storage_service.dart';
import 'package:liita/core/services/mesh_service_flutter.dart';
import 'package:liita/core/models/user_profile.dart';
import 'package:liita/core/providers/providers.dart';
import 'package:liita/core/widgets/global_alert_banner.dart';
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
  UserProfile? storedProfile = isOnboarded ? await storage.loadProfile() : null;

  // Keep the advertised public key in sync with the actual keypair. This covers
  // two cases: (1) installs onboarded before the key was embedded in the profile
  // (empty key), and (2) a keypair that changed underneath us. Without this, the
  // profile peers read would carry a stale key and encrypted chat would fail.
  if (storedProfile != null) {
    try {
      final pub = await crypto.exportPublicKey(await crypto.getPublicKey());
      if (storedProfile.publicKey != pub) {
        storedProfile = storedProfile.copyWith(publicKey: pub);
        await storage.saveProfile(storedProfile);
        await db.upsertProfile(storedProfile);
        debugPrint('[main] Synced profile publicKey to current keypair');
      }
    } catch (e) {
      debugPrint('[main] publicKey sync failed: $e');
    }
  }

  // Initialize MeshService
  final mesh = FlutterMeshService();
  if (isOnboarded && storedProfile != null) {
    debugPrint('[main] Starting mesh for profile ${storedProfile.deviceId}');
    // Do not await, let it start in the background to avoid blocking UI frame
    mesh.startMesh(storedProfile);
  }

  debugPrint('[main] isOnboarded=$isOnboarded, profile=${storedProfile?.name}');

  runApp(
    ProviderScope(
      overrides: [
        databaseServiceProvider.overrideWithValue(db),
        cryptoServiceProvider.overrideWithValue(crypto),
        meshServiceProvider.overrideWithValue(mesh),
        // Seed the onboarding flag from storage
        onboardingCompleteProvider.overrideWith((ref) => isOnboarded && storedProfile != null),
        // Seed the local profile from storage (null if not onboarded)
        localProfileProvider.overrideWith((ref) => storedProfile),
      ],
      child: const LiitaApp(),
    ),
  );
}

/// App-wide dark soft-UI theme for the flutter_neumorphic_plus widgets.
/// Both `theme` and `darkTheme` are set to this so the look is always dark,
/// regardless of the device's system brightness. (The standalone showcase wraps
/// its own light NeumorphicTheme, which overrides this locally.)
const NeumorphicThemeData _neuDarkTheme = NeumorphicThemeData(
  baseColor: NeuDark.base,
  accentColor: NeuDark.accent,
  variantColor: NeuDark.accentDeep,
  defaultTextColor: NeuDark.text,
  shadowLightColor: NeuDark.highlight,
  shadowDarkColor: NeuDark.shadow,
  shadowLightColorEmboss: NeuDark.highlight,
  shadowDarkColorEmboss: NeuDark.shadow,
  depth: 5,
  intensity: 0.55,
  lightSource: LightSource.topLeft,
);

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
      builder: (context, child) => NeumorphicTheme(
        theme: _neuDarkTheme,
        darkTheme: _neuDarkTheme,
        child: Stack(
          children: [
            child ?? const SizedBox.shrink(),
            const GlobalAlertBanner(),
          ],
        ),
      ),
    );
  }
}
