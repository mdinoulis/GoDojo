import 'point.dart';

enum ScoringType { territory, area }

enum KoRule {
  /// Only immediate recapture of a single-stone ko is forbidden.
  simple,

  /// A move may not recreate any earlier whole-board position.
  positionalSuperko,

  /// A move may not recreate an earlier position with the same side to move.
  situationalSuperko,
}

/// How many extra points White receives per handicap stone under area scoring.
enum HandicapBonus { none, n, nMinusOne }

/// Supported rulesets. [katagoName] is the shorthand accepted by KataGo.
enum Ruleset {
  japanese('Japanese', 'japanese', ScoringType.territory, KoRule.simple,
      suicide: false, handicapBonus: HandicapBonus.none, defaultKomi: 6.5),
  korean('Korean', 'korean', ScoringType.territory, KoRule.simple,
      suicide: false, handicapBonus: HandicapBonus.none, defaultKomi: 6.5),
  chinese('Chinese', 'chinese', ScoringType.area, KoRule.positionalSuperko,
      suicide: false, handicapBonus: HandicapBonus.n, defaultKomi: 7.5),
  aga('AGA', 'aga', ScoringType.area, KoRule.situationalSuperko,
      suicide: false, handicapBonus: HandicapBonus.nMinusOne, defaultKomi: 7.5),
  newZealand('New Zealand', 'new-zealand', ScoringType.area,
      KoRule.situationalSuperko,
      suicide: true, handicapBonus: HandicapBonus.none, defaultKomi: 7.0),
  trompTaylor('Tromp-Taylor', 'tromp-taylor', ScoringType.area,
      KoRule.positionalSuperko,
      suicide: true, handicapBonus: HandicapBonus.none, defaultKomi: 7.5);

  const Ruleset(this.displayName, this.katagoName, this.scoring, this.ko,
      {required this.suicide,
      required this.handicapBonus,
      required this.defaultKomi});

  final String displayName;
  final String katagoName;
  final ScoringType scoring;
  final KoRule ko;
  final bool suicide;
  final HandicapBonus handicapBonus;
  final double defaultKomi;

  /// Extra points given to White for [handicap] stones (area scoring only).
  int whiteHandicapBonus(int handicap) {
    if (handicap < 2) return 0;
    switch (handicapBonus) {
      case HandicapBonus.none:
        return 0;
      case HandicapBonus.n:
        return handicap;
      case HandicapBonus.nMinusOne:
        return handicap - 1;
    }
  }

  static Ruleset fromName(String s) {
    final t = s.toLowerCase().replaceAll(RegExp(r'[\s_]'), '-');
    for (final r in values) {
      if (r.katagoName == t || r.name.toLowerCase() == t.replaceAll('-', '')) {
        return r;
      }
    }
    if (t == 'nz') return newZealand;
    if (t == 'tt') return trompTaylor;
    return japanese;
  }
}

/// Fixed handicap stone placement (Japanese convention), as seen by Black.
List<Point> handicapPoints(int size, int stones) {
  if (stones < 2) return const [];
  final lo = size >= 13 ? 3 : 2;
  final hi = size - 1 - lo;
  final mid = size ~/ 2;
  final hasMid = size.isOdd && size >= 9;
  final maxStones = hasMid ? 9 : 4;
  if (stones > maxStones) {
    throw ArgumentError('At most $maxStones handicap stones on ${size}x$size');
  }
  final topRight = Point(hi, lo),
      bottomLeft = Point(lo, hi),
      bottomRight = Point(hi, hi),
      topLeft = Point(lo, lo),
      centre = Point(mid, mid),
      leftMid = Point(lo, mid),
      rightMid = Point(hi, mid),
      topMid = Point(mid, lo),
      bottomMid = Point(mid, hi);
  final corners = [topRight, bottomLeft, bottomRight, topLeft];
  switch (stones) {
    case 2:
    case 3:
    case 4:
      return corners.sublist(0, stones);
    case 5:
      return [...corners, centre];
    case 6:
      return [...corners, leftMid, rightMid];
    case 7:
      return [...corners, leftMid, rightMid, centre];
    case 8:
      return [...corners, leftMid, rightMid, topMid, bottomMid];
    default:
      return [...corners, leftMid, rightMid, topMid, bottomMid, centre];
  }
}

/// Maximum fixed handicap for a board size.
int maxHandicap(int size) => size.isOdd && size >= 9 ? 9 : 4;
