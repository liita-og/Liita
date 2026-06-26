import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:liita/core/theme/app_theme.dart';
import 'package:liita/core/widgets/neumorphic_dials.dart';

/// A standalone neumorphic (soft-UI) component showcase.
///
/// Deliberately LIGHT-themed and self-contained — it wraps its own subtree in a
/// scoped [NeumorphicTheme] (built from [NeuTokens]) rather than touching the
/// app-wide dark theme. Reached via a temporary debug entry on the Profile tab.
/// All callbacks are local/stubbed; nothing here touches mesh or app logic.
class ShowcaseScreen extends ConsumerStatefulWidget {
  const ShowcaseScreen({super.key});

  @override
  ConsumerState<ShowcaseScreen> createState() => _ShowcaseScreenState();
}

class _ShowcaseScreenState extends ConsumerState<ShowcaseScreen> {
  // ── Local control state (ephemeral demo values) ──
  int _rotaryIdx = 0;
  double _ringVal = 0.32;
  double _gaugeVal = 0.12;
  int _pieIdx = 1;
  Set<int> _dots = {0, 4, 8};
  int _yesNo = 0;
  double _slider = 4;
  double _fader = 0.6;
  double _thinSlider = 0.4;
  bool _switch1 = true;
  bool _switch2 = false;
  bool _dropdownOpen = false;
  int _dropdownSel = 2;
  String _lastAction = '—';

  static const _dropdownItems = ['One', 'Two', 'Three', 'Four'];
  static const _pieIcons = [
    Icons.water_drop,
    Icons.wb_sunny,
    Icons.cloud,
    Icons.ac_unit,
    Icons.air,
    Icons.umbrella,
  ];

  void _action(String label) => setState(() => _lastAction = label);

  @override
  Widget build(BuildContext context) {
    return NeumorphicTheme(
      // Force light: this is a light soft-UI surface regardless of the device's
      // system dark mode (which would otherwise select the package's dark theme).
      themeMode: ThemeMode.light,
      theme: const NeumorphicThemeData(
        baseColor: NeuTokens.base,
        accentColor: NeuTokens.accent,
        variantColor: NeuTokens.darkShadow,
        defaultTextColor: NeuTokens.text,
        lightSource: LightSource.topLeft,
        depth: 6,
        intensity: 0.65,
        shadowLightColor: NeuTokens.lightShadow,
        shadowDarkColor: NeuTokens.darkShadow,
      ),
      child: Scaffold(
        backgroundColor: NeuTokens.base,
        appBar: AppBar(
          backgroundColor: NeuTokens.base,
          foregroundColor: NeuTokens.text,
          elevation: 0,
          title: const Text('Neumorphic Showcase',
              style: TextStyle(
                  color: NeuTokens.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w600)),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _group('Dials & knobs', [
                _panel('Rotary', RotaryDialKnob(
                  value: _rotaryIdx,
                  onChanged: (v) => setState(() => _rotaryIdx = v),
                )),
                _panel('Accent ring', AccentRingKnob(
                  value: _ringVal,
                  onChanged: (v) => setState(() => _ringVal = v),
                )),
                _panel('Dot grid', DotGridSelector(
                  selected: _dots,
                  onChanged: (s) => setState(() => _dots = s),
                )),
                _panel('Segments', PieSegmentSelector(
                  icons: _pieIcons,
                  selectedIndex: _pieIdx,
                  onChanged: (v) => setState(() => _pieIdx = v),
                )),
                _panel('Gauge', GaugeDial(
                  value: _gaugeVal,
                  onChanged: (v) => setState(() => _gaugeVal = v),
                )),
              ]),
              _group('Toggles & buttons', [
                _panel('Pill toggle', _yesNoToggle(), auto: true),
                _panel('Segmented', _acceptCancel(), auto: true),
                _panel('Switches', _switches(), auto: true),
                _panel('Transport', _transportRow(), auto: true),
              ]),
              _panel('Icon buttons', _iconRow(), full: true),
              _group('Sliders & inputs', [
                _panel('Slider', _tickSlider(), full: true),
                _panel('Thin slider', _thinSliderWidget(), full: true),
                _panel('Progress', _progressSlider(), full: true),
                _panel('Text field', _pillField(), full: true),
                _panel('Fader', _verticalFader()),
              ]),
              _group('Popup & dropdown', [
                _panel('Popup', _popupCard(), full: true),
                _panel('Dropdown', _dropdown(), full: true),
              ]),
              const SizedBox(height: 8),
              Text('Last action: $_lastAction',
                  style: const TextStyle(color: NeuTokens.text, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  // ── Layout helpers ──────────────────────────────────────────────────────

  Widget _group(String title, List<Widget> children) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 20, bottom: 8),
            child: Text(title,
                style: const TextStyle(
                    color: NeuTokens.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5)),
          ),
          Wrap(spacing: 18, runSpacing: 18, children: children),
        ],
      );

  /// A labelled demo cell. [full] = full width; [auto] = size to content
  /// (for variable-width components); otherwise a fixed 150px square cell.
  Widget _panel(String label, Widget child, {bool full = false, bool auto = false}) {
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        child,
        const SizedBox(height: 8),
        Text(label,
            style: const TextStyle(
                color: NeuTokens.text, fontSize: 11, height: 1.2)),
      ],
    );
    if (auto) return column;
    return SizedBox(width: full ? double.infinity : 150, child: column);
  }

