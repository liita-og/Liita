import 'dart:async';

import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart';
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

  StreamSubscription<BluetoothAdapterState>? _adapterStateSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Initialize notifications + request POST_NOTIFICATIONS up front so wave
      // and connection notifications can actually fire on Android 13+.
      ref.read(notificationServiceProvider).initialize();

      final localProfile = ref.read(localProfileProvider);
      if (localProfile != null) {
        _adapterStateSub = FlutterBluePlus.adapterState.listen((state) {
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

        // Restore persisted wave state from the DB so a peer you've waved at
        // keeps its radar card across app restarts, and incoming-wave badges
        // survive too. (Out-of-range removal for non-waved peers is handled by
        // the native presence signal.)
        final db = ref.read(databaseServiceProvider);
        db.getWavedPeerIds(localProfile.deviceId).then((ids) {
          if (ids.isNotEmpty && mounted) {
            ref.read(wavedAtProvider.notifier).update((s) => {...s, ...ids});
          }
        });
        db.getWavedByIds(localProfile.deviceId).then((ids) {
          if (ids.isNotEmpty && mounted) {
            ref.read(wavedByProvider.notifier).update((s) => {...s, ...ids});
          }
        });
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _adapterStateSub?.cancel();
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

    // Connection feedback is delivered via a system notification
    // ("You have connected with X!") fired from AppController._createMatch,
    // so no in-app snackbar is shown here.

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
                      '${next.peerName} wants to play ${next.gameType.label}',
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
                                gameType: next.gameType,
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
                                gameType: next.gameType,
                                type: GameMessageType.accept,
                                payload: {},
                              ),
                            );
                            switch (next.gameType) {
                              case GameType.ticTacToe:
                                ref.read(ticTacToeProvider.notifier).onInviteAccepted(
                                      next.gameId,
                                      next.peerId,
                                      next.peerName,
                                    );
                                ref.read(pendingGameInviteProvider.notifier).state = null;
                                context.push('/games/tictactoe');
                                break;
                              case GameType.trivia:
                                ref.read(triviaGameProvider.notifier).onOpponentJoined(
                                      next.gameId,
                                      next.peerId,
                                      next.peerName,
                                    );
                                ref.read(pendingGameInviteProvider.notifier).state = null;
                                context.push('/games/trivia');
                                break;
                            }
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
        padding: const EdgeInsets.only(bottom: 20, left: 40, right: 40),
        child: Neumorphic(
          style: NeumorphicStyle(
            boxShape:
                NeumorphicBoxShape.roundRect(BorderRadius.circular(999)),
            depth: 6,
            intensity: 0.6,
            color: NeuDark.base,
          ),
          child: SizedBox(
            height: 64,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(5, (i) {
                final isActive = i == selectedIndex;
                return GestureDetector(
                  onTap: () => onTap(i),
                  behavior: HitTestBehavior.opaque,
                  child: SizedBox(
                    width: 48,
                    height: 64,
                    child: Center(
                      child: isActive
                          ? Neumorphic(
                              style: const NeumorphicStyle(
                                boxShape: NeumorphicBoxShape.circle(),
                                depth: -3,
                                intensity: 0.7,
                                color: NeuDark.base,
                              ),
                              padding: const EdgeInsets.all(9),
                              child: Icon(_activeIcons[i],
                                  size: 20, color: NeuDark.accentBright),
                            )
                          : Icon(_icons[i],
                              size: 22, color: NeuDark.textFaint),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}
