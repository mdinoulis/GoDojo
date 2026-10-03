import 'package:go_core/go_core.dart';
import 'package:test/test.dart';

ScoreResult scoreDiagram(String d, Ruleset rules,
    {double? komi, List<double>? ownership, Set<Point>? dead}) {
  final b = Board.fromAscii(d);
  return Scorer.score(
    board: b,
    rules: rules,
    komi: komi ?? rules.defaultKomi,
    deadStones: dead ?? Scorer.guessDeadStones(b, ownership, rules: rules),
    ownership: ownership,
  );
}

void main() {
  const simple = '''
    . . . X O . . . .
    . . . X O . . . .
    . . . X O . . . .
    . . . X O . . . .
    . . . X O . . . .
    . . . X O . . . .
    . . . X O . . . .
    . . . X O . . . .
    . . . X O . . . .''';

  test('simple finished game: Japanese vs Chinese', () {
    final j = scoreDiagram(simple, Ruleset.japanese);
    expect(j.blackTerritory, 27);
    expect(j.whiteTerritory, 36);
    expect(j.margin, 27 - (36 + 6.5));
    expect(j.isFinished, isTrue);
    expect(j.toResult().toSgf(), 'W+15.5');

    final c = scoreDiagram(simple, Ruleset.chinese);
    expect(c.blackScore, 36);
    expect(c.whiteScore, 45 + 7.5);
    expect(c.toResult().toSgf(), 'W+16.5');
  });

  test('prisoners count under territory scoring only', () {
    final b = Board.fromAscii(simple);
    final j = Scorer.score(
        board: b, rules: Ruleset.japanese, komi: 6.5, blackCaptures: 4);
    expect(j.blackScore, 27 + 4);
    final c = Scorer.score(
        board: b, rules: Ruleset.chinese, komi: 7.5, blackCaptures: 4);
    expect(c.blackScore, 36);
  });

  test('seki without eyes: shared liberties are neutral', () {
    const d = '''
      . . X O . X O . .
      . . X O . X O . .
      . . X O X X O . .
      . . X O X X O . .
      . . X O X X O . .
      . . X O X X O . .
      . . X O X X O . .
      . . X O X X O . .
      . . X O X X O . .''';
    final r = scoreDiagram(d, Ruleset.japanese);
    expect(r.statusAt(const Point(4, 0)), PointStatus.seki);
    expect(r.statusAt(const Point(4, 1)), PointStatus.seki);
    expect(r.sekiStones, contains(const Point(3, 0)));
    expect(r.sekiStones, contains(const Point(5, 0)));
    expect(r.deadStones, isEmpty);
    expect(r.blackTerritory, 18);
    expect(r.whiteTerritory, 18);
    expect(r.isFinished, isTrue);
  });

  const sekiWithEyes = '''
    . X X O .
    X X X O O
    X X . O O
    X X X O O
    X X X O O''';

  test('seki with eyes: eyes are not territory under Japanese rules', () {
    final r = scoreDiagram(sekiWithEyes, Ruleset.japanese, komi: 6.5);
    expect(r.statusAt(const Point(2, 2)), PointStatus.seki);
    expect(r.statusAt(const Point(0, 0)), PointStatus.seki);
    expect(r.statusAt(const Point(4, 0)), PointStatus.seki);
    expect(r.blackTerritory, 0);
    expect(r.whiteTerritory, 0);
    expect(r.toResult().toSgf(), 'W+6.5');
  });

  test('seki with eyes: eyes count as area under Chinese rules', () {
    final r = scoreDiagram(sekiWithEyes, Ruleset.chinese, komi: 7.5);
    expect(r.blackScore, 13 + 1);
    expect(r.whiteScore, 9 + 1 + 7.5);
  });

  test('bent four in the corner is dead under Japanese rules', () {
    const d = '''
      . X . O X . . . .
      . O O O X . . . .
      O O X X X . . . .
      X X X . . . . . .
      . . . . . . . . .
      . . . . . . . . .
      . . . . . . . . .
      . . . . . . . . .
      . . . . . . . . .''';
    final b = Board.fromAscii(d);
    final dead = Scorer.guessDeadStones(b, null, rules: Ruleset.japanese);
    expect(dead, containsAll([const Point(3, 0), const Point(0, 2)]));
    expect(dead, isNot(contains(const Point(1, 0))));
    final r = scoreDiagram(d, Ruleset.japanese, komi: 6.5);
    expect(r.blackPrisoners, 6);
    expect(r.blackTerritory, 72);
    expect(r.toResult().toSgf(), 'B+71.5');

    // Not applied under area scoring (left to the engine / players).
    expect(Scorer.guessDeadStones(b, null, rules: Ruleset.chinese), isEmpty);
  });

  test('dead stones from ownership are removed and become prisoners', () {
    final b = Board.fromAscii(simple).tryPlay(Stone.white, const Point(1, 4))!.board;
    final own = List<double>.generate(81, (i) => (i % 9) < 4 ? 0.95 : -0.95);
    final dead = Scorer.guessDeadStones(b, own);
    expect(dead, {const Point(1, 4)});
    final r = Scorer.score(
        board: b, rules: Ruleset.japanese, komi: 6.5, deadStones: dead);
    expect(r.blackTerritory, 27);
    expect(r.blackPrisoners, 1);
    expect(r.statusAt(const Point(1, 4)), PointStatus.deadWhite);
  });

  test('toggling a dead chain', () {
    final b = Board.fromAscii(simple);
    final d = Scorer.toggleDead(b, {}, const Point(3, 0));
    expect(d.length, 9);
    expect(Scorer.toggleDead(b, d, const Point(3, 5)), isEmpty);
  });

  test('open border is reported as unfinished', () {
    const d = '''
      . . . X . O . . .
      . . . X . O . . .
      . . . X . O . . .
      . . . X . O . . .
      . . . . . O . . .
      . . . X . O . . .
      . . . X . O . . .
      . . . X . O . . .
      . . . X . O . . .''';
    final r = scoreDiagram(d, Ruleset.japanese);
    expect(r.isFinished, isFalse);
    expect(r.unsettled, contains(const Point(3, 4)));
  });

  test('an empty or barely started board is unsettled', () {
    final r = Scorer.score(board: Board(9), rules: Ruleset.japanese, komi: 6.5);
    expect(r.isFinished, isFalse);
    expect(r.unsettled.length, 81);
  });

  test('open border detected using ownership', () {
    const d = '''
      . . . X O . . . .
      . . . X O . . . .
      . . . X O . . . .
      . . . X O . . . .
      . . . . O . . . .
      . . . X O . . . .
      . . . X O . . . .
      . . . X O . . . .
      . . . X O . . . .''';
    final own = List<double>.generate(81, (i) => (i % 9) < 4 ? 0.9 : -0.9);
    final r = scoreDiagram(d, Ruleset.japanese, ownership: own);
    expect(r.isFinished, isFalse);
    expect(r.openGaps, contains(const Point(3, 4)));
  });

  test('dame: harmless under Japanese, must be filled under Chinese', () {
    const d = '''
      . . . X . O . . .
      . . . X X O . . .
      . . . X O O . . .
      . . . X O . . . .
      . . . X O . . . .
      . . . X O . . . .
      . . . X O . . . .
      . . . X O . . . .
      . . . X O . . . .''';
    final j = scoreDiagram(d, Ruleset.japanese);
    expect(j.dame, {const Point(4, 0)});
    expect(j.isFinished, isTrue);
    final c = scoreDiagram(d, Ruleset.chinese);
    expect(c.openGaps, {const Point(4, 0)});
  });
}
