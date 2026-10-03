import 'board.dart';
import 'game.dart';
import 'point.dart';
import 'rules.dart';

/// What a point counts as in the final position.
enum PointStatus {
  blackStone,
  whiteStone,
  deadBlack, // dead black stone -> White's territory/prisoner
  deadWhite,
  blackTerritory,
  whiteTerritory,
  dame, // neutral point
  seki, // neutral point inside / between groups in seki
}

class ScoreResult {
  final Ruleset rules;
  final double komi;
  final int size;
  final List<PointStatus> status; // row-major, top row first

  final int blackTerritory, whiteTerritory;
  final int blackStones, whiteStones; // living stones on the board
  final int blackPrisoners, whitePrisoners; // captures + dead stones taken
  final int handicapBonus; // extra points for White (area scoring)

  final Set<Point> deadStones;
  final Set<Point> sekiStones;
  final Set<Point> dame;

  /// Points that still need to be played before the game can be counted
  /// (open borders, protective moves / teire, and dame under area scoring).
  final Set<Point> openGaps;

  /// Points of large neutral areas that are still being contested.
  final Set<Point> unsettled;

  const ScoreResult({
    required this.rules,
    required this.komi,
    required this.size,
    required this.status,
    required this.blackTerritory,
    required this.whiteTerritory,
    required this.blackStones,
    required this.whiteStones,
    required this.blackPrisoners,
    required this.whitePrisoners,
    required this.handicapBonus,
    required this.deadStones,
    required this.sekiStones,
    required this.dame,
    required this.openGaps,
    this.unsettled = const {},
  });

  bool get isFinished => openGaps.isEmpty && unsettled.isEmpty;

  double get blackScore => rules.scoring == ScoringType.area
      ? (blackStones + blackTerritory).toDouble()
      : (blackTerritory + blackPrisoners).toDouble();

  double get whiteScore =>
      (rules.scoring == ScoringType.area
          ? whiteStones + whiteTerritory
          : whiteTerritory + whitePrisoners) +
      komi +
      handicapBonus;

  /// Positive = Black leads.
  double get margin => blackScore - whiteScore;

  GameResult toResult() => margin == 0
      ? const GameResult(null, ResultReason.score, 0)
      : GameResult(margin > 0 ? Stone.black : Stone.white, ResultReason.score,
          margin.abs());

  PointStatus statusAt(Point p) => status[p.index(size)];
}

/// Final-position scoring with dead-stone, seki and unfinished-border handling.
class Scorer {
  /// Ownership magnitude beyond which a chain is judged dead.
  static const deadThreshold = 0.5;

  /// Guesses dead stones from engine ownership (+1 Black .. -1 White).
  /// Under territory rules, defender groups in a sealed "bent four in the
  /// corner" are also marked dead (Japanese 1989 rules).
  static Set<Point> guessDeadStones(Board board, List<double>? ownership,
      {Ruleset rules = Ruleset.japanese}) {
    final dead = <Point>{};
    if (ownership != null) {
      for (final chain in board.chains) {
        final colour = board[chain.first]!;
        final mean = chain
                .map((p) => ownership[p.index(board.size)])
                .reduce((a, b) => a + b) /
            chain.length;
        final own = colour == Stone.black ? mean : -mean;
        if (own < -deadThreshold) dead.addAll(chain);
      }
    }
    if (rules.scoring == ScoringType.territory) {
      _applyBentFour(board, dead);
    }
    return dead;
  }

  /// Toggles the life/death status of the chain at [p].
  static Set<Point> toggleDead(Board board, Set<Point> dead, Point p) {
    if (board[p] == null) return dead;
    final chain = board.chainAt(p);
    final next = Set<Point>.of(dead);
    if (dead.contains(p)) {
      next.removeAll(chain);
    } else {
      next.addAll(chain);
    }
    return next;
  }

  static ScoreResult scoreGame(Game game,
          {required Set<Point> deadStones, List<double>? ownership}) =>
      score(
        board: game.board,
        rules: game.rules,
        komi: game.setup.komi,
        handicap: game.handicapStones.length,
        blackCaptures: game.prisoners(Stone.black),
        whiteCaptures: game.prisoners(Stone.white),
        deadStones: deadStones,
        ownership: ownership,
      );

