import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

class CanvasEditorPage extends StatefulWidget {
  const CanvasEditorPage({super.key});

  @override
  State<CanvasEditorPage> createState() => _CanvasEditorPageState();
}

class _CanvasEditorPageState extends State<CanvasEditorPage> {
  final List<_CanvasStroke> strokes = [];
  _CanvasStroke? activeStroke;
  Color penColor = const Color(0xFF202124);
  double penWidth = 4;
  bool eraser = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Canvas'),
        actions: [
          IconButton(
            tooltip: 'Undo',
            onPressed: strokes.isEmpty ? null : () => setState(() => strokes.removeLast()),
            icon: const Icon(Icons.undo_rounded),
          ),
          IconButton(
            tooltip: 'Clear',
            onPressed: strokes.isEmpty ? null : () => setState(strokes.clear),
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surface,
              child: Listener(
                onPointerDown: _pointerDown,
                onPointerMove: _pointerMove,
                onPointerUp: _pointerUp,
                onPointerCancel: _pointerCancel,
                child: CustomPaint(
                  painter: _CanvasPainter(
                    strokes: strokes,
                    activeStroke: activeStroke,
                    background: Theme.of(context).colorScheme.surface,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 16,
            child: SafeArea(
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(20),
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: eraser ? 'Pen' : 'Eraser',
                        onPressed: () => setState(() => eraser = !eraser),
                        icon: Icon(eraser ? Icons.edit_rounded : Icons.auto_fix_high_outlined),
                      ),
                      IconButton(
                        tooltip: 'Pen color',
                        onPressed: _chooseColor,
                        icon: Icon(Icons.circle, color: penColor),
                      ),
                      Expanded(
                        child: Slider(
                          min: 1,
                          max: 18,
                          value: penWidth,
                          label: penWidth.toStringAsFixed(0),
                          onChanged: (value) => setState(() => penWidth = value),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Add text',
                        onPressed: () {},
                        icon: const Icon(Icons.text_fields_rounded),
                      ),
                      IconButton(
                        tooltip: 'Add image',
                        onPressed: () {},
                        icon: const Icon(Icons.image_outlined),
                      ),
                      IconButton(
                        tooltip: 'More tools',
                        onPressed: () {},
                        icon: const Icon(Icons.more_horiz_rounded),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _pointerDown(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.mouse && event.buttons != kPrimaryButton) return;
    if (eraser) {
      _eraseNear(event.localPosition);
      return;
    }
    final pressure = event.pressure.isFinite ? event.pressure.clamp(0.1, 1.0).toDouble() : 1;
    setState(() {
      activeStroke = _CanvasStroke(
        points: [_CanvasPoint(event.localPosition, pressure)],
        color: penColor,
        width: penWidth,
      );
    });
  }

  void _pointerMove(PointerMoveEvent event) {
    if (eraser) {
      _eraseNear(event.localPosition);
      return;
    }
    final stroke = activeStroke;
    if (stroke == null) return;
    setState(() {
      stroke.points.add(
        _CanvasPoint(
          event.localPosition,
          event.pressure.isFinite ? event.pressure.clamp(0.1, 1.0).toDouble() : 1,
        ),
      );
    });
  }

  void _pointerUp(PointerUpEvent event) {
    final stroke = activeStroke;
    if (stroke == null) return;
    setState(() {
      if (stroke.points.length > 1) strokes.add(stroke);
      activeStroke = null;
    });
  }

  void _pointerCancel(PointerCancelEvent event) {
    setState(() => activeStroke = null);
  }

  void _eraseNear(Offset point) {
    setState(() {
      strokes.removeWhere((stroke) {
        return stroke.points.any((p) => (p.position - point).distance < penWidth * 3);
      });
    });
  }

  Future<void> _chooseColor() async {
    final colors = <Color>[
      const Color(0xFF202124),
      const Color(0xFFB3261E),
      const Color(0xFF146C2E),
      const Color(0xFF175CD3),
      const Color(0xFF7A5AF8),
      const Color(0xFFE06C00),
    ];
    final selected = await showModalBottomSheet<Color>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Wrap(
            spacing: 18,
            runSpacing: 18,
            children: colors
                .map(
                  (color) => InkWell(
                    onTap: () => Navigator.pop(context, color),
                    borderRadius: BorderRadius.circular(30),
                    child: CircleAvatar(backgroundColor: color, radius: 24),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
    if (selected != null) setState(() => penColor = selected);
  }
}

class _CanvasPoint {
  _CanvasPoint(this.position, this.pressure);

  final Offset position;
  final double pressure;
}

class _CanvasStroke {
  _CanvasStroke({
    required this.points,
    required this.color,
    required this.width,
  });

  final List<_CanvasPoint> points;
  final Color color;
  final double width;
}

class _CanvasPainter extends CustomPainter {
  const _CanvasPainter({
    required this.strokes,
    required this.activeStroke,
    required this.background,
  });

  final List<_CanvasStroke> strokes;
  final _CanvasStroke? activeStroke;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final stroke in [...strokes, if (activeStroke != null) activeStroke!]) {
      paint
        ..color = stroke.color
        ..strokeWidth = stroke.width;
      if (stroke.points.length == 1) {
        canvas.drawCircle(stroke.points.first.position, stroke.width / 2, paint..style = PaintingStyle.fill);
        paint.style = PaintingStyle.stroke;
        continue;
      }
      final path = Path()..moveTo(stroke.points.first.position.dx, stroke.points.first.position.dy);
      for (var i = 1; i < stroke.points.length; i++) {
        final p = stroke.points[i].position;
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_CanvasPainter oldDelegate) {
    return oldDelegate.strokes != strokes || oldDelegate.activeStroke != activeStroke;
  }
}
