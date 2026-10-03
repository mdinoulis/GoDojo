import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:go_core/go_core.dart';

import '../settings.dart';

/// Renders stones. Each look is recorded once per radius into a [ui.Picture]
/// and reused, so a full 19x19 board repaints cheaply.
class StoneRenderer {
  static const shellVariants = 12;
  final Map<String, ui.Picture> _cache = {};

  void draw(Canvas canvas, Offset c, double r, Stone colour, StoneStyle style,
      {int variant = 0, double opacity = 1, bool shadow = true}) {
    if (shadow && opacity >= 1 && style != StoneStyle.flat) {
      canvas.drawCircle(
        c + Offset(r * 0.07, r * 0.12),
        r * 0.97,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.32)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.10),
      );
    }
    final v = colour == Stone.white && style == StoneStyle.slateShell
        ? variant % shellVariants
        : 0;
    final key = '${style.name}-${colour.name}-$v-${r.toStringAsFixed(2)}';
    final pic = _cache[key] ??= _record(r, colour, style, v);
    canvas.save();
    canvas.translate(c.dx - r, c.dy - r);
    if (opacity < 1) {
      canvas.saveLayer(Rect.fromLTWH(0, 0, r * 2, r * 2),
          Paint()..color = Colors.white.withValues(alpha: opacity));
      canvas.drawPicture(pic);
      canvas.restore();
    } else {
      canvas.drawPicture(pic);
    }
    canvas.restore();
  }

  ui.Picture _record(double r, Stone colour, StoneStyle style, int variant) {
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    final c = Offset(r, r);
    final rect = Rect.fromCircle(center: c, radius: r);
    switch (style) {
      case StoneStyle.slateShell:
        colour == Stone.black
            ? _slate(canvas, c, r, rect)
            : _shell(canvas, c, r, rect, variant);
      case StoneStyle.glossy:
        _glossy(canvas, c, r, rect, colour);
      case StoneStyle.flat:
        canvas.drawCircle(c, r * 0.96,
            Paint()..color = colour == Stone.black ? const Color(0xFF151515) : const Color(0xFFF7F7F7));
        canvas.drawCircle(
            c,
            r * 0.96,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = max(1, r * 0.05)
              ..color = const Color(0xFF000000));
    }
    return rec.endRecording();
  }

  /// Matte slate: dark charcoal with a soft, broad sheen.
  void _slate(Canvas canvas, Offset c, double r, Rect rect) {
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.35, -0.4),
          radius: 1.05,
          colors: [Color(0xFF5E5E5E), Color(0xFF2B2B2B), Color(0xFF0B0B0B)],
          stops: [0.0, 0.38, 1.0],
        ).createShader(rect),
    );
    // Faint slate texture.
    final rnd = Random(11);
    final p = Paint()..color = Colors.white.withValues(alpha: 0.025);
    canvas.save();
    canvas.clipPath(Path()..addOval(rect));
    for (var i = 0; i < 60; i++) {
      final a = rnd.nextDouble() * 2 * pi, d = sqrt(rnd.nextDouble()) * r;
      canvas.drawCircle(c + Offset(cos(a) * d, sin(a) * d), r * 0.05, p);
    }
    canvas.restore();
    canvas.drawCircle(
      c + Offset(-r * 0.32, -r * 0.36),
      r * 0.32,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.07)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.18),
    );
  }

  /// Clamshell: warm white with fine curved growth stripes.
  void _shell(Canvas canvas, Offset c, double r, Rect rect, int variant) {
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.3, -0.35),
          radius: 1.0,
          colors: [Color(0xFFFFFFFF), Color(0xFFF3F1EA), Color(0xFFD4CFC4)],
          stops: [0.0, 0.62, 1.0],
        ).createShader(rect),
    );
    final rnd = Random(1000 + variant);
    canvas.save();
    canvas.clipPath(Path()..addOval(rect));
    canvas.translate(c.dx, c.dy);
    canvas.rotate(rnd.nextDouble() * pi);
    final stripes = 12 + rnd.nextInt(8);
    var y = -r * 1.1;
    final bow = r * (0.06 + rnd.nextDouble() * 0.12);
    for (var i = 0; i < stripes && y < r * 1.1; i++) {
      y += r * (0.07 + rnd.nextDouble() * 0.12);
      final path = Path()
        ..moveTo(-r * 1.2, y)
        ..quadraticBezierTo(0, y + bow, r * 1.2, y);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * (0.01 + rnd.nextDouble() * 0.025)
          ..color = const Color(0xFFA9A193)
              .withValues(alpha: 0.05 + rnd.nextDouble() * 0.10),
      );
    }
    canvas.restore();
    // Re-shade the edge so the stripes sit "inside" a domed stone.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.35),
          radius: 1.0,
          colors: [Colors.white.withValues(alpha: 0.0), Colors.black.withValues(alpha: 0.10)],
          stops: const [0.65, 1.0],
        ).createShader(rect),
    );
    canvas.drawCircle(
      c + Offset(-r * 0.3, -r * 0.35),
      r * 0.25,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.15),
    );
  }

  void _glossy(Canvas canvas, Offset c, double r, Rect rect, Stone colour) {
    final black = colour == Stone.black;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.4),
          radius: 1.0,
          colors: black
              ? const [Color(0xFF777777), Color(0xFF1C1C1C), Color(0xFF000000)]
              : const [Color(0xFFFFFFFF), Color(0xFFE9E9E9), Color(0xFFB9B9B9)],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(rect),
    );
    canvas.drawOval(
      Rect.fromCenter(
          center: c + Offset(-r * 0.3, -r * 0.42), width: r * 0.7, height: r * 0.4),
      Paint()
        ..color = Colors.white.withValues(alpha: black ? 0.35 : 0.8)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.06),
    );
  }
}