  static ScoreResult score({
    required Board board,
    required Ruleset rules,
    required double komi,
    int handicap = 0,
    int blackCaptures = 0,
    int whiteCaptures = 0,
    Set<Point> deadStones = const {},
    List<double>? ownership,
  }) {
    final size = board.size;
    final cleared = board.without(deadStones);
    final status = List<PointStatus>.filled(size * size, PointStatus.dame);

    var deadBlack = 0, deadWhite = 0;
    for (final p in deadStones) {
      if (board[p] == Stone.black) deadBlack++;
      if (board[p] == Stone.white) deadWhite++;
    }

    // --- Seki detection -------------------------------------------------
    final regions = _emptyRegions(cleared);
    final sekiPoints = <Point>{};
    for (final r in regions) {
      if (r.borders.length != 2) continue;
      for (final p in r.points) {
        if (_isSekiPoint(cleared, p, ownership)) sekiPoints.add(p);
      }
    }
    final sekiStones = <Point>{};
    for (final p in sekiPoints) {
      for (final n in cleared.neighbors(p)) {
        if (cleared[n] != null && !sekiStones.contains(n)) {
          sekiStones.addAll(cleared.chainAt(n));
        }
      }
    }

    // --- Region classification -------------------------------------------
    var bt = 0, wt = 0;
    final dame = <Point>{};
    final openGaps = <Point>{};
    final unsettled = <Point>{};
    for (final r in regions) {
      if (r.borders.length == 1) {
        final owner = r.borders.first;
        final inSeki = rules.scoring == ScoringType.territory &&
            r.adjacentStones.any(sekiStones.contains);
        for (final p in r.points) {
          if (inSeki) {
            status[p.index(size)] = PointStatus.seki;
          } else {
            status[p.index(size)] = owner == Stone.black
                ? PointStatus.blackTerritory
                : PointStatus.whiteTerritory;
          }
        }
        if (!inSeki) {
          if (owner == Stone.black) {
            bt += r.points.length;
          } else {
            wt += r.points.length;
          }
        }
      } else {
        for (final p in r.points) {
          final s = sekiPoints.contains(p) ? PointStatus.seki : PointStatus.dame;
          status[p.index(size)] = s;
          if (s == PointStatus.dame) dame.add(p);
        }
        if (r.borders.length == 2) {
          if (_isUnsettled(r, ownership, size)) {
            unsettled.addAll(r.points);
          } else {
            openGaps.addAll(_openGapsIn(cleared, r, sekiPoints, ownership, rules));
          }
        } else if (r.borders.isEmpty) {
          unsettled.addAll(r.points); // empty board
        }
      }
    }

    // Under territory scoring, the points where dead stones stood are already
    // counted as territory above (they were removed before region-finding).
    for (final p in board.points) {
      final s = board[p];
      if (s == null) continue;
      if (deadStones.contains(p)) {
        status[p.index(size)] =
            s == Stone.black ? PointStatus.deadBlack : PointStatus.deadWhite;
      } else {
        status[p.index(size)] =
            s == Stone.black ? PointStatus.blackStone : PointStatus.whiteStone;
      }
    }

    return ScoreResult(
      rules: rules,
      komi: komi,
      size: size,
      status: status,
      blackTerritory: bt,
      whiteTerritory: wt,
      blackStones: cleared.countStones(Stone.black),
      whiteStones: cleared.countStones(Stone.white),
      blackPrisoners: blackCaptures + deadWhite,
      whitePrisoners: whiteCaptures + deadBlack,
      handicapBonus: rules.scoring == ScoringType.area
          ? rules.whiteHandicapBonus(handicap)
          : 0,
      deadStones: Set.unmodifiable(deadStones),
      sekiStones: sekiStones,
      dame: dame,
      openGaps: openGaps,
      unsettled: unsettled,
    );
  }

  /// A neutral region that is too big to be dame and is not simply one
  /// side's territory with a gap in its wall.
  static bool _isUnsettled(_Region r, List<double>? ownership, int size) {
    if (r.points.length <= 3) return false;
    if (ownership == null) return true;
    final strong =
        r.points.where((p) => ownership[p.index(size)].abs() > 0.6).length;
    return strong < r.points.length * 0.5;
  }

  /// A neutral point where neither side can play without putting its own
  /// chain into atari (and without capturing) - the hallmark of seki.
  /// Engine ownership near zero for the point and both neighbouring groups
  /// is accepted as a secondary signal for larger seki shapes.
  static bool _isSekiPoint(Board b, Point p, List<double>? ownership) {
    var bothSelfAtari = true;
    for (final c in Stone.values) {
      final r = b.tryPlay(c, p, allowSuicide: true);
      if (r == null) continue;
      if (r.captured.isNotEmpty) {
        bothSelfAtari = false;
        break;
      }
      final own = r.board.chainAt(p);
      if (own.isNotEmpty && r.board.libertiesOf(own).length > 1) {
        bothSelfAtari = false;
        break;
      }
    }
    if (bothSelfAtari) return true;
    if (ownership == null) return false;

    final size = b.size;
    if (ownership[p.index(size)].abs() > 0.3) return false;
    final colours = <Stone>{};
    for (final n in b.neighbors(p)) {
      final s = b[n];
      if (s == null) continue;
      final chain = b.chainAt(n);
      final mean =
          chain.map((q) => ownership[q.index(size)]).reduce((a, c) => a + c) /
              chain.length;
      if (mean.abs() > 0.4) return false;
      colours.add(s);
    }
    return colours.length == 2;
  }

