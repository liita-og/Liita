import 'dart:async';

import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:liita/core/providers/alert_provider.dart';
import 'package:liita/core/theme/app_theme.dart';
import 'package:liita/router.dart';

/// App-wide top banner for incoming waves/matches. Placed once at the root (in
/// [MaterialApp.router]'s builder) so it overlays every screen, including pushed
/// routes like chat. Watches [incomingAlertProvider]; slides in, auto-dismisses
/// after a few seconds, and on tap navigates (wave → Radar, match → that chat).
///
/// Must be a direct child of a [Stack].
class GlobalAlertBanner extends ConsumerStatefulWidget {
  const GlobalAlertBanner({super.key});

  @override
  ConsumerState<GlobalAlertBanner> createState() => _GlobalAlertBannerState();
}

class _GlobalAlertBannerState extends ConsumerState<GlobalAlertBanner>
    with SingleTickerProviderStateMixin {
  static const _visibleDuration = Duration(seconds: 4);

  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );

  RadarAlert? _current;
  Timer? _dismissTimer;

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _show(RadarAlert alert) {
    _dismissTimer?.cancel();
    setState(() => _current = alert);
    _ctrl.forward(from: 0);
    _dismissTimer = Timer(_visibleDuration, _hide);
  }

  Future<void> _hide() async {
    _dismissTimer?.cancel();
    if (!mounted) return;
    await _ctrl.reverse();
    if (mounted) setState(() => _current = null);
    // Clear so the same peer can trigger another banner later.
    ref.read(incomingAlertProvider.notifier).state = null;
  }

  void _onTap() {
    final alert = _current;
    if (alert == null) return;
    final router = ref.read(routerProvider);
    if (alert.kind == RadarAlertKind.match && alert.matchId != null) {
      router.push(
        '/chat/${alert.matchId}?name=${Uri.encodeComponent(alert.peerName)}',
      );
    } else {
      router.go('/radar');
    }
    _hide();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<RadarAlert?>(incomingAlertProvider, (_, next) {
      if (next != null) _show(next);
    });

    final alert = _current;
    if (alert == null) return const SizedBox.shrink();

    final topInset = MediaQuery.of(context).padding.top;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -1.2),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic)),
        child: FadeTransition(
          opacity: _ctrl,
          child: Padding(
            padding: EdgeInsets.fromLTRB(12, topInset + 8, 12, 0),
            child: _banner(alert),
          ),
        ),
      ),
    );
  }

  Widget _banner(RadarAlert alert) {
    final isMatch = alert.kind == RadarAlertKind.match;
    final title = isMatch
        ? 'You matched with ${alert.peerName}!'
        : '${alert.peerName} waved at you';
    final subtitle = isMatch ? 'Tap to say hello' : 'Tap to wave back';

    return GestureDetector(
      onTap: _onTap,
      child: Neumorphic(
        style: NeumorphicStyle(
          boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(18)),
          depth: 6,
          intensity: 0.6,
          color: NeuDark.base,
        ),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Neumorphic(
              style: const NeumorphicStyle(
                boxShape: NeumorphicBoxShape.circle(),
                depth: -3,
                color: NeuDark.base,
              ),
              padding: const EdgeInsets.all(10),
              child: Icon(
                isMatch ? Icons.favorite_rounded : Icons.waving_hand_rounded,
                color: NeuDark.accentBright,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: NeuDark.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: NeuDark.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: NeuDark.accentBright, size: 22),
          ],
        ),
      ),
    );
  }
}
