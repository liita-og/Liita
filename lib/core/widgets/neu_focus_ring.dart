import 'package:flutter/material.dart';

import 'package:liita/core/theme/app_theme.dart';

/// Wraps an interactive child with a visible keyboard / D-pad / switch-access
/// focus indicator.
///
/// The neumorphic shadow communicates depth, not focus — a non-touch user
/// (hardware keyboard, TV remote D-pad, Android switch access) has no way to
/// tell which control is selected. [NeuFocusRing] makes its child focus-
/// traversable and paints an accent outline (plus a soft glow) around it, but
/// ONLY when focus arrives via a non-pointer interaction. Pointer taps do not
/// show the ring, matching the platform focus-highlight convention.
///
/// If [onActivate] is supplied, Enter / Space / the platform select key invoke
/// it while the ring is focused, so the control is fully operable without a
/// pointer. Leave it null for controls that have no discrete "activate" action
/// (e.g. a continuous drag knob) — the ring is then purely a visible indicator.
class NeuFocusRing extends StatefulWidget {
  /// The control to wrap. Keep its own [Semantics] in place; this widget only
  /// adds the focus affordance, not the semantic label.
  final Widget child;

  /// Outline shape. Use [CircleBorder] for the round dials, [StadiumBorder] for
  /// pills/switches, or a [RoundedRectangleBorder] for cards and sliders.
  final ShapeBorder shape;

  /// Optional discrete action fired on Enter/Space/select while focused.
  final VoidCallback? onActivate;

  /// Gap between the child's bounds and the painted ring.
  final EdgeInsets padding;

  const NeuFocusRing({
    super.key,
    required this.child,
    this.shape = const StadiumBorder(),
    this.onActivate,
    this.padding = const EdgeInsets.all(6),
  });

  @override
  State<NeuFocusRing> createState() => _NeuFocusRingState();
}

class _NeuFocusRingState extends State<NeuFocusRing> {
  bool _showRing = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      mouseCursor: widget.onActivate != null
          ? SystemMouseCursors.click
          : MouseCursor.defer,
      actions: <Type, Action<Intent>>{
        if (widget.onActivate != null)
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onActivate!.call();
              return null;
            },
          ),
      },
      // Fires only for non-pointer focus (keyboard/D-pad/switch access).
      onShowFocusHighlight: (show) {
        if (show != _showRing) setState(() => _showRing = show);
      },
      child: CustomPaint(
        foregroundPainter:
            _showRing ? _FocusRingPainter(shape: widget.shape) : null,
        child: Padding(padding: widget.padding, child: widget.child),
      ),
    );
  }
}

class _FocusRingPainter extends CustomPainter {
  final ShapeBorder shape;
  _FocusRingPainter({required this.shape});

  @override
  void paint(Canvas canvas, Size size) {
    final path = shape.getOuterPath(Offset.zero & size);
    // Soft outer glow.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = NeuTokens.accent.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    // Crisp ring.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = NeuTokens.accent,
    );
  }

  @override
  bool shouldRepaint(_FocusRingPainter old) => old.shape != shape;
}
