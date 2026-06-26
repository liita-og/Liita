import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:liita/core/theme/app_theme.dart';
import 'package:liita/core/widgets/neu_focus_ring.dart';

// =============================================================================
// Neumorphic dial controls — pure StatefulWidget + CustomPainter.
//
// These are hand-painted (rather than built from the flutter_neumorphic_plus
// container) so the tick rings, needles, wedges and accent arcs can be placed
// with pixel precision to match the reference design. They share the soft-UI
// look via [NeuTokens] and the helpers below.
// =============================================================================

const double _shadowOffset = 5.0;
const MaskFilter _shadowBlur = MaskFilter.blur(BlurStyle.normal, 7.0);

/// Draws a raised (extruded) soft-UI circle: dark shadow bottom-right, light
/// highlight top-left, base fill on top.
void _raisedCircle(Canvas canvas, Offset c, double r, {Color? color}) {
  canvas.drawCircle(c.translate(_shadowOffset, _shadowOffset), r,
      Paint()..color = NeuTokens.darkShadow..maskFilter = _shadowBlur);
  canvas.drawCircle(c.translate(-_shadowOffset, -_shadowOffset), r,
      Paint()..color = NeuTokens.lightShadow..maskFilter = _shadowBlur);
  canvas.drawCircle(c, r, Paint()..color = color ?? NeuTokens.base);
}

/// Draws an inset (pressed-in) soft-UI circle.
void _insetCircle(Canvas canvas, Offset c, double r, {Color? color}) {
  canvas.drawCircle(c, r, Paint()..color = color ?? NeuTokens.base);
  canvas.save();
  canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));
  final stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = _shadowOffset * 2
    ..maskFilter = _shadowBlur;
  canvas.drawCircle(c.translate(-_shadowOffset, -_shadowOffset), r,
      stroke..color = NeuTokens.darkShadow);
  canvas.drawCircle(c.translate(_shadowOffset, _shadowOffset), r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _shadowOffset * 2
        ..maskFilter = _shadowBlur
        ..color = NeuTokens.lightShadow);
  canvas.restore();
}

/// Paints an [IconData] glyph centered at [center].
void _paintIcon(Canvas canvas, IconData icon, Offset center, double size,
    Color color) {
  final tp = TextPainter(
    textDirection: TextDirection.ltr,
    text: TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontSize: size,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        color: color,
      ),
    ),
  )..layout();
  tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
}

// =============================================================================
// 1. RotaryDialKnob — ring of ticks + concentric raised circles; snaps to N.
// =============================================================================

class RotaryDialKnob extends StatefulWidget {
  final int ticks;
  final int value;
  final double size;
  final ValueChanged<int>? onChanged;

  const RotaryDialKnob({
    super.key,
    this.ticks = 12,
    this.value = 0,
    this.size = 150,
    this.onChanged,
  });

  @override
  State<RotaryDialKnob> createState() => _RotaryDialKnobState();
}

class _RotaryDialKnobState extends State<RotaryDialKnob> {
  late double _angle = _angleFor(widget.value);

  double _angleFor(int i) => (2 * math.pi * i) / widget.ticks;

  void _updateFromPointer(Offset local) {
    final center = Offset(widget.size / 2, widget.size / 2);
    final v = local - center;
    var a = math.atan2(v.dx, -v.dy); // 0 at top, clockwise positive
    if (a < 0) a += 2 * math.pi;
    setState(() => _angle = a);
  }

  void _snap() {
    final step = 2 * math.pi / widget.ticks;
    final idx = ((_angle / step).round()) % widget.ticks;
    setState(() => _angle = idx * step);
    widget.onChanged?.call(idx);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Rotary dial',
      value: '${widget.value + 1} of ${widget.ticks}',
      child: NeuFocusRing(
        shape: const CircleBorder(),
        child: GestureDetector(
          onPanStart: (d) => _updateFromPointer(d.localPosition),
          onPanUpdate: (d) => _updateFromPointer(d.localPosition),
          onPanEnd: (_) => _snap(),
          child: CustomPaint(
            size: Size.square(widget.size),
            painter: _RotaryPainter(angle: _angle, ticks: widget.ticks),
          ),
        ),
      ),
    );
  }
}

class _RotaryPainter extends CustomPainter {
  final double angle;
  final int ticks;
  _RotaryPainter({required this.angle, required this.ticks});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final outer = size.width / 2 - _shadowOffset * 1.5;

    _raisedCircle(canvas, c, outer);

    // Tick ring.
    final tickPaint = Paint()
      ..color = NeuTokens.darkShadow.withValues(alpha: 0.5)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < ticks; i++) {
      final a = (2 * math.pi * i / ticks) - math.pi / 2;
      final p1 = c + Offset(math.cos(a), math.sin(a)) * (outer * 0.88);
      final p2 = c + Offset(math.cos(a), math.sin(a)) * (outer * 0.78);
      canvas.drawLine(p1, p2, tickPaint);
    }

    // Three concentric raised circles.
    _raisedCircle(canvas, c, outer * 0.66);
    _raisedCircle(canvas, c, outer * 0.46);
    _raisedCircle(canvas, c, outer * 0.26);

    // Indicator notch + center pivot.
    final ia = angle - math.pi / 2;
    final notch = c + Offset(math.cos(ia), math.sin(ia)) * (outer * 0.58);
    canvas.drawCircle(notch, 4, Paint()..color = NeuTokens.accent);
    _insetCircle(canvas, c, outer * 0.1);
  }

  @override
  bool shouldRepaint(_RotaryPainter old) =>
      old.angle != angle || old.ticks != ticks;
}

