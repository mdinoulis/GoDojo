import 'board.dart';
import 'point.dart';
import 'rules.dart';

/// Parameters fixed at the start of a game.
class GameSetup {
  final int size;
  final Ruleset rules;
  final double komi;
  final int handicap;

  const GameSetup({
    this.size = 19,
    this.rules = Ruleset.japanese,
    this.komi = 6.5,
    this.handicap = 0,
  });

  GameSetup copyWith({int? size, Ruleset? rules, double? komi, int? handicap}) =>
      GameSetup(
        size: size ?? this.size,
        rules: rules ?? this.rules,
        komi: komi ?? this.komi,
        handicap: handicap ?? this.handicap,
      );

  /// Conventional komi: the ruleset default for even games, 0.5 with handicap.
  static double defaultKomi(Ruleset rules, int handicap) =>
      handicap >= 2 ? 0.5 : rules.defaultKomi;
}

enum ResultReason { score, resignation, time, forfeit }

class GameResult {
  final Stone? winner; // null = jigo (draw)
  final ResultReason reason;
  final double? margin;
  const GameResult(this.winner, this.reason, [this.margin]);

  /// SGF RE value, e.g. "B+R", "W+3.5", "0".
  String toSgf() {
    if (winner == null) return '0';
    final suffix = switch (reason) {
      ResultReason.resignation => 'R',
      ResultReason.time => 'T',
      ResultReason.forfeit => 'F',
      ResultReason.score => _fmt(margin ?? 0),
    };
    return '${winner!.letter}+$suffix';
  }

  static GameResult? fromSgf(String re) {
    final t = re.trim().toUpperCase();
    if (t == '0' || t == 'DRAW' || t == 'JIGO') {
      return const GameResult(null, ResultReason.score, 0);
    }
    final m = RegExp(r'^([BW])\+(.*)$').firstMatch(t);
    if (m == null) return null;
    final w = Stone.fromLetter(m[1]!);
    final rest = m[2]!;
    if (rest.startsWith('R')) return GameResult(w, ResultReason.resignation);
    if (rest.startsWith('T')) return GameResult(w, ResultReason.time);
    if (rest.startsWith('F')) return GameResult(w, ResultReason.forfeit);
    return GameResult(w, ResultReason.score, double.tryParse(rest));
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  @override
  String toString() => toSgf();
}

enum IllegalReason { occupied, suicide, ko, superko, gameOver, offBoard }

class IllegalMoveException implements Exception {
  final IllegalReason reason;
  final Move move;
  IllegalMoveException(this.reason, this.move);
  @override
  String toString() => 'Illegal move $move: ${reason.name}';
}

class _Node {
  final Board board;
  final Move? move; // null for the root
  final Stone toMove;
  final int blackPrisoners; // white stones captured by black
  final int whitePrisoners; // black stones captured by white
  final List<Point> captured;
  const _Node(this.board, this.move, this.toMove, this.blackPrisoners,
      this.whitePrisoners, this.captured);
}

/// A game record (main line) with legal-move checking and multi-step
/// undo / redo. Which colour the user controls is decided by the caller,
/// so sides can be switched at any time.
class Game {
  final GameSetup setup;
  final List<Point> handicapStones;
  final List<_Node> _nodes = [];
  final List<Move> _redo = [];
  GameResult? _result;

  Game(this.setup, {List<Point>? handicapStones})
      : handicapStones = List.unmodifiable(
            handicapStones ?? handicapPoints(setup.size, setup.handicap)) {
    final board = Board.withStones(
        setup.size, {for (final p in this.handicapStones) p: Stone.black});
    final first = this.handicapStones.length >= 2 ? Stone.white : Stone.black;
    _nodes.add(_Node(board, null, first, 0, 0, const []));
  }

  /// An independent copy of the game (main line and redo moves).
  Game copy() {
    final g = Game(setup, handicapStones: handicapStones);
    for (final m in moves) {
      g.playMove(m);
    }
    for (final m in _redo) {
      g._redo.add(m);
    }
    g._result = _result;
    return g;
  }

  int get size => setup.size;
  Ruleset get rules => setup.rules;
  Board get board => _nodes.last.board;
  Stone get toMove => _nodes.last.toMove;
  Stone get firstPlayer => _nodes.first.toMove;

  /// Number of moves played (passes included).
  int get moveNumber => _nodes.length - 1;
  List<Move> get moves => [for (final n in _nodes.skip(1)) n.move!];
  Move? get lastMove => _nodes.last.move;
  List<Point> get lastCaptured => _nodes.last.captured;

  /// Board after [moveCount] moves.
  Board boardAt(int moveCount) => _nodes[moveCount].board;
  Stone toMoveAt(int moveCount) => _nodes[moveCount].toMove;

  /// Stones captured BY [colour] (prisoners it holds).
  int prisoners(Stone colour) => colour == Stone.black
      ? _nodes.last.blackPrisoners
      : _nodes.last.whitePrisoners;

  GameResult? get result => _result;
  bool get isOver => _result != null || bothPassed;

