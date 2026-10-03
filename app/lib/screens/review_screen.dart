import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_core/go_core.dart';
import 'package:katago_engine/katago_engine.dart';

import '../board/board_view.dart';
import '../engine_service.dart';
import '../settings.dart';
import 'quality.dart';

/// Moves worth stopping at when stepping through a review.
const keyQualities = {
  MoveQuality.tesuji,
  MoveQuality.great,
  MoveQuality.mistake,
  MoveQuality.blunder,
};

/// Per-player summary of a reviewed game.
class ReviewSummary {
  final Map<MoveQuality, int> counts;
  final double accuracy; // 0..100
  final double meanLoss;
  const ReviewSummary(this.counts, this.accuracy, this.meanLoss);

  static ReviewSummary of(Iterable<MoveReview> reviews) {
    final counts = {for (final q in MoveQuality.values) q: 0};
    var acc = 0.0, loss = 0.0, n = 0;
    for (final r in reviews) {
      if (r.move.isPass) continue;
      counts[r.rating.quality] = counts[r.rating.quality]! + 1;
      acc += 100 * exp(-r.rating.pointLoss / 4);
      loss += r.rating.pointLoss;
      n++;
    }
    return ReviewSummary(counts, n == 0 ? 0 : acc / n, n == 0 ? 0 : loss / n);
  }
}

/// Post-game analysis: summary of move qualities for each player, a score
/// graph, and stepping through the key moments with the engine's best line.
class ReviewScreen extends ConsumerStatefulWidget {
  final Game game;

  /// Highlights this player's moves (null = both, e.g. over-the-board games).
  final Stone? player;
  final String blackName, whiteName;

  const ReviewScreen({
    super.key,
    required this.game,
    this.player,
    this.blackName = 'Black',
    this.whiteName = 'White',
  });

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  List<PositionAnalysis>? analyses;
  List<MoveReview>? reviews;
  String? error;
  int done = 0;
  int index = 0; // number of moves shown on the board
  bool showBestLine = false;
  bool onlyMine = true;

  Game get game => widget.game;

  @override
  void initState() {
    super.initState();
    index = min(1, game.moveNumber);
    _run();
  }