// =============================================================================
// 2. AccentRingKnob — big raised knob, blue ring, inner disc; 0..1 rotation.
// =============================================================================

class AccentRingKnob extends StatefulWidget {
  final double value; // 0..1
  final double size;
  final ValueChanged<double>? onChanged;

  const AccentRingKnob({
    super.key,
    this.value = 0.0,
    this.size = 150,
    this.onChanged,
  });

  @override
  State<AccentRingKnob> createState() => _AccentRingKnobState();
}

class _AccentRingKnobState extends State<AccentRingKnob> {
  void _updateFromPointer(Offset local) {
    final center = Offset(widget.size / 2, widget.size / 2);
    final v = local - center;
    var a = math.atan2(v.dx, -v.dy);
    if (a < 0) a += 2 * math.pi;
    widget.onChanged?.call(a / (2 * math.pi));
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Accent ring knob',
      value: '${(widget.value * 100).round()} percent',
      child: NeuFocusRing(
        shape: const CircleBorder(),
        child: GestureDetector(
          onPanStart: (d) => _updateFromPointer(d.localPosition),
          onPanUpdate: (d) => _updateFromPointer(d.localPosition),
          child: CustomPaint(
            size: Size.square(widget.size),
            painter: _AccentRingPainter(widget.value),
          ),
        ),
      ),
    );
  }
}

class _AccentRingPainter extends CustomPainter {
  final double value;
  _AccentRingPainter(this.value);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final outer = size.width / 2 - _shadowOffset * 1.5;

    _raisedCircle(canvas, c, outer);

    // Outer tick marks.
    final tickPaint = Paint()
      ..color = NeuTokens.darkShadow.withValues(alpha: 0.45)
      ..strokeWidth = 2;
    for (var i = 0; i < 24; i++) {
      final a = (2 * math.pi * i / 24) - math.pi / 2;
      final p1 = c + Offset(math.cos(a), math.sin(a)) * (outer * 0.92);
      final p2 = c + Offset(math.cos(a), math.sin(a)) * (outer * 0.84);
      canvas.drawLine(p1, p2, tickPaint);
    }

    // Blue accent ring (full track + active arc).
    final ringR = outer * 0.6;
    canvas.drawCircle(
        c,
        ringR,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..color = NeuTokens.accent.withValues(alpha: 0.25));
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: ringR),
      -math.pi / 2,
      2 * math.pi * value.clamp(0.0, 1.0),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round
        ..color = NeuTokens.accent,
    );

    // Inner raised disc + indicator.
    _raisedCircle(canvas, c, outer * 0.42);
    final ia = 2 * math.pi * value - math.pi / 2;
    final dot = c + Offset(math.cos(ia), math.sin(ia)) * ringR;
    canvas.drawCircle(dot, 5, Paint()..color = NeuTokens.accent);
  }

  @override
  bool shouldRepaint(_AccentRingPainter old) => old.value != value;
}

// =============================================================================
// 3. GaugeDial — thin blue needle, fixed tick at 12 o'clock, draggable.
// =============================================================================

class GaugeDial extends StatefulWidget {
  final double value; // 0..1 → full rotation
  final double size;
  final ValueChanged<double>? onChanged;

  const GaugeDial({
    super.key,
    this.value = 0.0,
    this.size = 150,
    this.onChanged,
  });

  @override
  State<GaugeDial> createState() => _GaugeDialState();
}

