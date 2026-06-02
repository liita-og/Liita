import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liita/core/theme/app_theme.dart';
import 'package:liita/core/providers/providers.dart';
import 'package:liita/core/services/storage_service.dart';
import 'package:liita/core/widgets/avatar_widget.dart';
import 'package:liita/core/utils/constants.dart';

/// Premium user profile screen with glassmorphic cards.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _isEditing = false;
  late TextEditingController _nameController;
  late TextEditingController _seatController;
  late TextEditingController _occupationController;
  late TextEditingController _icebreakerAnswerController;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(localProfileProvider);
    _nameController = TextEditingController(text: profile?.name ?? '');
    _seatController = TextEditingController(text: profile?.seatNumber ?? '');
    _occupationController =
        TextEditingController(text: profile?.occupation ?? '');
    _icebreakerAnswerController =
        TextEditingController(text: profile?.icebreakerAnswer ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _seatController.dispose();
    _occupationController.dispose();
    _icebreakerAnswerController.dispose();
    super.dispose();
  }

  void _saveProfile() {
    final profile = ref.read(localProfileProvider);
    if (profile == null) return;

    final updated = profile.copyWith(
      name: _nameController.text.trim(),
      seatNumber: _seatController.text.trim().toUpperCase(),
      occupation: _occupationController.text.trim(),
      icebreakerAnswer: _icebreakerAnswerController.text.trim(),
      version: profile.version + 1,
    );

    ref.read(localProfileProvider.notifier).state = updated;
    // Save to storage as well
    StorageService.instance.saveProfile(updated);
    setState(() => _isEditing = false);
  }

  Future<void> _startNewFlight() async {
    // Show confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Start New Flight?'),
        content: const Text(
          'This will erase your current profile and disconnect you from the mesh. Are you sure?',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textTertiary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Start New Flight', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // 1. Stop mesh
    await ref.read(meshServiceProvider).stopMesh();
    // 2. Clear secure storage
    await StorageService.instance.clearAll();
    // 3. Clear providers (triggers router redirect to /onboarding)
    ref.read(localProfileProvider.notifier).state = null;
    ref.read(onboardingCompleteProvider.notifier).state = false;
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(localProfileProvider);

    if (profile == null) {
      return const Scaffold(
        body: Center(child: Text('No profile found')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          TextButton(
            onPressed: () {
              if (_isEditing) {
                _saveProfile();
              } else {
                setState(() => _isEditing = true);
              }
            },
            child: Text(
              _isEditing ? 'Save' : 'Edit',
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            // Avatar with glow
            Center(
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      blurRadius: 24,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    AvatarWidget(name: profile.name, size: 96),
                    if (_isEditing)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: AppColors.primaryGradient,
                          ),
                          child: const Icon(
                            Icons.camera_alt_rounded,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (!_isEditing) ...[
              Text(
                profile.name,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Seat ${profile.seatNumber} · ${profile.occupation} · ${profile.age}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),

            // Editable fields
            if (_isEditing) ...[
              _buildField('Name', _nameController, AppConstants.maxNameLength),
              _buildField('Seat', _seatController, AppConstants.maxSeatLength),
              _buildField(
                'Occupation',
                _occupationController,
                AppConstants.maxOccupationLength,
              ),
              _buildField(
                'Icebreaker Answer',
                _icebreakerAnswerController,
                AppConstants.maxIcebreakerAnswerLength,
              ),
            ],

            // Read-only sections
            if (!_isEditing) ...[
              // Icebreaker card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: AppRadius.lgAll,
                  border: Border.all(
                    color: AppColors.glassBorder,
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 14,
                          color: AppColors.primary.withValues(alpha: 0.7),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          profile.icebreakerPrompt,
                          style: TextStyle(
                            color: AppColors.primary.withValues(alpha: 0.8),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      profile.icebreakerAnswer.isNotEmpty
                          ? profile.icebreakerAnswer
                          : 'No answer yet',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),

              // Info section header
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'DETAILS',
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),

              // Info tiles in a glass card
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: AppRadius.lgAll,
                  border: Border.all(
                    color: AppColors.glassBorder,
                    width: 1,
                  ),
                ),
                child: Column(
                  children: [
                    _InfoTile(
                      icon: Icons.fingerprint_rounded,
                      label: 'Device ID',
                      value: '${profile.deviceId.substring(0, 8)}…',
                    ),
                    Divider(
                      height: 1,
                      color: AppColors.divider.withValues(alpha: 0.5),
                      indent: 52,
                    ),
                    _InfoTile(
                      icon: Icons.sync_rounded,
                      label: 'Profile Version',
                      value: 'v${profile.version}',
                    ),
                    Divider(
                      height: 1,
                      color: AppColors.divider.withValues(alpha: 0.5),
                      indent: 52,
                    ),
                    _InfoTile(
                      icon: Icons.bluetooth_rounded,
                      label: 'Mesh Mode',
                      value: 'Mock',
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.xxl),

              // App version
              Text(
                'Liita v0.1.0 · BLE Mesh Social',
                style: TextStyle(
                  color: AppColors.textTertiary.withValues(alpha: 0.6),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),

              // Start New Flight Button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _startNewFlight,
                  icon: const Icon(Icons.flight_takeoff_rounded, size: 18),
                  label: const Text('Start New Flight'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: BorderSide(color: AppColors.error.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                    shape: RoundedRectangleBorder(
                      borderRadius: AppRadius.mdAll,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildField(String label, TextEditingController ctrl, int maxLen) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: TextField(
        controller: ctrl,
        maxLength: maxLen,
        style: const TextStyle(color: AppColors.textPrimary),
        decoration: InputDecoration(
          labelText: label,
          counterStyle: const TextStyle(color: AppColors.textTertiary),
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 2,
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: AppRadius.smAll,
            ),
            child: Icon(icon, color: AppColors.primary, size: 18),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w500,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