  // ── Section 2: standard components ──────────────────────────────────────

  Widget _yesNoToggle() {
    Widget label(String t, Color c) =>
        Center(child: Text(t, style: TextStyle(color: c, fontWeight: FontWeight.w600)));
    return Semantics(
      label: 'Yes or No toggle',
      value: _yesNo == 0 ? 'Yes' : 'No',
      child: NeumorphicToggle(
        height: 44,
        width: 150,
        selectedIndex: _yesNo,
        onChanged: (i) => setState(() => _yesNo = i),
        style: NeumorphicToggleStyle(
            borderRadius: BorderRadius.circular(NeuTokens.pillRadius)),
        thumb: Neumorphic(
          style: NeumorphicStyle(
            boxShape: NeumorphicBoxShape.roundRect(
                BorderRadius.circular(NeuTokens.pillRadius)),
          ),
        ),
        children: [
          ToggleElement(
            background: label('Yes', NeuTokens.text),
            foreground: label('Yes', NeuTokens.accent),
          ),
          ToggleElement(
            background: label('No', NeuTokens.text),
            foreground: label('No', NeuTokens.accent),
          ),
        ],
      ),
    );
  }

  Widget _acceptCancel() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        NeumorphicButton(
          onPressed: () => _action('Accept'),
          tooltip: 'Accept',
          style: NeumorphicStyle(
              boxShape: NeumorphicBoxShape.roundRect(
                  const BorderRadius.horizontal(left: Radius.circular(14)))),
          child: const Text('Accept', style: TextStyle(color: NeuTokens.text)),
        ),
        NeumorphicButton(
          onPressed: () => _action('Cancel'),
          tooltip: 'Cancel',
          style: NeumorphicStyle(
              color: NeuTokens.accent,
              boxShape: NeumorphicBoxShape.roundRect(
                  const BorderRadius.horizontal(right: Radius.circular(14)))),
          child: const Text('Cancel', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  Widget _switches() => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            label: 'Switch one',
            toggled: _switch1,
            child: NeumorphicSwitch(
              value: _switch1,
              onChanged: (v) => setState(() => _switch1 = v),
              style: const NeumorphicSwitchStyle(thumbShape: NeumorphicShape.concave),
            ),
          ),
          const SizedBox(width: 16),
          Semantics(
            label: 'Switch two',
            toggled: _switch2,
            child: NeumorphicSwitch(
              value: _switch2,
              onChanged: (v) => setState(() => _switch2 = v),
            ),
          ),
        ],
      );

  Widget _circleIconButton(IconData icon, String label, {Color? color}) =>
      NeumorphicButton(
        onPressed: () => _action(label),
        tooltip: label,
        padding: const EdgeInsets.all(14),
        style: NeumorphicStyle(
          boxShape: const NeumorphicBoxShape.circle(),
          color: color,
        ),
        child: Icon(icon, size: 20, color: color != null ? Colors.white : NeuTokens.text),
      );

  Widget _transportRow() => Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icons.fast_forward,
          Icons.play_arrow,
          Icons.stop,
          Icons.pause,
        ]
            .map((i) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _TransportButton(icon: i),
                ))
            .toList(),
      );

  Widget _iconRow() => Wrap(
        spacing: 12,
        runSpacing: 12,
        alignment: WrapAlignment.center,
        children: [
          _circleIconButton(Icons.chevron_right, 'Next'),
          _circleIconButton(Icons.home, 'Home'),
          _circleIconButton(Icons.thumb_up, 'Like'),
          _circleIconButton(Icons.arrow_forward, 'Forward'),
          _circleIconButton(Icons.block, 'Block'),
          _circleIconButton(Icons.close, 'Close'),
          _circleIconButton(Icons.info_outline, 'Info'),
          _circleIconButton(Icons.more_horiz, 'More'),
        ],
      );

  // ── Section 3: sliders & inputs ─────────────────────────────────────────

  Widget _tickSlider() => Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _TickBarPainter(count: 24)),
          ),
          NeumorphicSlider(
            min: 0,
            max: 10,
            value: _slider,
            height: 16,
            onChanged: (v) => setState(() => _slider = v),
          ),
        ],
      );

  Widget _thinSliderWidget() => SliderTheme(
        data: SliderThemeData(
          trackHeight: 2,
          activeTrackColor: NeuTokens.accent,
          inactiveTrackColor: NeuTokens.darkShadow.withValues(alpha: 0.4),
          thumbColor: NeuTokens.accent,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        ),
        child: Slider(
          value: _thinSlider,
          onChanged: (v) => setState(() => _thinSlider = v),
        ),
      );

  Widget _progressSlider() => NeumorphicSlider(
        min: 0,
        max: 10,
        value: 8.6,
        height: 18,
        onChanged: (_) {},
      );

  Widget _pillField() => Neumorphic(
        style: NeumorphicStyle(
          depth: -4,
          boxShape: NeumorphicBoxShape.roundRect(
              BorderRadius.circular(NeuTokens.pillRadius)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 2),
        child: const TextField(
          decoration: InputDecoration(
            border: InputBorder.none,
            hintText: 'Name',
            hintStyle: TextStyle(color: NeuTokens.text),
          ),
          style: TextStyle(color: NeuTokens.text),
        ),
      );

  Widget _verticalFader() => SizedBox(
        height: 170,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            RotatedBox(
              quarterTurns: 3,
              child: SizedBox(
                width: 150,
                child: NeumorphicSlider(
                  value: _fader,
                  min: 0,
                  max: 1,
                  height: 16,
                  onChanged: (v) => setState(() => _fader = v),
                ),
              ),
            ),
            const SizedBox(width: 12),
            CustomPaint(size: const Size(18, 150), painter: _FaderMarksPainter()),
          ],
        ),
      );

  // ── Section 4: popup & dropdown ─────────────────────────────────────────

  Widget _popupCard() => Neumorphic(
        style: NeumorphicStyle(
          boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Text('Pop Up',
                    style: TextStyle(
                        color: NeuTokens.text,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close, color: NeuTokens.text, size: 20),
                  onPressed: () => _action('Close popup'),
                ),
              ],
            ),
            const Text(
              'Lorem ipsum dolor sit amet, consectetuer adipiscing elit, sed diam nonummy nibh euismod tincidunt ut laoreet.',
              style: TextStyle(
                  color: NeuTokens.text,
                  fontStyle: FontStyle.italic,
                  fontSize: 13,
                  height: 1.4),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: NeumorphicButton(
                onPressed: () => _action('Learn more'),
                tooltip: 'Learn more',
                style: NeumorphicStyle(
                  color: NeuTokens.accent,
                  boxShape:
                      NeumorphicBoxShape.roundRect(BorderRadius.circular(12)),
                ),
                child: const Text('Learn more',
                    style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      );

  Widget _dropdown() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          expanded: _dropdownOpen,
          label: 'Dropdown, selected ${_dropdownItems[_dropdownSel]}',
          child: GestureDetector(
            onTap: () => setState(() => _dropdownOpen = !_dropdownOpen),
            child: Neumorphic(
              style: NeumorphicStyle(
                boxShape: NeumorphicBoxShape.roundRect(
                    BorderRadius.circular(NeuTokens.pillRadius)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
              child: Row(
                children: [
                  Text(_dropdownItems[_dropdownSel],
                      style: const TextStyle(color: NeuTokens.text)),
                  const Spacer(),
                  AnimatedRotation(
                    turns: _dropdownOpen ? 0.25 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.chevron_right,
                        color: NeuTokens.text, size: 20),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child: _dropdownOpen
              ? Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Neumorphic(
                    style: NeumorphicStyle(
                      depth: -3,
                      boxShape:
                          NeumorphicBoxShape.roundRect(BorderRadius.circular(16)),
                    ),
                    child: Column(
                      children: List.generate(_dropdownItems.length, (i) {
                        final selected = i == _dropdownSel;
                        return InkWell(
                          onTap: () => setState(() {
                            _dropdownSel = i;
                            _dropdownOpen = false;
                          }),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 14),
                            decoration: BoxDecoration(
                              color: selected ? NeuTokens.accent : null,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(_dropdownItems[i],
                                style: TextStyle(
                                    color: selected
                                        ? Colors.white
                                        : NeuTokens.text)),
                          ),
                        );
                      }),
                    ),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

// ── Small painted overlays ────────────────────────────────────────────────

class _TransportButton extends StatelessWidget {
  final IconData icon;
  const _TransportButton({required this.icon});

  @override
  Widget build(BuildContext context) => NeumorphicButton(
        onPressed: () {},
        tooltip: icon.toString(),
        padding: const EdgeInsets.all(14),
        style: const NeumorphicStyle(boxShape: NeumorphicBoxShape.circle()),
        child: Icon(icon, size: 20, color: NeuTokens.text),
      );
}

class _TickBarPainter extends CustomPainter {
  final int count;
  _TickBarPainter({required this.count});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = NeuTokens.darkShadow.withValues(alpha: 0.5)
      ..strokeWidth = 1.5;
    for (var i = 0; i <= count; i++) {
      final x = size.width * i / count;
      canvas.drawLine(
          Offset(x, size.height * 0.3), Offset(x, size.height * 0.7), paint);
    }
  }

  @override
  bool shouldRepaint(_TickBarPainter old) => old.count != count;
}

class _FaderMarksPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = NeuTokens.accent
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    // Bracket line.
    canvas.drawLine(Offset(size.width * 0.5, 6),
        Offset(size.width * 0.5, size.height - 6), paint);
    // Preset dots.
    final dot = Paint()..color = NeuTokens.accent;
    for (final t in [0.1, 0.35, 0.6, 0.85]) {
      canvas.drawCircle(Offset(size.width * 0.5, size.height * t), 3, dot);
    }
  }

  @override
  bool shouldRepaint(_FaderMarksPainter old) => false;
}