  /// True when the last two moves were passes (the game ends; count it).
  bool get bothPassed =>
      _nodes.length >= 3 &&
      _nodes.last.move!.isPass &&
      _nodes[_nodes.length - 2].move!.isPass;

  bool get canUndo => _nodes.length > 1;
  bool get canRedo => _redo.isNotEmpty;

  /// Why [p] is illegal for the side to move, or null if it is legal.
  IllegalReason? illegalReason(Point p) {
    try {
      _resolve(Move(toMove, p));
      return null;
    } on IllegalMoveException catch (e) {
      return e.reason;
    }
  }

  bool isLegal(Point p) => illegalReason(p) == null;

  /// Plays a stone (or a pass if [p] is null) for the side to move.
  void play(Point? p) => playMove(Move(toMove, p));

  void pass() => play(null);

  /// Plays [move]. If the colour isn't the side to move, it is still played
  /// (useful for setting up positions and for SGF files with consecutive moves).
  void playMove(Move move, {bool keepRedo = false}) {
    if (_result != null) {
      throw IllegalMoveException(IllegalReason.gameOver, move);
    }
    _nodes.add(_resolve(move));
    if (!keepRedo) {
      if (_redo.isNotEmpty && _redo.last == move) {
        _redo.removeLast();
      } else {
        _redo.clear();
      }
    }
  }

  _Node _resolve(Move move) {
    final prev = _nodes.last;
    if (move.isPass) {
      return _Node(prev.board, move, move.color.opponent, prev.blackPrisoners,
          prev.whitePrisoners, const []);
    }
    final p = move.point!;
    if (!prev.board.contains(p)) {
      throw IllegalMoveException(IllegalReason.offBoard, move);
    }
    if (prev.board[p] != null) {
      throw IllegalMoveException(IllegalReason.occupied, move);
    }
    final r = prev.board.tryPlay(move.color, p, allowSuicide: rules.suicide);
    if (r == null) throw IllegalMoveException(IllegalReason.suicide, move);
    final next = r.board;
    final nextToMove = move.color.opponent;

    switch (rules.ko) {
      case KoRule.simple:
        if (_nodes.length >= 2 &&
            r.captured.length == 1 &&
            next == _nodes[_nodes.length - 2].board) {
          throw IllegalMoveException(IllegalReason.ko, move);
        }
      case KoRule.positionalSuperko:
        if (_nodes.any((n) => n.board == next)) {
          throw IllegalMoveException(
              _isSimpleKo(next, r) ? IllegalReason.ko : IllegalReason.superko,
              move);
        }
      case KoRule.situationalSuperko:
        if (_nodes.any((n) => n.toMove == nextToMove && n.board == next)) {
          throw IllegalMoveException(
              _isSimpleKo(next, r) ? IllegalReason.ko : IllegalReason.superko,
              move);
        }
    }

    final suicided = next[p] == null ? 1 : 0; // own stone(s) removed
    final selfLost = suicided == 0
        ? 0
        : prev.board.countStones(move.color) + 1 - next.countStones(move.color);
    var bp = prev.blackPrisoners, wp = prev.whitePrisoners;
    if (move.color == Stone.black) {
      bp += r.captured.length;
      wp += selfLost;
    } else {
      wp += r.captured.length;
      bp += selfLost;
    }
    return _Node(next, move, nextToMove, bp, wp, r.captured);
  }

  bool _isSimpleKo(Board next, PlayResult r) =>
      _nodes.length >= 2 &&
      r.captured.length == 1 &&
      next == _nodes[_nodes.length - 2].board;

  /// Takes back [count] moves (they become available to [redo]).
  /// Also clears a resignation/result.
  int undo([int count = 1]) {
    var n = 0;
    _result = null;
    while (n < count && _nodes.length > 1) {
      _redo.add(_nodes.removeLast().move!);
      n++;
    }
    return n;
  }

  /// Re-plays up to [count] undone moves.
  int redo([int count = 1]) {
    var n = 0;
    while (n < count && _redo.isNotEmpty) {
      playMove(_redo.last, keepRedo: true);
      _redo.removeLast();
      n++;
    }
    return n;
  }

  /// Moves backward/forward so that exactly [moveCount] moves are on the board.
  void goTo(int moveCount) {
    if (moveCount < moveNumber) {
      undo(moveNumber - moveCount);
    } else if (moveCount > moveNumber) {
      redo(moveCount - moveNumber);
    }
  }

  /// Number of moves available to redo.
  int get redoCount => _redo.length;

  /// Total length of the line including undone moves.
  int get lineLength => moveNumber + _redo.length;

  void resign(Stone loser) =>
      _result = GameResult(loser.opponent, ResultReason.resignation);

  void setResult(GameResult r) => _result = r;
  void clearResult() => _result = null;

  /// Moves with player letters and GTP coordinates, as needed by KataGo.
  List<List<String>> movesForEngine([int? upTo]) => [
        for (final m in moves.take(upTo ?? moveNumber))
          [m.color.letter, m.toGtp(size)]
      ];

  List<List<String>> initialStonesForEngine() =>
      [for (final p in handicapStones) ['B', p.toGtp(size)]];
}
