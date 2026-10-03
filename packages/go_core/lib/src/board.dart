import 'dart:math';

import 'point.dart';

/// Result of placing a stone on a [Board].
class PlayResult {
  final Board board;
  final List<Point> captured;
  const PlayResult(this.board, this.captured);
}

/// Immutable Go board position (stones only - no side to move, ko or history).
class Board {
  static const maxSize = 19;

  final int size;
  final List<Stone?> _cells;
  final int hash;

  Board(this.size)
      : assert(size >= 2 && size <= maxSize),
        _cells = List<Stone?>.filled(size * size, null),
        hash = 0;

  Board._(this.size, this._cells, this.hash);

  /// Creates a board with the given stones already placed (no captures).
  factory Board.withStones(int size, Map<Point, Stone> stones) {
    final cells = List<Stone?>.filled(size * size, null);
    var h = 0;
    stones.forEach((p, s) {
      cells[p.index(size)] = s;
      h ^= _zobrist(p.index(size), s);
    });
    return Board._(size, cells, h);
  }

  Stone? operator [](Point p) => _cells[p.y * size + p.x];
  Stone? at(int x, int y) => _cells[y * size + x];

  bool contains(Point p) => p.x >= 0 && p.y >= 0 && p.x < size && p.y < size;
  bool isEmptyAt(Point p) => this[p] == null;

  Iterable<Point> get points sync* {
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        yield Point(x, y);
      }
    }
  }

  Iterable<Point> neighbors(Point p) sync* {
    if (p.x > 0) yield Point(p.x - 1, p.y);
    if (p.x < size - 1) yield Point(p.x + 1, p.y);
    if (p.y > 0) yield Point(p.x, p.y - 1);
    if (p.y < size - 1) yield Point(p.x, p.y + 1);
  }

  /// All stones of the chain (string) containing [p]. Empty if [p] is empty.
  Set<Point> chainAt(Point p) {
    final colour = this[p];
    if (colour == null) return {};
    final chain = <Point>{p};
    final stack = [p];
    while (stack.isNotEmpty) {
      final q = stack.removeLast();
      for (final n in neighbors(q)) {
        if (this[n] == colour && chain.add(n)) stack.add(n);
      }
    }
    return chain;
  }

  Set<Point> libertiesOf(Iterable<Point> chain) {
    final libs = <Point>{};
    for (final q in chain) {
      for (final n in neighbors(q)) {
        if (this[n] == null) libs.add(n);
      }
    }
    return libs;
  }

  /// All chains on the board.
  List<Set<Point>> get chains {
    final seen = <Point>{};
    final result = <Set<Point>>[];
    for (final p in points) {
      if (this[p] != null && !seen.contains(p)) {
        final c = chainAt(p);
        seen.addAll(c);
        result.add(c);
      }
    }
    return result;
  }

  int countStones(Stone s) => _cells.where((c) => c == s).length;

  /// Places [colour] at [p], removing captured enemy stones (and the played
  /// chain itself if it is suicide and [allowSuicide] is true).
  /// Returns null if the point is occupied or the move is a forbidden suicide.
  PlayResult? tryPlay(Stone colour, Point p, {bool allowSuicide = false}) {
    if (!contains(p) || this[p] != null) return null;
    final cells = List<Stone?>.of(_cells);
    var h = hash ^ _zobrist(p.index(size), colour);
    cells[p.index(size)] = colour;
    final next = Board._(size, cells, h);

    final captured = <Point>[];
    for (final n in neighbors(p)) {
      if (cells[n.index(size)] == colour.opponent) {
        final chain = next.chainAt(n);
        if (next.libertiesOf(chain).isEmpty) {
          for (final q in chain) {
            if (cells[q.index(size)] != null) {
              cells[q.index(size)] = null;
              h ^= _zobrist(q.index(size), colour.opponent);
              captured.add(q);
            }
          }
        }
      }
    }
    var board = Board._(size, cells, h);
    if (captured.isEmpty) {
      final own = board.chainAt(p);
      if (board.libertiesOf(own).isEmpty) {
        if (!allowSuicide) return null;
        for (final q in own) {
          cells[q.index(size)] = null;
          h ^= _zobrist(q.index(size), colour);
        }
        board = Board._(size, cells, h);
      }
    }
    return PlayResult(board, captured);
  }

  /// Returns a copy with the given points cleared.
  Board without(Iterable<Point> pts) {
    final cells = List<Stone?>.of(_cells);
    var h = hash;
    for (final p in pts) {
      final s = cells[p.index(size)];
      if (s != null) {
        cells[p.index(size)] = null;
        h ^= _zobrist(p.index(size), s);
      }
    }
    return Board._(size, cells, h);
  }

  /// Multi-line text diagram (X = black, O = white, . = empty), top row first.
  String toAscii() {
    final sb = StringBuffer();
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final s = at(x, y);
        sb.write(s == Stone.black ? 'X' : s == Stone.white ? 'O' : '.');
      }
      if (y < size - 1) sb.writeln();
    }
    return sb.toString();
  }

  /// Parses a diagram as produced by [toAscii]. Whitespace between columns is
  /// ignored; `X`/`B` = black, `O`/`W` = white, anything else = empty.
  factory Board.fromAscii(String diagram) {
    final rows = diagram
        .split('\n')
        .map((r) => r.replaceAll(RegExp(r'\s'), ''))
        .where((r) => r.isNotEmpty)
        .toList();
    final size = rows.length;
    final stones = <Point, Stone>{};
    for (var y = 0; y < size; y++) {
      if (rows[y].length != size) {
        throw FormatException('Row $y has ${rows[y].length} columns, expected $size');
      }
      for (var x = 0; x < size; x++) {
        final c = rows[y][x];
        if (c == 'X' || c == 'B') stones[Point(x, y)] = Stone.black;
        if (c == 'O' || c == 'W') stones[Point(x, y)] = Stone.white;
      }
    }
    return Board.withStones(size, stones);
  }

  @override
  bool operator ==(Object other) {
    if (other is! Board || other.size != size || other.hash != hash) {
      return false;
    }
    for (var i = 0; i < _cells.length; i++) {
      if (_cells[i] != other._cells[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => hash;

  static final List<int> _table = () {
    final r = Random(0x5EED);
    int rnd() => (r.nextInt(1 << 32) << 32) ^ r.nextInt(1 << 32);
    return List<int>.generate(maxSize * maxSize * 2, (_) => rnd());
  }();

  static int _zobrist(int index, Stone s) =>
      _table[index * 2 + (s == Stone.black ? 0 : 1)];
}