  Future<void> _run() async {
    try {
      final engines = ref.read(engineServiceProvider);
      final engine = await engines.engineFor(ref.read(settingsProvider));
      final a = await engine.analyzeGame(game, onProgress: (d, total) {
        if (mounted) setState(() => done = d);
      });
      if (!mounted) return;
      setState(() {
        analyses = a;
        reviews = engine.reviewGame(game, a);
        final first = _nextKey(0);
        if (first != null) index = first;
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  @override
  void dispose() {
    if (reviews == null) ref.read(engineServiceProvider).cancel();
    super.dispose();
  }

  MoveReview? get current =>
      reviews == null || index < 1 || index > reviews!.length ? null : reviews![index - 1];

  bool _isKey(MoveReview r) =>
      keyQualities.contains(r.rating.quality) &&
      (!onlyMine || widget.player == null || r.move.color == widget.player);

  int? _nextKey(int from) {
    final rs = reviews;
    if (rs == null) return null;
    for (var i = from; i < rs.length; i++) {
      if (_isKey(rs[i])) return i + 1;
    }
    return null;
  }

  int? _prevKey(int before) {
    final rs = reviews;
    if (rs == null) return null;
    for (var i = before - 2; i >= 0; i--) {
      if (_isKey(rs[i])) return i + 1;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final total = game.moveNumber;
    return Scaffold(
      appBar: AppBar(title: const Text('Game review')),
      body: SafeArea(
        child: LayoutBuilder(builder: (context, box) {
          final board = _board(settings);
          final panel = _panel(total);
          if (box.maxWidth > box.maxHeight * 1.15) {
            return Row(children: [
              Expanded(child: Padding(padding: const EdgeInsets.all(12), child: Center(child: board))),
              SizedBox(width: 380, child: ListView(padding: const EdgeInsets.fromLTRB(0, 12, 12, 12), children: panel)),
            ]);
          }
          return ListView(padding: const EdgeInsets.all(8), children: [board, const SizedBox(height: 8), ...panel]);
        }),
      ),
    );
  }

  Widget _board(AppSettings settings) {
    final r = current;
    if (r == null) {
      return BoardView(board: game.boardAt(index), settings: settings,
          decorations: BoardDecorations(lastMove: index > 0 ? game.moves[index - 1].point : null));
    }
    final size = game.size;
    final best = r.rating.best;
    if (showBestLine && best != null) {
      // Position before the move, with the engine's line as numbered stones.
      var b = game.boardAt(index - 1);
      var colour = r.move.color;
      final marks = <CandidateMark>[];
      final line = [best.point, ...best.pv.skip(1)].take(8).toList();
      for (var i = 0; i < line.length; i++) {
        final p = line[i];
        if (p == null) break;
        final res = b.tryPlay(colour, p);
        if (res == null) break;
        b = res.board;
        marks.add(CandidateMark(p, '${i + 1}',
            colour == Stone.black ? const Color(0xFF263238) : const Color(0xFFF5F5F5),
            textColor: colour == Stone.black ? Colors.white : Colors.black,
            best: i == 0));
        colour = colour.opponent;
      }
      return BoardView(
        board: game.boardAt(index - 1),
        settings: settings,
        decorations: BoardDecorations(candidates: marks),
      );
    }
    final played = r.move.point;
    return BoardView(
      board: game.boardAt(index),
      settings: settings,
      decorations: BoardDecorations(
        lastMove: played,
        rings: {?played: qualityColor(r.rating.quality)},
        candidates: [
          if (best != null && best.point != null && best.point != played &&
              game.boardAt(index)[best.point!] == null)
            CandidateMark(best.point!, '★', const Color(0xFF4FC3F7), best: true),
        ],
      ),
      key: ValueKey('review-$index-$size'),
    );
  }

  List<Widget> _panel(int total) {
    final rs = reviews;
    if (error != null) {
      return [Card(child: Padding(padding: const EdgeInsets.all(12), child: Text('Analysis failed: $error')))];
    }
    if (rs == null) {
      return [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Analysing the game…', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: total == 0 ? null : done / (total + 1)),
              const SizedBox(height: 4),
              Text('$done / ${total + 1} positions'),
            ]),
          ),
        ),
      ];
    }
    return [
      _summary(rs),
      const SizedBox(height: 8),
      _graph(),
      const SizedBox(height: 8),
      _navigator(total),
      const SizedBox(height: 8),
      _moveCard(),
    ];
  }

  Widget _summary(List<MoveReview> rs) {
    final black = ReviewSummary.of(rs.where((r) => r.move.color == Stone.black));
    final white = ReviewSummary.of(rs.where((r) => r.move.color == Stone.white));
    TableRow row(Widget label, String b, String w) => TableRow(children: [
          Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: label),
          Text(b, textAlign: TextAlign.center),
          Text(w, textAlign: TextAlign.center),
        ]);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Summary', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Table(columnWidths: const {0: FlexColumnWidth(2)}, children: [
            row(const SizedBox(), widget.blackName, widget.whiteName),
            row(const Text('Accuracy'), '${black.accuracy.round()}%', '${white.accuracy.round()}%'),
            row(const Text('Avg. points lost'), black.meanLoss.toStringAsFixed(1), white.meanLoss.toStringAsFixed(1)),
            for (final q in MoveQuality.values)
              row(
                Row(children: [
                  Icon(qualityIcon(q), size: 16, color: qualityColor(q)),
                  const SizedBox(width: 6),
                  Text(q == MoveQuality.tesuji ? 'Tesujis' : '${q.label}s'),
                ]),
                '${black.counts[q]}',
                '${white.counts[q]}',
              ),
          ]),
        ]),
      ),
    );
  }

  Widget _graph() {
    final a = analyses!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Score lead (Black above the line)', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          SizedBox(
            height: 110,
            child: LayoutBuilder(builder: (context, box) {
              return GestureDetector(
                onTapDown: (d) => _jump(d.localPosition.dx, box.maxWidth, a.length),
                onHorizontalDragUpdate: (d) => _jump(d.localPosition.dx, box.maxWidth, a.length),
                child: CustomPaint(
                  size: Size(box.maxWidth, 110),
                  painter: _GraphPainter(
                    [for (final x in a) x.scoreLead],
                    reviews!,
                    index,
                    Theme.of(context).colorScheme,
                  ),
                ),
              );
            }),
          ),
        ]),
      ),
    );
  }

  void _jump(double x, double width, int n) {
    if (n < 2) return;
    setState(() {
      index = (x / width * (n - 1)).round().clamp(0, n - 1);
      showBestLine = false;
    });
  }

  Widget _navigator(int total) {
    void go(int? i) {
      if (i == null) return;
      setState(() {
        index = i.clamp(0, total);
        showBestLine = false;
      });
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(children: [
          Row(children: [
            IconButton(tooltip: 'Previous key moment', onPressed: _prevKey(index) == null ? null : () => go(_prevKey(index)),
                icon: const Icon(Icons.keyboard_double_arrow_left)),
            IconButton(tooltip: 'Previous move', onPressed: index > 0 ? () => go(index - 1) : null,
                icon: const Icon(Icons.chevron_left)),
            Expanded(child: Text('Move $index / $total', textAlign: TextAlign.center)),
            IconButton(tooltip: 'Next move', onPressed: index < total ? () => go(index + 1) : null,
                icon: const Icon(Icons.chevron_right)),
            IconButton(tooltip: 'Next key moment', onPressed: _nextKey(index) == null ? null : () => go(_nextKey(index)),
                icon: const Icon(Icons.keyboard_double_arrow_right)),
          ]),
          if (widget.player != null)
            SwitchListTile(
              dense: true,
              title: const Text('Key moments: only my moves'),
              value: onlyMine,
              onChanged: (v) => setState(() => onlyMine = v),
            ),
        ]),
      ),
    );
  }

  Widget _moveCard() {
    final r = current;
    if (r == null) {
      return const Card(child: Padding(padding: EdgeInsets.all(12), child: Text('Start of the game.')));
    }
    final size = game.size;
    final q = r.rating.quality;
    final who = r.move.color == Stone.black ? widget.blackName : widget.whiteName;
    final best = r.rating.best;
    final explanation = switch (q) {
      MoveQuality.tesuji => 'A hard-to-find move that is clearly better than anything else.',
      MoveQuality.great => 'The only good move in this position.',
      MoveQuality.good => r.rating.pointLoss < 0.5 ? 'One of the best moves.' : 'A reasonable move.',
      _ => 'Lost ${r.rating.pointLoss.toStringAsFixed(1)} points '
          '(${(r.rating.winrateLoss * 100).toStringAsFixed(1)}% win chance).',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(qualityIcon(q), color: qualityColor(q), size: 28),
            const SizedBox(width: 8),
            Expanded(
              child: Text('$index. $who ${r.move.toGtp(size)} – ${q.label}',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
          ]),
          const SizedBox(height: 6),
          Text(explanation),
          if (best != null && best.point != r.move.point) ...[
            const SizedBox(height: 4),
            Text('Best was ${best.point?.toGtp(size) ?? 'pass'} '
                '(lead ${signed(best.scoreFor(r.move.color))} for $who).'),
          ],
          const SizedBox(height: 4),
          Text('Position after the move: ${leadText(r.after?.scoreLead ?? r.before.scoreLead)}',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          if (best != null && best.point != null)
            FilledButton.tonalIcon(
              onPressed: () => setState(() => showBestLine = !showBestLine),
              icon: Icon(showBestLine ? Icons.visibility_off : Icons.timeline),
              label: Text(showBestLine ? 'Show the game move' : 'Show the best line'),
            ),
        ]),
      ),
    );
  }
}