class _GaugeDialState extends State<GaugeDial> {
  void _updateFromPointer(Offset local) {
    final center = Offset(widget.size / 2, widget.size / 2);
    final v = local - center;
    var a = math.atan2(v.dx, -v.dy);
    if (a < 0) a += 2 * math.pi;
    widget.onChanged?.call(a / (2 * math.pi));
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Gauge dial',
      value: '${(widget.value * 100).round()} percent',
      child: NeuFocusRing(
        shape: const CircleBorder(),
        child: GestureDetector(
          onPanStart: (d) => _updateFromPointer(d.localPosition),
          onPanUpdate: (d) => _updateFromPointer(d.localPosition),
          child: CustomPaint(
            size: Size.square(widget.size),
            painter: _GaugePainter(widget.value),
          ),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double value;
  _GaugePainter(this.value);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final outer = size.width / 2 - _shadowOffset * 1.5;

    _raisedCircle(canvas, c, outer);

    // Fixed tick at 12 o'clock.
    canvas.drawLine(
      c + Offset(0, -outer * 0.9),
      c + Offset(0, -outer * 0.72),
      Paint()
        ..color = NeuTokens.accent
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );

    // Needle.
    final a = 2 * math.pi * value - math.pi / 2;
    final tip = c + Offset(math.cos(a), math.sin(a)) * (outer * 0.72);
    canvas.drawLine(
      c,
      tip,
      Paint()
        ..color = NeuTokens.accent
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(c, 5, Paint()..color = NeuTokens.text);
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.value != value;
}

// =============================================================================
// 4. PieSegmentSelector — icon wedges; selected wedge fills accent.
// =============================================================================

class PieSegmentSelector extends StatelessWidget {
  final List<IconData> icons;
  final int selectedIndex;
  final double size;
  final ValueChanged<int>? onChanged;

  const PieSegmentSelector({
    super.key,
    required this.icons,
    this.selectedIndex = 0,
    this.size = 150,
    this.onChanged,
  });

  void _handleTap(Offset local) {
    final center = Offset(size / 2, size / 2);
    final v = local - center;
    var a = math.atan2(v.dx, -v.dy);
    if (a < 0) a += 2 * math.pi;
    final idx = (a / (2 * math.pi) * icons.length).floor() % icons.length;
    onChanged?.call(idx);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Pie segment selector',
      value: 'segment ${selectedIndex + 1} of ${icons.length}',
      child: NeuFocusRing(
        shape: const CircleBorder(),
        child: GestureDetector(
          onTapDown: (d) => _handleTap(d.localPosition),
          child: CustomPaint(
            size: Size.square(size),
            painter: _PiePainter(icons: icons, selected: selectedIndex),
          ),
        ),
      ),
    );
  }
}

class _PiePainter extends CustomPainter {
  final List<IconData> icons;
  final int selected;
  _PiePainter({required this.icons, required this.selected});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final outer = size.width / 2 - _shadowOffset * 1.5;
    final n = icons.length;
    final sweep = 2 * math.pi / n;

    _raisedCircle(canvas, c, outer);

    // Selected wedge fill.
    if (selected >= 0 && selected < n) {
      final start = selected * sweep - math.pi / 2;
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: outer * 0.92),
        start,
        sweep,
        true,
        Paint()..color = NeuTokens.accent,
      );
    }

    // Dividers + icons.
    final divider = Paint()
      ..color = NeuTokens.darkShadow.withValues(alpha: 0.4)
      ..strokeWidth = 1.5;
    for (var i = 0; i < n; i++) {
      final a = i * sweep - math.pi / 2;
      canvas.drawLine(
          c, c + Offset(math.cos(a), math.sin(a)) * (outer * 0.92), divider);

      final mid = (i + 0.5) * sweep - math.pi / 2;
      final iconPos = c + Offset(math.cos(mid), math.sin(mid)) * (outer * 0.6);
      _paintIcon(canvas, icons[i], iconPos, 18,
          i == selected ? Colors.white : NeuTokens.text);
    }
  }

  @override
  bool shouldRepaint(_PiePainter old) =>
      old.selected != selected || old.icons != icons;
}

// =============================================================================
// 5. DotGridSelector — NxM grid of circles toggling neutral/accent.
// =============================================================================

class DotGridSelector extends StatelessWidget {
  final int rows;
  final int cols;
  final Set<int> selected;
  final double size;
  final ValueChanged<Set<int>>? onChanged;

  const DotGridSelector({
    super.key,
    this.rows = 3,
    this.cols = 3,
    this.selected = const {},
    this.size = 150,
    this.onChanged,
  });

  void _handleTap(Offset local) {
    final cellW = size / cols;
    final cellH = size / rows;
    final col = (local.dx / cellW).floor().clamp(0, cols - 1);
    final row = (local.dy / cellH).floor().clamp(0, rows - 1);
    final index = row * cols + col;
    final next = Set<int>.from(selected);
    next.contains(index) ? next.remove(index) : next.add(index);
    onChanged?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Dot grid selector',
      value: '${selected.length} of ${rows * cols} selected',
      child: NeuFocusRing(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: GestureDetector(
          onTapDown: (d) => _handleTap(d.localPosition),
          child: CustomPaint(
            size: Size.square(size),
            painter: _DotGridPainter(rows: rows, cols: cols, selected: selected),
          ),
        ),
      ),
    );
  }
}

class _DotGridPainter extends CustomPainter {
  final int rows;
  final int cols;
  final Set<int> selected;
  _DotGridPainter({required this.rows, required this.cols, required this.selected});

  @override
  void paint(Canvas canvas, Size size) {
    final cellW = size.width / cols;
    final cellH = size.height / rows;
    final r = math.min(cellW, cellH) * 0.32;
    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        final index = row * cols + col;
        final c = Offset((col + 0.5) * cellW, (row + 0.5) * cellH);
        if (selected.contains(index)) {
          canvas.drawCircle(c, r, Paint()..color = NeuTokens.accent);
        } else {
          _raisedCircle(canvas, c, r);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_DotGridPainter old) =>
      old.selected != selected || old.rows != rows || old.cols != cols;
}
