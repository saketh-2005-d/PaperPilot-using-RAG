import 'package:flutter/material.dart';

import '../theme.dart';

/// Animated tesseract mark — a 4D-inspired hex-of-hexes built from strokes.
/// Uses Brand Green strokes on whatever background it sits on.
/// Set [animate] to false to render the final state immediately as a logo.
class TesseractMark extends StatefulWidget {
  final double size;
  final bool animate;
  final VoidCallback? onComplete;

  const TesseractMark({
    super.key,
    this.size = 240,
    this.animate = true,
    this.onComplete,
  });

  @override
  State<TesseractMark> createState() => _TesseractMarkState();
}

class _TesseractMarkState extends State<TesseractMark>
    with SingleTickerProviderStateMixin {
  static const _totalDuration = Duration(milliseconds: 2500);

  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: _totalDuration);
    if (widget.animate) {
      _ctrl.forward().whenComplete(() => widget.onComplete?.call());
    } else {
      _ctrl.value = 1.0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, _) => CustomPaint(
          painter: _TesseractPainter(seconds: _ctrl.value * 2.5),
        ),
      ),
    );
  }
}

class _TesseractPainter extends CustomPainter {
  final double seconds;

  _TesseractPainter({required this.seconds});

  // Outer hexagon corners (top-clockwise) and matching inner hexagon corners.
  static const _outer = [
    Offset(130, 40),
    Offset(208, 85),
    Offset(208, 175),
    Offset(130, 220),
    Offset(52, 175),
    Offset(52, 85),
  ];
  static const _inner = [
    Offset(130, 90),
    Offset(165, 110),
    Offset(165, 150),
    Offset(130, 170),
    Offset(95, 150),
    Offset(95, 110),
  ];
  static const _center = Offset(130, 130);

  static const _hexCurve = Cubic(0.4, 0.0, 0.2, 1.0);
  static const _popCurve = Cubic(0.34, 1.56, 0.64, 1.0);

  double _p(double start, double duration, Curve curve) {
    if (seconds <= start) return 0.0;
    if (seconds >= start + duration) return 1.0;
    return curve.transform((seconds - start) / duration);
  }

  void _drawHexProgress(Canvas canvas, List<Offset> pts, double progress, Paint paint) {
    if (progress <= 0) return;
    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (var i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }
    path.close();
    final metrics = path.computeMetrics().toList();
    final out = Path();
    for (final m in metrics) {
      out.addPath(m.extractPath(0, m.length * progress), Offset.zero);
    }
    canvas.drawPath(out, paint);
  }

  void _drawLineProgress(Canvas canvas, Offset a, Offset b, double progress, Paint paint) {
    if (progress <= 0) return;
    final end = Offset(a.dx + (b.dx - a.dx) * progress, a.dy + (b.dy - a.dy) * progress);
    canvas.drawLine(a, end, paint);
  }

  Paint _stroke(double width, double opacity) => Paint()
    ..color = brandGreen.withValues(alpha: opacity)
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  @override
  void paint(Canvas canvas, Size size) {
    // SVG viewBox is 260x260; scale into the available square.
    final scale = size.width / 260;
    canvas.save();
    canvas.scale(scale);

    // Outer hexagon (.oh) — 0 → 0.75s
    _drawHexProgress(canvas, _outer, _p(0, 0.75, _hexCurve), _stroke(2.5, 1.0));

    // Outer visible interior (.ov1..3) — center to corners 1,3,5, staggered 0.62/0.68/0.74
    const ovIdx = [1, 3, 5];
    const ovDelay = [0.62, 0.68, 0.74];
    for (var i = 0; i < 3; i++) {
      _drawLineProgress(
        canvas, _center, _outer[ovIdx[i]],
        _p(ovDelay[i], 0.38, Curves.ease), _stroke(2.0, 1.0),
      );
    }

    // Outer hidden interior (.ohd1..3) — center to corners 0,2,4
    const ohdIdx = [0, 2, 4];
    for (var i = 0; i < 3; i++) {
      _drawLineProgress(
        canvas, _center, _outer[ohdIdx[i]],
        _p(ovDelay[i], 0.38, Curves.ease), _stroke(1.2, 0.22),
      );
    }

    // Connecting lines (.cn1..6) — outer[k] ↔ inner[k]
    const cnDelay = [0.88, 0.93, 0.98, 1.03, 1.08, 1.13];
    for (var i = 0; i < 6; i++) {
      _drawLineProgress(
        canvas, _outer[i], _inner[i],
        _p(cnDelay[i], 0.32, Curves.ease), _stroke(1.6, 0.55),
      );
    }

    // Inner hexagon (.ih) — 1.2 → 1.78s
    _drawHexProgress(canvas, _inner, _p(1.2, 0.58, _hexCurve), _stroke(2.0, 0.82));

    // Inner visible interior (.iv1..3) — center to inner 1,3,5
    const ivDelay = [1.72, 1.78, 1.84];
    for (var i = 0; i < 3; i++) {
      _drawLineProgress(
        canvas, _center, _inner[ovIdx[i]],
        _p(ivDelay[i], 0.32, Curves.ease), _stroke(1.7, 0.76),
      );
    }
    // Inner hidden interior (.ihd1..3) — center to inner 0,2,4
    for (var i = 0; i < 3; i++) {
      _drawLineProgress(
        canvas, _center, _inner[ohdIdx[i]],
        _p(ivDelay[i], 0.32, Curves.ease), _stroke(1.0, 0.18),
      );
    }

    // Outer corner dots (r=4) and inner corner dots (r=3) — pop in
    const daDelay = [2.05, 2.08, 2.11, 2.14, 2.17, 2.20];
    const dbDelay = [2.10, 2.13, 2.16, 2.19, 2.22, 2.25];
    final dotPaint = Paint()..color = brandGreen..style = PaintingStyle.fill;
    for (var i = 0; i < 6; i++) {
      final s = _p(daDelay[i], 0.30, _popCurve);
      if (s > 0) canvas.drawCircle(_outer[i], 4.0 * s, dotPaint);
    }
    for (var i = 0; i < 6; i++) {
      final s = _p(dbDelay[i], 0.30, _popCurve);
      if (s > 0) canvas.drawCircle(_inner[i], 3.0 * s, dotPaint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TesseractPainter old) => old.seconds != seconds;
}
