import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_core/go_core.dart';

import '../settings.dart';
import 'stones.dart';

/// A labelled candidate move drawn on the board (hints, better moves).
class CandidateMark {
  final Point point;
  final String label;
  final String? subLabel;
  final Color color;
  final Color textColor;
  final bool best;
  const CandidateMark(this.point, this.label, this.color,
      {this.subLabel, this.best = false, this.textColor = Colors.black});
}

/// Everything drawn on top of the stones.
class BoardDecorations {
  final Point? lastMove;
  final Map<Point, int>? moveNumbers;
  final List<CandidateMark> candidates;
  final List<double>? ownership;
  final List<PointStatus>? scoring;
  final Set<Point> gaps;
  final Set<Point> unsettled;
  final Map<Point, Color> rings;

  const BoardDecorations({
    this.lastMove,
    this.moveNumbers,
    this.candidates = const [],
    this.ownership,
    this.scoring,
    this.gaps = const {},
    this.unsettled = const {},
    this.rings = const {},
  });
}

class BoardView extends StatefulWidget {
  final Board board;
  final AppSettings settings;
  final BoardDecorations decorations;
  final ValueChanged<Point>? onTap;

  /// Colour of the translucent "ghost" stone shown under the mouse.
  final Stone? ghost;

  const BoardView({
    super.key,
    required this.board,
    required this.settings,
    this.decorations = const BoardDecorations(),
    this.onTap,
    this.ghost,
  });

  @override
  State<BoardView> createState() => _BoardViewState();
}

class _BoardViewState extends State<BoardView> {
  final _stones = StoneRenderer();
  Point? _hover;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(builder: (context, box) {
        final geo = BoardGeometry(
            box.maxWidth, widget.board.size, widget.settings.showCoordinates);
        return MouseRegion(
          onHover: (e) {
            final p = geo.pointAt(e.localPosition);
            if (p != _hover) setState(() => _hover = p);
          },
          onExit: (_) => setState(() => _hover = null),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: widget.onTap == null
                ? null
                : (d) {
                    final p = geo.pointAt(d.localPosition);
                    if (p != null) widget.onTap!(p);
                  },
            child: Stack(fit: StackFit.expand, children: [
              RepaintBoundary(
                child: CustomPaint(
                  painter: _BackgroundPainter(geo, widget.settings),
                ),
              ),
              CustomPaint(
                painter: _ForegroundPainter(
                  geo,
                  widget.board,
                  widget.settings,
                  widget.decorations,
                  _stones,
                  ghost: widget.ghost != null &&
                          _hover != null &&
                          widget.board[_hover!] == null
                      ? (_hover!, widget.ghost!)
                      : null,
                ),
              ),
            ]),
          ),
        );
      }),
    );
  }
}

/// Maps between board points and pixels.
class BoardGeometry {
  final double side;
  final int size;
  final bool coords;
  late final double cell;
  late final double origin;

  BoardGeometry(this.side, this.size, this.coords) {
    final marginCells = coords ? 1.05 : 0.7;
    cell = side / (size - 1 + 2 * marginCells);
    origin = cell * marginCells;
  }

  Offset at(Point p) => Offset(origin + p.x * cell, origin + p.y * cell);
  Offset atIndex(int x, int y) => Offset(origin + x * cell, origin + y * cell);
  double get stoneRadius => cell * 0.48;

  Point? pointAt(Offset o) {
    final x = ((o.dx - origin) / cell).round();
    final y = ((o.dy - origin) / cell).round();
    if (x < 0 || y < 0 || x >= size || y >= size) return null;
    return Point(x, y);
  }

  List<Point> get hoshi {
    final lo = size >= 13 ? 3 : 2;
    final hi = size - 1 - lo, mid = size ~/ 2;
    if (size < 9) return const [];
    final pts = [Point(lo, lo), Point(hi, lo), Point(lo, hi), Point(hi, hi)];
    if (size.isOdd) pts.add(Point(mid, mid));
    if (size >= 19) {
      pts.addAll([Point(mid, lo), Point(mid, hi), Point(lo, mid), Point(hi, mid)]);
    }
    return pts;
  }
}

