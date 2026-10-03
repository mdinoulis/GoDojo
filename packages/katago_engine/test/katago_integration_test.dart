// Runs against the real KataGo in ../../engine (skipped if not installed).
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:go_core/go_core.dart';
import 'package:katago_engine/katago_engine.dart';
import 'package:test/test.dart';

final engineDir = Directory('../../engine').absolute.path;

void main() {
  final config = EngineConfig.desktop(engineDir);
  final installed = File(config.executable).existsSync() &&
      File(config.model).existsSync();
  late KataGoEngine engine;

  setUpAll(() async {
    if (!installed) return;
    engine = KataGoEngine(config.copyWith(hintVisits: 200, rateVisits: 300));
    await engine.start();
  });
  tearDownAll(() async {
    if (installed) await engine.stop();
  });

  Game game9(List<String> moves, {Ruleset rules = Ruleset.japanese}) {
    final g = Game(GameSetup(size: 9, rules: rules, komi: rules.defaultKomi));
    for (final m in moves) {
      g.play(Point.fromGtp(m, 9));
    }
    return g;
  }

  group('KataGo', skip: installed ? false : 'KataGo not installed', () {
    test('values and ownership are from Black\'s perspective', () async {
      final g = game9(['E5', 'pass', 'C5', 'pass', 'G5', 'pass']);
      final a = await engine.analyze(g);
      expect(a.toMove, Stone.black);
      expect(a.scoreLead, greaterThan(5));
      expect(a.winrate, greaterThan(0.8));
      expect(a.ownershipAt(Point.fromGtp('E5', 9)!, 9), greaterThan(0.5));
      expect(a.moves, isNotEmpty);
      expect(a.moves.first.order, 0);
    });

    test('streams partial results', () async {
      final g = Game(const GameSetup(size: 19));
      var partials = 0;
      final a = await engine.analyze(g,
          maxVisits: 3000, onPartial: (_) => partials++);
      expect(a.visits, greaterThanOrEqualTo(2000));
      expect(partials, greaterThan(0));
    });

    for (final id in ['16k', '5k', '1d', 'max']) {
      test('bot level $id plays legal moves', () async {
        final level = BotLevel.byId(id);
        for (final size in [9, 19]) {
          final g = Game(GameSetup(size: size));
          for (var i = 0; i < 6; i++) {
            final m = await engine.genMove(g, level);
            expect(m.point, isNotNull, reason: 'should not pass in the opening');
            expect(g.isLegal(m.point!), isTrue);
            g.play(m.point);
          }
        }
      });
    }

    test('handicap game: White moves first and the bot answers', () async {
      final g = Game(const GameSetup(size: 19, handicap: 4, komi: 0.5));
      final m = await engine.genMove(g, BotLevel.byId('3k'));
      expect(g.toMove, Stone.white);
      expect(g.isLegal(m.point!), isTrue);
      final a = await engine.analyze(g, ownership: false);
      expect(a.toMove, Stone.white);
      expect(a.scoreLead, greaterThan(10)); // Black is well ahead
    });

    test('rates a bad move and suggests better ones', () async {
      final g = game9(['E5', 'E3', 'A9']); // Black's A9 is terrible
      final r = await engine.rateMove(g, 3);
      expect(r.rating.quality.index,
          greaterThanOrEqualTo(MoveQuality.mistake.index));
      expect(r.rating.pointLoss, greaterThan(3));
      expect(r.rating.betterMoves, isNotEmpty);
    });

    test('rates the engine\'s own best move as good or better', () async {
      final g = game9(['E5']);
      final a = await engine.analyze(g, ownership: false, maxVisits: 400);
      g.play(a.best!.point);
      final r = await engine.rateMove(g, 2);
      expect(r.rating.quality.index,
          lessThanOrEqualTo(MoveQuality.good.index));
    });

    test('analyzeGame returns one analysis per position', () async {
      final g = game9(['E5', 'E3', 'C4', 'G4', 'D3']);
      var progress = 0;
      final all = await engine.analyzeGame(g,
          maxVisits: 50, onProgress: (d, _) => progress = d);
      expect(all.length, 6);
      expect(progress, 6);
      final reviews = engine.reviewGame(g, all);
      expect(reviews.length, 5);
    });

    for (final rules in [Ruleset.japanese, Ruleset.chinese]) {
      test('scorer agrees with KataGo on a finished self-play game (${rules.name})',
          () async {
        final g = Game(GameSetup(size: 9, rules: rules, komi: rules.defaultKomi));
        final engineFast = engine;
        while (!g.isOver && g.moveNumber < 160) {
          final a = await engineFast.analyze(g, maxVisits: 60, ownership: false);
          g.play(a.best!.point);
        }
        expect(g.bothPassed, isTrue, reason: 'game should end by passes');
        final a = await engine.analyze(g, maxVisits: 400);
        final dead =
            Scorer.guessDeadStones(g.board, a.ownership, rules: g.rules);
        final s = Scorer.scoreGame(g, deadStones: dead, ownership: a.ownership);
        // ignore: avoid_print
        print('${rules.name}: scorer ${s.margin} vs KataGo ${a.scoreLead.toStringAsFixed(2)}'
            ' finished=${s.isFinished}\n${g.board.toAscii()}');
        expect((s.margin - a.scoreLead).abs(), lessThan(1.5));
      });
    }
  });
}
