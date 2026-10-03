/// Stone colours.
enum Stone {
  black,
  white;

  Stone get opponent => this == Stone.black ? Stone.white : Stone.black;

  /// "B" / "W" as used by GTP, SGF and KataGo.
  String get letter => this == Stone.black ? 'B' : 'W';

  static Stone fromLetter(String s) {
    switch (s.toUpperCase()) {
      case 'B':
        return Stone.black;
      case 'W':
        return Stone.white;
    }
    throw ArgumentError('Not a stone colour: $s');
  }
}

/// A board intersection. `x` is the column (0 = left/"A"), `y` is the row
/// counted from the TOP (0 = top row, i.e. row 19 on a 19x19 board). This
/// matches KataGo's row-major ownership/policy arrays.
class Point {
  final int x;
  final int y;
  const Point(this.x, this.y);

  static const _gtpColumns = 'ABCDEFGHJKLMNOPQRSTUVWXYZ';

  /// GTP coordinate, e.g. "Q16" (column letters skip "I").
  String toGtp(int size) => '${_gtpColumns[x]}${size - y}';

  /// Parses a GTP coordinate. Returns null for "pass" (case-insensitive).
  /// Throws [FormatException] for anything else that isn't on the board.
  static Point? fromGtp(String s, int size) {
    final t = s.trim().toUpperCase();
    if (t == 'PASS') return null;
    if (t.length < 2) throw FormatException('Bad GTP coordinate', s);
    final x = _gtpColumns.indexOf(t[0]);
    final row = int.tryParse(t.substring(1));
    if (x < 0 || x >= size || row == null || row < 1 || row > size) {
      throw FormatException('Bad GTP coordinate', s);
    }
    return Point(x, size - row);
  }

  /// SGF coordinate, e.g. "pd" (x then y, both from top-left).
  String toSgf() =>
      String.fromCharCode(97 + x) + String.fromCharCode(97 + y);

  static Point? fromSgf(String s, int size) {
    if (s.isEmpty || (s == 'tt' && size <= 19)) return null; // pass
    if (s.length != 2) throw FormatException('Bad SGF coordinate', s);
    final x = s.codeUnitAt(0) - 97, y = s.codeUnitAt(1) - 97;
    if (x < 0 || x >= size || y < 0 || y >= size) {
      throw FormatException('Bad SGF coordinate', s);
    }
    return Point(x, y);
  }

  int index(int size) => y * size + x;

  @override
  bool operator ==(Object other) =>
      other is Point && other.x == x && other.y == y;

  @override
  int get hashCode => x * 31 + y;

  @override
  String toString() => 'Point($x,$y)';
}

/// A move: a stone placed at [point], or a pass when [point] is null.
class Move {
  final Stone color;
  final Point? point;
  const Move(this.color, this.point);
  const Move.pass(this.color) : point = null;

  bool get isPass => point == null;

  String toGtp(int size) => point?.toGtp(size) ?? 'pass';

  @override
  bool operator ==(Object other) =>
      other is Move && other.color == color && other.point == point;

  @override
  int get hashCode => Object.hash(color, point);

  @override
  String toString() => 'Move(${color.letter}, ${point ?? 'pass'})';
}
