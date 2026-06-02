import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:liita/core/theme/app_theme.dart';
import 'package:liita/core/utils/constants.dart';
import 'package:liita/core/models/user_profile.dart';
import 'package:liita/core/providers/providers.dart';
import 'package:liita/core/services/storage_service.dart';

/// 6-step onboarding flow with smooth page transitions.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;

  // Form data
  final _nameController = TextEditingController();
  final _ageController = TextEditingController();
  final _seatController = TextEditingController();
  final _occupationController = TextEditingController();
  final _icebreakerAnswerController = TextEditingController();
  int _selectedPromptIndex = 0;
  String? _photoPath;

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _ageController.dispose();
    _seatController.dispose();
    _occupationController.dispose();
    _icebreakerAnswerController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < 5) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  void _completeOnboarding() async {
    try {
      debugPrint('[Onboarding] Starting completion flow...');
      final profile = UserProfile(
        deviceId: const Uuid().v4(),
        name: _nameController.text.trim(),
        age: int.tryParse(_ageController.text) ?? 25,
        seatNumber: _seatController.text.trim().toUpperCase(),
        occupation: _occupationController.text.trim(),
        icebreakerPrompt: IcebreakerPrompts.prompts[_selectedPromptIndex],
        icebreakerAnswer: _icebreakerAnswerController.text.trim(),
      );

      // Capture ALL providers synchronously BEFORE any await.
      final db = ref.read(databaseServiceProvider);
      final appController = ref.read(appControllerProvider);
      final mesh = ref.read(meshServiceProvider);
      final router = GoRouter.of(context);

      // Persist to secure storage FIRST — ensures restart resilience.
      debugPrint('[Onboarding] Persisting to secure storage...');
      await StorageService.instance.completeOnboarding(profile);

      // Set in-memory state (triggers router redirect to /radar)
      ref.read(localProfileProvider.notifier).state = profile;
      ref.read(onboardingCompleteProvider.notifier).state = true;

      // DB + service init after state change (uses locally-captured vars)
      debugPrint('[Onboarding] Saving profile to DB...');
      await db.upsertProfile(profile);

      debugPrint('[Onboarding] Initializing AppController...');
      await appController.initialize(profile.deviceId);

      debugPrint('[Onboarding] Requesting Bluetooth permissions...');
      await [
        Permission.bluetoothScan,
        Permission.bluetoothAdvertise,
        Permission.bluetoothConnect,
        Permission.location,
      ].request();

      debugPrint('[Onboarding] Starting mesh service...');
      await mesh.startMesh(profile);

      debugPrint('[Onboarding] Navigation triggered by provider state change.');
      router.go('/radar');
    } catch (e, st) {
      debugPrint('[Onboarding] ERROR in _completeOnboarding: $e');
      debugPrint('$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Setup failed: $e')),
        );
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            // Progress indicator
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              child: Row(
                children: List.generate(6, (i) {
                  final isActive = i <= _currentPage;
                  return Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      height: 3,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        borderRadius: AppRadius.pillAll,
                        color: isActive
                            ? AppColors.primary
                            : AppColors.divider,
                      ),
                    ),
                  );
                }),
              ),
            ),
            // Pages
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _currentPage = i),
                children: [
                  _WelcomePage(onNext: _nextPage),
                  _NameAgePage(
                    nameController: _nameController,
                    ageController: _ageController,
                    onNext: _nextPage,
                    onBack: _previousPage,
                  ),
                  _SeatOccupationPage(
                    seatController: _seatController,
                    occupationController: _occupationController,
                    onNext: _nextPage,
                    onBack: _previousPage,
                  ),
                  _IcebreakerPage(
                    selectedIndex: _selectedPromptIndex,
                    answerController: _icebreakerAnswerController,
                    onSelectPrompt: (i) =>
                        setState(() => _selectedPromptIndex = i),
                    onNext: _nextPage,
                    onBack: _previousPage,
                  ),
                  _PhotoPage(
                    photoPath: _photoPath,
                    onPhotoPicked: (path) =>
                        setState(() => _photoPath = path),
                    onNext: _nextPage,
                    onBack: _previousPage,
                  ),
                  _ConfirmationPage(
                    name: _nameController.text,
                    onComplete: _completeOnboarding,
                    onBack: _previousPage,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Step 1: Welcome
// =============================================================================

class _WelcomePage extends StatelessWidget {
  final VoidCallback onNext;

  const _WelcomePage({required this.onNext});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(),
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppColors.primaryGradient,
              boxShadow: AppShadows.primaryGlow,
            ),
            child: const Icon(
              Icons.connecting_airports_rounded,
              size: 56,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'Liita',
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
              fontSize: 42,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.5,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Connect with fellow travelers',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: AppColors.textSecondary,
              fontSize: 16,
            ),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: onNext,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadius.mdAll,
                ),
              ),
              child: const Text(
                'Get Started',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textOnPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

// =============================================================================
// Step 2: Name + Age
// =============================================================================

class _NameAgePage extends StatelessWidget {
  final TextEditingController nameController;
  final TextEditingController ageController;
  final VoidCallback onNext;
  final VoidCallback onBack;

  const _NameAgePage({
    required this.nameController,
    required this.ageController,
    required this.onNext,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return _OnboardingStepLayout(
      title: "What's your name?",
      subtitle: "This is how other travelers will see you",
      onNext: onNext,
      onBack: onBack,
      canProceed: true,
      children: [
        TextField(
          controller: nameController,
          maxLength: AppConstants.maxNameLength,
          textCapitalization: TextCapitalization.words,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 18),
          decoration: const InputDecoration(
            hintText: 'Your first name',
            prefixIcon: Icon(Icons.person_outline, color: AppColors.primary),
            counterStyle: TextStyle(color: AppColors.textTertiary),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        TextField(
          controller: ageController,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 18),
          decoration: const InputDecoration(
            hintText: 'Your age',
            prefixIcon: Icon(Icons.cake_outlined, color: AppColors.primary),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Step 3: Seat + Occupation
// =============================================================================

class _SeatOccupationPage extends StatelessWidget {
  final TextEditingController seatController;
  final TextEditingController occupationController;
  final VoidCallback onNext;
  final VoidCallback onBack;

  const _SeatOccupationPage({
    required this.seatController,
    required this.occupationController,
    required this.onNext,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return _OnboardingStepLayout(
      title: "Where are you sitting?",
      subtitle: "Helps others find you on the flight",
      onNext: onNext,
      onBack: onBack,
      canProceed: true,
      children: [
        TextField(
          controller: seatController,
          maxLength: AppConstants.maxSeatLength,
          textCapitalization: TextCapitalization.characters,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 18),
          decoration: const InputDecoration(
            hintText: 'e.g. 14C',
            prefixIcon:
                Icon(Icons.airline_seat_recline_normal, color: AppColors.primary),
            counterStyle: TextStyle(color: AppColors.textTertiary),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        TextField(
          controller: occupationController,
          maxLength: AppConstants.maxOccupationLength,
          textCapitalization: TextCapitalization.words,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 18),
          decoration: const InputDecoration(
            hintText: 'What do you do?',
            prefixIcon: Icon(Icons.work_outline, color: AppColors.primary),
            counterStyle: TextStyle(color: AppColors.textTertiary),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Step 4: Icebreaker
// =============================================================================

class _IcebreakerPage extends StatelessWidget {
  final int selectedIndex;
  final TextEditingController answerController;
  final ValueChanged<int> onSelectPrompt;
  final VoidCallback onNext;
  final VoidCallback onBack;

  const _IcebreakerPage({
    required this.selectedIndex,
    required this.answerController,
    required this.onSelectPrompt,
    required this.onNext,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return _OnboardingStepLayout(
      title: 'Pick an icebreaker',
      subtitle: 'This will show on your profile to spark conversations',
      onNext: onNext,
      onBack: onBack,
      canProceed: true,
      children: [
        SizedBox(
          height: 140,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: IcebreakerPrompts.prompts.length,
            itemBuilder: (context, i) {
              final isSelected = i == selectedIndex;
              return GestureDetector(
                onTap: () => onSelectPrompt(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 180,
                  margin: const EdgeInsets.only(right: AppSpacing.sm),
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary.withValues(alpha: 0.12)
                        : AppColors.surfaceLight,
                    borderRadius: AppRadius.lgAll,
                    border: Border.all(
                      color:
                          isSelected ? AppColors.primary : AppColors.glassBorder,
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _promptIcons[i % _promptIcons.length],
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.textTertiary,
                        size: 26,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        IcebreakerPrompts.prompts[i],
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isSelected
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          IcebreakerPrompts.prompts[selectedIndex],
          style: const TextStyle(
            color: AppColors.primary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: answerController,
          maxLength: AppConstants.maxIcebreakerAnswerLength,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
          decoration: const InputDecoration(
            hintText: 'Your answer...',
            counterStyle: TextStyle(color: AppColors.textTertiary),
          ),
        ),
      ],
    );
  }

  static const _promptIcons = [
    Icons.cookie_outlined,
    Icons.flight_class_outlined,
    Icons.location_city_outlined,
    Icons.tv_outlined,
    Icons.music_note_outlined,
    Icons.flag_outlined,
    Icons.coffee_outlined,
    Icons.star_outlined,
    Icons.public_outlined,
    Icons.emoji_emotions_outlined,
  ];
}

// =============================================================================
// Step 5: Photo (optional) — now with working image picker
// =============================================================================

class _PhotoPage extends StatelessWidget {
  final String? photoPath;
  final ValueChanged<String?> onPhotoPicked;
  final VoidCallback onNext;
  final VoidCallback onBack;

  const _PhotoPage({
    required this.photoPath,
    required this.onPhotoPicked,
    required this.onNext,
    required this.onBack,
  });

  Future<void> _pickPhoto(BuildContext context) async {
    final picker = ImagePicker();
    try {
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 70,
      );
      if (picked != null) {
        onPhotoPicked(picked.path);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open gallery: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _OnboardingStepLayout(
      title: 'Add a photo',
      subtitle: "Optional — you'll get a cool avatar either way",
      onNext: onNext,
      onBack: onBack,
      canProceed: true,
      nextLabel: photoPath != null ? 'Continue' : 'Skip for now',
      children: [
        Center(
          child: GestureDetector(
            onTap: () => _pickPhoto(context),
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.surfaceLight,
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  width: 2,
                ),
                image: photoPath != null
                    ? DecorationImage(
                        image: FileImage(File(photoPath!)),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: photoPath == null
                  ? const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.camera_alt_outlined,
                          color: AppColors.primary,
                          size: 40,
                        ),
                        SizedBox(height: AppSpacing.sm),
                        Text(
                          'Tap to add',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    )
                  : null,
            ),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Step 6: Confirmation
// =============================================================================

class _ConfirmationPage extends StatelessWidget {
  final String name;
  final VoidCallback onComplete;
  final VoidCallback onBack;

  const _ConfirmationPage({
    required this.name,
    required this.onComplete,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: AppSpacing.xxl),
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppColors.primaryGradient,
                boxShadow: AppShadows.primaryGlow,
              ),
              child: const Icon(
                Icons.check_rounded,
                size: 48,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              "You're all set, ${name.isNotEmpty ? name : 'traveler'}!",
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              "We'll start scanning for nearby travelers.\nYour BLE mesh is about to light up.",
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                height: 1.5,
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            Row(
              children: [
                TextButton(
                  onPressed: onBack,
                  child: const Text('Back'),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: SizedBox(
                    height: 56,
                    child: ElevatedButton(
                      onPressed: onComplete,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: AppRadius.mdAll,
                        ),
                      ),
                      child: const Text(
                        'Start Exploring',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textOnPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Shared step layout — uses SingleChildScrollView to prevent overflow
// =============================================================================

class _OnboardingStepLayout extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> children;
  final VoidCallback onNext;
  final VoidCallback onBack;
  final bool canProceed;
  final String nextLabel;

  const _OnboardingStepLayout({
    required this.title,
    required this.subtitle,
    required this.children,
    required this.onNext,
    required this.onBack,
    this.canProceed = true,
    this.nextLabel = 'Continue',
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Scrollable content area
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: AppSpacing.md),
                  Text(title,
                      style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  ...children,
                ],
              ),
            ),
          ),
          // Fixed bottom buttons
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              TextButton(
                onPressed: onBack,
                child: const Text('Back'),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: canProceed ? onNext : null,
                    child: Text(nextLabel),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
