import 'package:go_core/go_core.dart';
import 'package:test/test.dart';

MoveCandidate cand(int x, int order, double lead, double wr,
        {int visits = 100, double prior = 0.2}) =>
    MoveCandidate(
        point: Point(x, 0),
        order: order,
        visits: visits,
        winrate: wr,
        scoreLead: lead,
        prior: prior);

PositionAnalysis pos(List<MoveCandidate> moves) => PositionAnalysis(
    toMove: Stone.black,
    visits: 500,
    winrate: moves.first.winrate,
    scoreLead: moves.first.scoreLead,
    moves: moves);

void main() {
  const c = MoveClassifier();
  MoveQuality rate(PositionAnalysis a, int x) =>
      c.classify(before: a, played: Point(x, 0), player: Stone.black).quality;

  test('categories by points lost', () {
    final a = pos([
      cand(0, 0, 5.0, 0.70),
      cand(1, 1, 4.6, 0.68),
      cand(2, 2, 3.5, 0.65),
      cand(3, 3, 0.0, 0.50),
      cand(4, 4, -6.0, 0.25),
    ]);
    expect(rate(a, 0), MoveQuality.good);
    expect(rate(a, 1), MoveQuality.good);
    expect(rate(a, 2), MoveQuality.poor);
    expect(rate(a, 3), MoveQuality.mistake);
    expect(rate(a, 4), MoveQuality.blunder);
  });

  test('a small point loss with a big winrate swing is not a blunder', () {
    final a = pos([cand(0, 0, 0.5, 0.60), cand(1, 1, -0.5, 0.30)]);
    expect(rate(a, 1), MoveQuality.good);
  });

  test('winrate swing escalates a real mistake to a blunder', () {
    final a = pos([cand(0, 0, 2.0, 0.65), cand(1, 1, -2.5, 0.35)]);
    expect(rate(a, 1), MoveQuality.blunder);
  });

  test('only good move is great; hard-to-find only move is a tesuji', () {
    final great = pos([cand(0, 0, 3.0, 0.7, prior: 0.4), cand(1, 1, 0.5, 0.5)]);
    expect(rate(great, 0), MoveQuality.great);
    final tesuji = pos([cand(0, 0, 3.0, 0.7, prior: 0.01), cand(1, 1, -1.0, 0.4)]);
    expect(rate(tesuji, 0), MoveQuality.tesuji);
  });

  test('reports better alternatives and uses White\'s perspective', () {
    final a = PositionAnalysis(
      toMove: Stone.white,
      visits: 500,
      winrate: 0.3,
      scoreLead: -4,
      moves: [cand(0, 0, -4.0, 0.3), cand(1, 1, -3.0, 0.35), cand(2, 2, 2.0, 0.4)],
    );
    final r = c.classify(before: a, played: const Point(2, 0), player: Stone.white);
    expect(r.pointLoss, closeTo(6.0, 1e-9));
    expect(r.quality, MoveQuality.mistake);
    expect(r.betterMoves.map((m) => m.point), [const Point(0, 0), const Point(1, 0)]);
  });

  test('unsearched move falls back to the following position', () {
    final before = pos([cand(0, 0, 3.0, 0.7), cand(1, 1, 2.8, 0.69)]);
    final after = PositionAnalysis(
        toMove: Stone.white, visits: 300, winrate: 0.3, scoreLead: -7, moves: const []);
    final r = c.classify(
        before: before, played: const Point(8, 8), player: Stone.black, after: after);
    expect(r.pointLoss, closeTo(10.0, 1e-9));
    expect(r.quality, MoveQuality.blunder);
  });
}
