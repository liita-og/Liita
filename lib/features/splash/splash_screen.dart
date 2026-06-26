import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:liita/core/theme/app_theme.dart';
import 'package:liita/core/providers/providers.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      
      final isOnboarded = ref.read(onboardingCompleteProvider);
      final profile = ref.read(localProfileProvider);
      final bool shouldOnboard = !isOnboarded || profile == null;

      if (shouldOnboard) {
        context.go('/onboarding');
      } else {
        context.go('/radar');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo
            Neumorphic(
              style: const NeumorphicStyle(
                boxShape: NeumorphicBoxShape.circle(),
                depth: 6,
                intensity: 0.6,
                color: NeuDark.base,
              ),
              padding: const EdgeInsets.all(26),
              child: const Icon(
                Icons.flight_takeoff_rounded,
                size: 50,
                color: NeuDark.accentBright,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Liita',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 32,
                fontWeight: FontWeight.bold,
                letterSpacing: 2.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