class _GraphPainter extends CustomPainter {
  final List<double> leads;
  final List<MoveReview> reviews;
  final int index;
  final ColorScheme scheme;
  _GraphPainter(this.leads, this.reviews, this.index, this.scheme);

  @override
  void paint(Canvas canvas, Size size) {
    if (leads.length < 2) return;
    final maxAbs = max(5.0, leads.map((v) => v.abs()).reduce(max));
    double x(int i) => i / (leads.length - 1) * size.width;
    double y(double v) => size.height / 2 - v / maxAbs * (size.height / 2 - 4);

    final mid = size.height / 2;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, mid), Paint()..color = const Color(0x22000000));
    canvas.drawRect(Rect.fromLTWH(0, mid, size.width, mid), Paint()..color = const Color(0x11FFFFFF));
    canvas.drawLine(Offset(0, mid), Offset(size.width, mid), Paint()..color = scheme.outline);

    final path = Path()..moveTo(x(0), y(leads[0]));
    for (var i = 1; i < leads.length; i++) {
      path.lineTo(x(i), y(leads[i]));
    }
    canvas.drawPath(path, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = scheme.primary);

    for (final r in reviews) {
      if (!keyQualities.contains(r.rating.quality)) continue;
      final i = r.moveNumber;
      if (i >= leads.length) continue;
      canvas.drawCircle(Offset(x(i), y(leads[i])), 3.5, Paint()..color = qualityColor(r.rating.quality));
    }
    canvas.drawLine(Offset(x(index.clamp(0, leads.length - 1)), 0),
        Offset(x(index.clamp(0, leads.length - 1)), size.height),
        Paint()
          ..color = scheme.tertiary
          ..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(_GraphPainter old) => old.index != index || old.leads != leads;
}