class _BackgroundPainter extends CustomPainter {
  final BoardGeometry g;
  final AppSettings s;
  _BackgroundPainter(this.g, this.s);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final theme = s.boardTheme;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(g.cell * 0.15));
    canvas.save();
    canvas.clipRRect(rrect);
    _paintWood(canvas, rect, theme);
    canvas.restore();

    final grid = Paint()
      ..color = s.gridColour.color
      ..strokeWidth = max(0.8, g.cell * 0.035);
    final n = g.size - 1;
    for (var i = 0; i <= n; i++) {
      canvas.drawLine(g.atIndex(i, 0), g.atIndex(i, n), grid);
      canvas.drawLine(g.atIndex(0, i), g.atIndex(n, i), grid);
    }
    // Slightly heavier border.
    canvas.drawRect(
        Rect.fromPoints(g.atIndex(0, 0), g.atIndex(n, n)),
        Paint()
          ..color = s.gridColour.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = max(1.2, g.cell * 0.06));
    for (final h in g.hoshi) {
      canvas.drawCircle(g.at(h), max(2, g.cell * 0.11),
          Paint()..color = s.gridColour.color);
    }
    if (s.showCoordinates) _paintCoords(canvas);
  }

  void _paintWood(Canvas canvas, Rect rect, BoardTheme t) {
    final base = HSLColor.fromColor(t.base);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            base.withLightness(min(1, base.lightness + 0.04)).toColor(),
            t.base,
            base.withLightness(max(0, base.lightness - 0.04)).toColor(),
          ],
        ).createShader(rect),
    );
    if (!t.woodGrain) return;
    // Straight vertical grain (masame) with gentle waves.
    final rnd = Random(7);
    final w = rect.width, h = rect.height;
    for (var i = 0; i < 170; i++) {
      final x0 = rnd.nextDouble() * w * 1.1 - w * 0.05;
      final amp = w * (0.002 + rnd.nextDouble() * 0.008);
      final freq = 0.6 + rnd.nextDouble() * 1.8;
      final phase = rnd.nextDouble() * 2 * pi;
      final drift = (rnd.nextDouble() - 0.5) * w * 0.03;
      final path = Path();
      const steps = 48;
      for (var k = 0; k <= steps; k++) {
        final y = h * k / steps;
        final x = x0 + amp * sin(freq * 2 * pi * k / steps + phase) + drift * k / steps;
        k == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      final strong = rnd.nextDouble() < 0.18;
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * (strong ? 0.002 + rnd.nextDouble() * 0.004 : 0.0008 + rnd.nextDouble() * 0.0018)
          ..color = t.grain.withValues(
              alpha: strong ? 0.25 + rnd.nextDouble() * 0.2 : 0.08 + rnd.nextDouble() * 0.16),
      );
    }
    // Soft broad bands of colour variation.
    for (var i = 0; i < 9; i++) {
      final x = rnd.nextDouble() * w;
      final bw = w * (0.04 + rnd.nextDouble() * 0.1);
      canvas.drawRect(
        Rect.fromLTWH(x - bw / 2, 0, bw, h),
        Paint()
          ..color = (rnd.nextBool() ? Colors.white : t.grain)
              .withValues(alpha: 0.05 + rnd.nextDouble() * 0.05)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, bw * 0.4),
      );
    }
  }

  void _paintCoords(Canvas canvas) {
    const letters = 'ABCDEFGHJKLMNOPQRST';
    final style = TextStyle(
      color: s.gridColour.color.withValues(alpha: 0.8),
      fontSize: min(g.cell * 0.34, 20),
      fontWeight: FontWeight.w600,
    );
    void text(String t, Offset c) {
      final tp = TextPainter(
          text: TextSpan(text: t, style: style), textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    }

    final off = g.cell * 0.62;
    for (var i = 0; i < g.size; i++) {
      final top = g.atIndex(i, 0), bottom = g.atIndex(i, g.size - 1);
      text(letters[i], top - Offset(0, off));
      text(letters[i], bottom + Offset(0, off));
      final left = g.atIndex(0, i), right = g.atIndex(g.size - 1, i);
      text('${g.size - i}', left - Offset(off, 0));
      text('${g.size - i}', right + Offset(off, 0));
    }
  }

  @override
  bool shouldRepaint(_BackgroundPainter old) =>
      old.g.side != g.side ||
      old.g.size != g.size ||
      old.s.boardTheme != s.boardTheme ||
      old.s.gridColour != s.gridColour ||
      old.s.showCoordinates != s.showCoordinates;
}

class _ForegroundPainter extends CustomPainter {
  final BoardGeometry g;
  final Board board;
  final AppSettings s;
  final BoardDecorations d;
  final StoneRenderer stones;
  final (Point, Stone)? ghost;

  _ForegroundPainter(this.g, this.board, this.s, this.d, this.stones, {this.ghost});