  /// Points in a two-coloured region that still need playing.
  static Iterable<Point> _openGapsIn(Board b, _Region r, Set<Point> sekiPoints,
      List<double>? ownership, Ruleset rules) sync* {
    final size = b.size;
    // 1) An unclosed border: the region is mostly owned by one side but
    //    leaks into the opponent's stones somewhere.
    if (ownership != null) {
      final sum =
          r.points.map((p) => ownership[p.index(size)]).reduce((a, c) => a + c);
      final strong = r.points.where((p) => ownership[p.index(size)].abs() > 0.6);
      if (strong.isNotEmpty) {
        final owner = sum >= 0 ? Stone.black : Stone.white;
        for (final p in r.points) {
          if (sekiPoints.contains(p)) continue;
          final touchesIntruder = b.neighbors(p).any((n) => b[n] == owner.opponent);
          if (touchesIntruder || ownership[p.index(size)].abs() < 0.6) yield p;
        }
        return;
      }
    }
    // 2) Dame: always worth a point under area scoring; under territory
    //    scoring only when filling it forces a protective move (teire).
    for (final p in r.points) {
      if (sekiPoints.contains(p)) continue;
      if (rules.scoring == ScoringType.area || _createsAtari(b, p)) yield p;
    }
  }

  /// Whether either side playing [p] would put an enemy chain into atari
  /// without self-atari - meaning a protective move is needed.
  static bool _createsAtari(Board b, Point p) {
    for (final c in Stone.values) {
      final r = b.tryPlay(c, p);
      if (r == null) continue;
      final nb = r.board;
      final own = nb.chainAt(p);
      if (nb.libertiesOf(own).length <= 1) continue;
      for (final n in nb.neighbors(p)) {
        if (nb[n] == c.opponent && nb.libertiesOf(nb.chainAt(n)).length == 1) {
          return true;
        }
      }
    }
    return false;
  }

  static List<_Region> _emptyRegions(Board b) {
    final seen = <Point>{};
    final out = <_Region>[];
    for (final start in b.points) {
      if (b[start] != null || seen.contains(start)) continue;
      final pts = <Point>{start};
      final borders = <Stone>{};
      final adj = <Point>{};
      final stack = [start];
      seen.add(start);
      while (stack.isNotEmpty) {
        final q = stack.removeLast();
        for (final n in b.neighbors(q)) {
          final s = b[n];
          if (s == null) {
            if (seen.add(n)) {
              pts.add(n);
              stack.add(n);
            }
          } else {
            borders.add(s);
            adj.add(n);
          }
        }
      }
      out.add(_Region(pts, borders, adj));
    }
    return out;
  }

  // --- Bent four in the corner --------------------------------------------

  static void _applyBentFour(Board board, Set<Point> dead) {
    final size = board.size;
    final corners = [
      const Point(0, 0),
      Point(size - 1, 0),
      Point(0, size - 1),
      Point(size - 1, size - 1),
    ];
    for (final corner in corners) {
      for (final defender in Stone.values) {
        // The eye space: points that are not defender stones, connected to
        // the corner, bounded entirely by defender stones.
        if (board[corner] == defender) continue;
        final space = <Point>{corner};
        final stack = [corner];
        var tooBig = false;
        while (stack.isNotEmpty && !tooBig) {
          final q = stack.removeLast();
          for (final n in board.neighbors(q)) {
            if (board[n] != defender && space.add(n)) {
              stack.add(n);
              if (space.length > 4) tooBig = true;
            }
          }
        }
        if (tooBig || space.length != 4 || !_isBentAtCorner(space, corner)) {
          continue;
        }
        // Defender chains around the eye space.
        final group = <Point>{};
        for (final q in space) {
          for (final n in board.neighbors(q)) {
            if (board[n] == defender && !group.contains(n)) {
              group.addAll(board.chainAt(n));
            }
          }
        }
        // Sealed: no liberties outside the eye space (dead attacker stones
        // outside are ignored as they would be removed).
        final cleared = board.without(dead.difference(space));
        final libs = cleared.libertiesOf(group);
        if (libs.every(space.contains)) {
          dead.addAll(group);
          dead.removeAll(space); // attacker stones inside are alive
        }
      }
    }
  }

  /// An L-shaped tetromino whose bend is at the corner point.
  static bool _isBentAtCorner(Set<Point> s, Point corner) {
    final neighboursInShape = s
        .where((p) => (p.x - corner.x).abs() + (p.y - corner.y).abs() == 1)
        .length;
    if (neighboursInShape != 2) return false;
    // Remaining point extends one arm in a straight line from the corner.
    final xs = s.map((p) => p.x).toSet(), ys = s.map((p) => p.y).toSet();
    return (xs.length == 3 && ys.length == 2) || (xs.length == 2 && ys.length == 3);
  }
}

class _Region {
  final Set<Point> points;
  final Set<Stone> borders;
  final Set<Point> adjacentStones;
  _Region(this.points, this.borders, this.adjacentStones);
}
