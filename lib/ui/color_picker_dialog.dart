import 'package:flutter/material.dart';
import 'package:inkpad/engine/renderer/document_painter.dart';

/// Packs a Flutter [Color] into the 0xRRGGBBAA int the models use.
int rgbaFromColor(Color color) {
  int channel(double v) => (v * 255).round() & 0xFF;
  return (channel(color.r) << 24) |
      (channel(color.g) << 16) |
      (channel(color.b) << 8) |
      channel(color.a);
}

/// An HSV colour picker: a saturation/value square above a hue slider.
///
/// Returns the picked colour as 0xRRGGBBAA, or `null` if cancelled.
Future<int?> showColorPickerDialog(
  BuildContext context, {
  required int initialRGBA,
}) => showDialog<int>(
  context: context,
  builder: (context) => ColorPickerDialog(initialRGBA: initialRGBA),
);

class ColorPickerDialog extends StatefulWidget {
  const ColorPickerDialog({required this.initialRGBA, super.key});

  final int initialRGBA;

  @override
  State<ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<ColorPickerDialog> {
  late HSVColor _hsv = HSVColor.fromColor(colorFromRGBA(widget.initialRGBA));

  Color get _color => _hsv.toColor();

  void _setSaturationValue(Offset local, Size size) {
    setState(() {
      _hsv = _hsv
          .withSaturation((local.dx / size.width).clamp(0.0, 1.0))
          .withValue(1 - (local.dy / size.height).clamp(0.0, 1.0));
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Custom colour'),
      content: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 180,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = constraints.biggest;
                  return GestureDetector(
                    key: const Key('sv-square'),
                    behavior: HitTestBehavior.opaque,
                    onPanDown: (d) =>
                        _setSaturationValue(d.localPosition, size),
                    onPanUpdate: (d) =>
                        _setSaturationValue(d.localPosition, size),
                    child: CustomPaint(
                      painter: _SaturationValuePainter(hue: _hsv.hue),
                      child: _Reticle(hsv: _hsv, size: size),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            _HueSlider(
              hue: _hsv.hue,
              onChanged: (hue) => setState(() => _hsv = _hsv.withHue(hue)),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  key: const Key('color-preview'),
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _color,
                    shape: BoxShape.circle,
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '#${rgbaFromColor(_color).toRadixString(16).padLeft(8, '0').substring(0, 6).toUpperCase()}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('color-picker-ok'),
          onPressed: () => Navigator.of(context).pop(rgbaFromColor(_color)),
          child: const Text('Select'),
        ),
      ],
    );
  }
}

/// White-to-hue horizontally, transparent-to-black vertically.
class _SaturationValuePainter extends CustomPainter {
  const _SaturationValuePainter({required this.hue});

  final double hue;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [Colors.white, HSVColor.fromAHSV(1, hue, 1, 1).toColor()],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_SaturationValuePainter old) => old.hue != hue;
}

class _Reticle extends StatelessWidget {
  const _Reticle({required this.hsv, required this.size});

  final HSVColor hsv;
  final Size size;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          left: hsv.saturation * size.width - 8,
          top: (1 - hsv.value) * size.height - 8,
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [
                BoxShadow(color: Colors.black38, blurRadius: 2),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HueSlider extends StatelessWidget {
  const _HueSlider({required this.hue, required this.onChanged});

  final double hue;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Container(
              height: 12,
              decoration: const BoxDecoration(
                borderRadius: BorderRadius.all(Radius.circular(6)),
                gradient: LinearGradient(
                  colors: [
                    Color(0xFFFF0000),
                    Color(0xFFFFFF00),
                    Color(0xFF00FF00),
                    Color(0xFF00FFFF),
                    Color(0xFF0000FF),
                    Color(0xFFFF00FF),
                    Color(0xFFFF0000),
                  ],
                ),
              ),
            ),
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: Colors.transparent,
              inactiveTrackColor: Colors.transparent,
              thumbColor: Colors.white,
              overlayColor: Colors.black12,
            ),
            child: Slider(
              key: const Key('hue-slider'),
              max: 360,
              value: hue,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
