import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:go_router/go_router.dart';
import 'package:liita/core/theme/app_theme.dart';
import 'package:liita/core/providers/providers.dart';
import 'package:liita/core/providers/game_provider.dart';
import 'package:liita/core/models/game_message.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final localProfile = ref.read(localProfileProvider);
      if (localProfile != null) {
        FlutterBluePlus.adapterState.listen((state) {
          if (state == BluetoothAdapterState.off) {
            try {
              FlutterBluePlus.turnOn();
            } catch (_) {}
          } else if (state == BluetoothAdapterState.on) {
            ref.read(meshServiceProvider).startMesh(localProfile);
            ref.read(appControllerProvider).initialize(localProfile.deviceId);
          }
        });

        ref.read(appControllerProvider).onMatchCreated = (peerId) {
          ref.read(newMatchProvider.notifier).state = peerId;
        };
      }
    });
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

    ref.listen<String?>(newMatchProvider, (previous, next) {
      if (next != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "You're connected!",
              style: TextStyle(color: AppColors.textOnPrimary, fontWeight: FontWeight.bold),
            ),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 3),
          ),
        );
        // Reset provider so we don't repeatedly trigger
        Future.microtask(() => ref.read(newMatchProvider.notifier).state = null);
      }
    });

    ref.listen<PendingGameInvite?>(pendingGameInviteProvider, (previous, next) {
      if (next != null) {
        showModalBottomSheet(
          context: context,
          backgroundColor: AppColors.surface,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (context) {
            bool responded = false;
            Future.delayed(const Duration(seconds: 30), () {
              if (context.mounted && !responded && Navigator.canPop(context)) {
                Navigator.pop(context);
              }
            });

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${next.peerName} wants to play Tic Tac Toe',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        TextButton(
                          onPressed: () {
                            responded = true;
                            Navigator.pop(context);
                            ref.read(appControllerProvider).sendGameMessage(
                              next.peerId,
                              GameMessage(
                                gameId: next.gameId,
                                type: GameMessageType.decline,
                                payload: {},
                              ),
                            );
                            ref.read(pendingGameInviteProvider.notifier).state = null;
                          },
                          child: const Text(
                            'Decline',
                            style: TextStyle(color: AppColors.textTertiary, fontSize: 16),
                          ),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                          ),
                          onPressed: () {
                            responded = true;
                            Navigator.pop(context);
                            ref.read(appControllerProvider).sendGameMessage(
                              next.peerId,
                              GameMessage(
                                gameId: next.gameId,
                                type: GameMessageType.accept,
                                payload: {},
                              ),
                            );
                            ref.read(ticTacToeProvider.notifier).onInviteAccepted(
                              next.gameId,
                              next.peerId,
                              next.peerName,
                            );
                            ref.read(pendingGameInviteProvider.notifier).state = null;
                            context.push('/games/tictactoe');
                          },
                          child: const Text(
                            'Accept',
                            style: TextStyle(color: AppColors.textOnPrimary, fontSize: 16),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ).whenComplete(() {
          // If dismissed by swiping down, we just clear the state. We don't send decline to save bandwidth or let it timeout.
          // Or we can send decline. Let's just clear the state.
          ref.read(pendingGameInviteProvider.notifier).state = null;
        });
      }
    });

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
