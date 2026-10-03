import 'package:go_core/go_core.dart';
import 'package:test/test.dart';

Point p(int x, int y) => Point(x, y);

/// Sets up a ko at (1,1)/(2,1) and returns the game right after Black takes.
Game koGame(Ruleset rules) {
  final g = Game(GameSetup(size: 19, rules: rules));
  for (final m in [
    Move(Stone.black, p(1, 0)),
    Move(Stone.white, p(2, 0)),
    Move(Stone.black, p(0, 1)),
    Move(Stone.white, p(3, 1)),
    Move(Stone.black, p(1, 2)),
    Move(Stone.white, p(2, 2)),
    Move(Stone.black, p(10, 10)),
    Move(Stone.white, p(1, 1)),
    Move(Stone.black, p(2, 1)), // takes the ko
  ]) {
    g.playMove(m);
  }
  return g;
}

void main() {
  group('coordinates', () {
    test('GTP round trip skips I', () {
      expect(p(15, 3).toGtp(19), 'Q16');
      expect(p(8, 0).toGtp(19), 'J19');
      expect(Point.fromGtp('D4', 19), p(3, 15));
      expect(Point.fromGtp('pass', 19), isNull);
    });
    test('SGF', () {
      expect(p(15, 3).toSgf(), 'pd');
      expect(Point.fromSgf('pd', 19), p(15, 3));
    });
  });

  group('captures and legality', () {
    test('capture single stone and count prisoners', () {
      final g = Game(const GameSetup(size: 9));
      g.playMove(Move(Stone.white, p(4, 4)));
      g.playMove(Move(Stone.black, p(3, 4)));
      g.playMove(Move(Stone.black, p(5, 4)));
      g.playMove(Move(Stone.black, p(4, 3)));
      g.playMove(Move(Stone.black, p(4, 5)));
      expect(g.board[p(4, 4)], isNull);
      expect(g.prisoners(Stone.black), 1);
      expect(g.lastCaptured, [p(4, 4)]);
    });

    test('suicide is illegal under Japanese, legal under New Zealand', () {
      for (final rules in [Ruleset.japanese, Ruleset.newZealand]) {
        final g = Game(GameSetup(size: 9, rules: rules));
        g.playMove(Move(Stone.black, p(1, 0)));
        g.playMove(Move(Stone.black, p(0, 1)));
        // White to move? force colour: white plays the corner (suicide).
        final reason = () {
          try {
            g.playMove(Move(Stone.white, p(0, 0)));
            return null;
          } on IllegalMoveException catch (e) {
            return e.reason;
          }
        }();
        if (rules.suicide) {
          expect(reason, isNull);
          expect(g.board[p(0, 0)], isNull);
          expect(g.prisoners(Stone.black), 1);
        } else {
          expect(reason, IllegalReason.suicide);
        }
      }
    });

    test('occupied point is illegal', () {
      final g = Game(const GameSetup(size: 9));
      g.play(p(4, 4));
      expect(g.illegalReason(p(4, 4)), IllegalReason.occupied);
    });

    for (final rules in [Ruleset.japanese, Ruleset.chinese, Ruleset.aga]) {
      test('ko cannot be retaken immediately (${rules.name})', () {
        final g = koGame(rules);
        expect(g.board[p(1, 1)], isNull);
        expect(g.toMove, Stone.white);
        expect(g.illegalReason(p(1, 1)), IllegalReason.ko);
        // After a ko threat exchange it becomes legal.
        g.play(p(15, 15));
        g.play(p(15, 14));
        expect(g.illegalReason(p(1, 1)), isNull);
      });
    }
  });

  group('handicap', () {
    test('19x19 two stones on Q16 and D4, White first', () {
      final g = Game(const GameSetup(size: 19, handicap: 2, komi: 0.5));
      expect(g.handicapStones.map((s) => s.toGtp(19)).toSet(), {'Q16', 'D4'});
      expect(g.toMove, Stone.white);
      expect(g.board[Point.fromGtp('Q16', 19)!], Stone.black);
    });
    test('9 stones use every star point', () {
      expect(handicapPoints(19, 9).map((s) => s.toGtp(19)).toSet(),
          {'D4', 'K4', 'Q4', 'D10', 'K10', 'Q10', 'D16', 'K16', 'Q16'});
      expect(handicapPoints(9, 5).map((s) => s.toGtp(9)).toSet(),
          {'C3', 'G3', 'C7', 'G7', 'E5'});
      expect(handicapPoints(13, 4).map((s) => s.toGtp(13)).toSet(),
          {'D4', 'K4', 'D10', 'K10'});
    });
    test('default komi', () {
      expect(GameSetup.defaultKomi(Ruleset.japanese, 0), 6.5);
      expect(GameSetup.defaultKomi(Ruleset.japanese, 3), 0.5);
    });
  });

  group('undo / redo', () {
    test('multi-step undo restores board, captures and side to move', () {
      final g = Game(const GameSetup(size: 9));
      final before = g.board;
      g.play(p(2, 2));
      g.play(p(6, 6));
      g.play(p(2, 6));
      expect(g.undo(2), 2);
      expect(g.moveNumber, 1);
      expect(g.toMove, Stone.white);
      expect(g.undo(5), 1);
      expect(g.board, before);
      expect(g.redo(3), 3);
      expect(g.board[p(2, 6)], Stone.black);
    });

    test('playing a new move clears redo, same move keeps it', () {
      final g = Game(const GameSetup(size: 9));
      g.play(p(2, 2));
      g.play(p(6, 6));
      g.play(p(4, 4));
      g.undo(2);
      g.play(p(6, 6)); // same as the undone move
      expect(g.redoCount, 1);
      g.play(p(1, 1)); // different -> redo lost
      expect(g.redoCount, 0);
    });

    test('undo also undoes a capture', () {
      final g = koGame(Ruleset.japanese);
      g.undo();
      expect(g.board[p(1, 1)], Stone.white);
      expect(g.prisoners(Stone.black), 0);
    });

    test('two passes end the game; undo resumes it', () {
      final g = Game(const GameSetup(size: 9));
      g.pass();
      g.pass();
      expect(g.bothPassed, isTrue);
      g.undo();
      expect(g.isOver, isFalse);
    });
  });

  group('SGF', () {
    test('round trip with handicap, passes and result', () {
      final g = Game(const GameSetup(size: 13, handicap: 3, komi: 0.5));
      g.play(p(3, 3));
      g.play(p(6, 6));
      g.pass();
      g.resign(Stone.black);
      final sgf = Sgf.export(g, blackName: 'Me', whiteName: 'KataGo');
      final g2 = Sgf.import(sgf);
      expect(g2.size, 13);
      expect(g2.setup.komi, 0.5);
      expect(g2.handicapStones.toSet(), g.handicapStones.toSet());
      expect(g2.moves, g.moves);
      expect(g2.board, g.board);
      expect(g2.result?.toSgf(), 'W+R');
    });

    test('reads variations by following the main line', () {
      final g = Sgf.import('(;GM[1]SZ[9]KM[7.5]RU[Chinese];B[ee](;W[cc];B[gg])(;W[gc]))');
      expect(g.rules, Ruleset.chinese);
      expect(g.moveNumber, 3);
    });
  });
}
