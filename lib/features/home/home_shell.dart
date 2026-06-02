import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:liita/core/theme/app_theme.dart';
import 'package:liita/core/providers/providers.dart';

/// Main app shell with floating pill tab bar — no labels, dot indicator.
class HomeShell extends ConsumerStatefulWidget {
  final Widget child;

  const HomeShell({super.key, required this.child});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell>
    with WidgetsBindingObserver {

  static const _tabs = [
    '/radar',
    '/lounge',
    '/games',
    '/matches',
    '/profile',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final mesh = ref.read(meshServiceProvider);
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        mesh.setBackgroundMode();
      case AppLifecycleState.resumed:
        mesh.setForegroundMode();
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final currentIndex = _tabs.indexWhere((t) => location.startsWith(t));
    final selectedIndex = currentIndex >= 0 ? currentIndex : 0;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: widget.child,
      bottomNavigationBar: _FloatingTabBar(
        selectedIndex: selectedIndex,
        onTap: (i) => context.go(_tabs[i]),
      ),
    );
  }
}

class _FloatingTabBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;

  const _FloatingTabBar({
    required this.selectedIndex,
    required this.onTap,
  });

  static const _icons = [
    Icons.wifi_tethering_rounded,   // radar
    Icons.chat_bubble_outline_rounded, // lounge
    Icons.sports_esports_outlined,  // games
    Icons.people_outline_rounded,   // matches
    Icons.person_outline_rounded,   // profile
  ];

  static const _activeIcons = [
    Icons.wifi_tethering_rounded,
    Icons.chat_bubble_rounded,
    Icons.sports_esports_rounded,
    Icons.people_rounded,
    Icons.person_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 20, left: 48, right: 48),
        child: Container(
          height: 60,
          decoration: BoxDecoration(
            color: const Color(0xE8121214), // surface with 91% opacity
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.06),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 32,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(5, (i) {
              final isActive = i == selectedIndex;
              return GestureDetector(
                onTap: () => onTap(i),
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: 44,
                  height: 60,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: Icon(
                          isActive ? _activeIcons[i] : _icons[i],
                          key: ValueKey(isActive),
                          size: 22,
                          color: isActive
                              ? AppColors.textPrimary
                              : AppColors.textTertiary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: isActive ? 4 : 0,
                        height: isActive ? 4 : 0,
                        decoration: const BoxDecoration(
                          color: AppColors.textPrimary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
