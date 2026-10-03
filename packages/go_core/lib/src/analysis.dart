import 'point.dart';

/// One candidate move from an engine search. Winrate and score are always
/// from BLACK's perspective (positive = good for Black).
class MoveCandidate {
  /// Null means pass.
  final Point? point;
  final int order;
  final int visits;
  final double winrate;
  final double scoreLead;
  final double prior;
  final double? humanPrior;
  final List<Point?> pv;

  const MoveCandidate({
    required this.point,
    required this.order,
    required this.visits,
    required this.winrate,
    required this.scoreLead,
    required this.prior,
    this.humanPrior,
    this.pv = const [],
  });

  bool get isPass => point == null;

  /// Score/winrate from [player]'s point of view.
  double scoreFor(Stone player) => player == Stone.black ? scoreLead : -scoreLead;
  double winrateFor(Stone player) =>
      player == Stone.black ? winrate : 1 - winrate;
}

/// Engine evaluation of a single position. All values from BLACK's view.
class PositionAnalysis {
  final Stone toMove;
  final int visits;
  final double winrate;
  final double scoreLead;
  final double? scoreStdev;

  /// Candidates sorted best first (by engine order).
  final List<MoveCandidate> moves;

  /// Row-major (top row first), +1 = Black owns, -1 = White owns.
  final List<double>? ownership;

  /// Row-major, length size*size + 1 (last = pass); -1 marks illegal moves.
  final List<double>? policy;
  final List<double>? humanPolicy;
  final bool isPartial;

  const PositionAnalysis({
    required this.toMove,
    required this.visits,
    required this.winrate,
    required this.scoreLead,
    this.scoreStdev,
    required this.moves,
    this.ownership,
    this.policy,
    this.humanPolicy,
    this.isPartial = false,
  });

  MoveCandidate? get best => moves.isEmpty ? null : moves.first;

  MoveCandidate? candidateFor(Point? p) {
    for (final m in moves) {
      if (m.point == p) return m;
    }
    return null;
  }

  double? ownershipAt(Point p, int size) => ownership?[p.index(size)];
}