  @override
  void paint(Canvas canvas, Size size) {
    final r = g.stoneRadius;
    final status = d.scoring;

    // Ownership (score estimate) under the stones.
    final own = d.ownership;
    if (own != null && status == null) {
      for (final p in board.points) {
        final v = own[p.index(board.size)];
        if (v.abs() < 0.15) continue;
        final stone = board[p];
        final owner = v > 0 ? Stone.black : Stone.white;
        if (stone == owner) continue;
        final side = g.cell * 0.62 * v.abs();
        final rect = Rect.fromCenter(center: g.at(p), width: side, height: side);
        canvas.drawRect(
          rect,
          Paint()
            ..color = (owner == Stone.black ? Colors.black : Colors.white)
                .withValues(alpha: 0.5 + 0.45 * v.abs()),
        );
        if (owner == Stone.white) {
          canvas.drawRect(
              rect,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1
                ..color = Colors.black38);
        }
      }
    }

    // Stones.
    for (final p in board.points) {
      final st = board[p];
      if (st == null) continue;
      final dead = status != null &&
          (status[p.index(board.size)] == PointStatus.deadBlack ||
              status[p.index(board.size)] == PointStatus.deadWhite);
      final likelyDead = own != null &&
          status == null &&
          (st == Stone.black ? own[p.index(board.size)] < -0.5 : own[p.index(board.size)] > 0.5);
      stones.draw(canvas, g.at(p), r, st, s.stoneStyle,
          variant: p.x * 7 + p.y * 13, opacity: dead ? 0.45 : 1);
      if (likelyDead) _cross(canvas, g.at(p), r * 0.45, st);
    }

    // Territory, seki and dead marks when counting.
    if (status != null) {
      for (final p in board.points) {
        final ps = status[p.index(board.size)];
        final c = g.at(p);
        final side = g.cell * 0.34;
        switch (ps) {
          case PointStatus.blackTerritory:
          case PointStatus.deadWhite:
            _square(canvas, c, side, Colors.black);
          case PointStatus.whiteTerritory:
          case PointStatus.deadBlack:
            _square(canvas, c, side, Colors.white);
          case PointStatus.seki:
            if (board[p] == null) _diamond(canvas, c, side * 0.8);
          default:
            break;
        }
      }
    }

    // Move numbers / last move marker.
    final nums = d.moveNumbers;
    if (nums != null) {
      nums.forEach((p, n) {
        final st = board[p];
        if (st == null) return;
        _label(canvas, g.at(p), '$n',
            st == Stone.black ? Colors.white : Colors.black, r * (n >= 100 ? 0.75 : 0.9));
      });
    }
    final last = d.lastMove;
    if (last != null && board[last] != null && (nums == null || !nums.containsKey(last))) {
      canvas.drawCircle(
        g.at(last),
        r * 0.42,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = max(1.5, r * 0.12)
          ..color = board[last] == Stone.black ? Colors.white : Colors.black,
      );
    }

    // Coloured rings (e.g. rated move).
    d.rings.forEach((p, color) {
      canvas.drawCircle(
        g.at(p),
        r * 1.02,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = max(2.5, r * 0.18)
          ..color = color,
      );
    });

    // Candidate moves.
    for (final m in d.candidates) {
      if (board[m.point] != null) continue;
      final c = g.at(m.point);
      canvas.drawCircle(c, r * 0.95, Paint()..color = m.color.withValues(alpha: 0.88));
      if (m.best) {
        canvas.drawCircle(
            c,
            r * 0.95,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = max(2, r * 0.12)
              ..color = Colors.white);
      }
      if (m.subLabel == null) {
        _label(canvas, c, m.label, m.textColor, r * (m.label.length > 3 ? 0.55 : 0.75));
      } else {
        _label(canvas, c - Offset(0, r * 0.25), m.label, m.textColor, r * 0.62);
        _label(canvas, c + Offset(0, r * 0.38), m.subLabel!,
            Colors.black.withValues(alpha: 0.75), r * 0.45);
      }
    }

    // Areas still open.
    for (final p in d.unsettled) {
      if (board[p] != null) continue;
      canvas.drawCircle(g.at(p), r * 0.16,
          Paint()..color = Colors.redAccent.withValues(alpha: 0.7));
    }

    // Unfinished points.
    for (final p in d.gaps) {
      final c = g.at(p);
      canvas.drawCircle(
          c,
          r * 0.6,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = max(2, r * 0.14)
            ..color = Colors.redAccent);
      _label(canvas, c, '?', Colors.red.shade900, r * 0.8);
    }

    // Ghost stone under the pointer.
    if (ghost != null) {
      stones.draw(canvas, g.at(ghost!.$1), r, ghost!.$2, s.stoneStyle,
          opacity: 0.5, shadow: false);
    }
  }

  void _square(Canvas canvas, Offset c, double side, Color color) {
    final rect = Rect.fromCenter(center: c, width: side, height: side);
    canvas.drawRect(rect, Paint()..color = color);
    canvas.drawRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = color == Colors.white ? Colors.black54 : Colors.white38);
  }

  void _diamond(Canvas canvas, Offset c, double side) {
    final path = Path()
      ..moveTo(c.dx, c.dy - side)
      ..lineTo(c.dx + side, c.dy)
      ..lineTo(c.dx, c.dy + side)
      ..lineTo(c.dx - side, c.dy)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.blueGrey.shade600);
  }

  void _cross(Canvas canvas, Offset c, double h, Stone st) {
    final p = Paint()
      ..strokeWidth = max(1.5, h * 0.3)
      ..color = st == Stone.black ? Colors.white : Colors.black;
    canvas.drawLine(c - Offset(h, h), c + Offset(h, h), p);
    canvas.drawLine(c - Offset(-h, h), c + Offset(-h, h), p);
  }

  void _label(Canvas canvas, Offset c, String text, Color color, double fontSize) {
    final tp = TextPainter(
      text: TextSpan(
          text: text,
          style: TextStyle(
              color: color, fontSize: fontSize, fontWeight: FontWeight.w700, height: 1)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_ForegroundPainter old) => true;
}
