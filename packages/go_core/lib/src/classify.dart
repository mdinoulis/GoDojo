import 'analysis.dart';
import 'point.dart';

/// Move quality categories, best to worst.
enum MoveQuality {
  tesuji('Tesuji'),
  great('Great move'),
  good('Good move'),
  poor('Poor move'),
  mistake('Mistake'),
  blunder('Blunder');

  const MoveQuality(this.label);
  final String label;
}

/// Thresholds (in points and winrate) used by [MoveClassifier].
class ClassifierThresholds {
  final double good; // max point loss for "good"
  final double poor; // max point loss for "poor"
  final double mistake; // max point loss for "mistake"
  final double mistakeWinrate; // winrate loss that makes it at least a mistake
  final double blunderWinrate; // winrate loss that makes it a blunder
  final double bestTolerance; // loss still considered "the best move"
  final double greatMargin; // how much worse the alternatives must be
  final double tesujiMaxPrior; // "hard to find" - low policy prior
  final double tesujiMargin; // gain over the second-best move

  const ClassifierThresholds({
    this.good = 1.0,
    this.poor = 3.0,
    this.mistake = 8.0,
    this.mistakeWinrate = 0.10,
    this.blunderWinrate = 0.20,
    this.bestTolerance = 0.5,
    this.greatMargin = 2.0,
    this.tesujiMaxPrior = 0.05,
    this.tesujiMargin = 3.0,
  });
}

class MoveRating {
  final MoveQuality quality;

  /// Points lost compared to the engine's best move (>= 0).
  final double pointLoss;

  /// Winrate lost compared to the best move, in [0,1].
  final double winrateLoss;
  final Stone player;
  final Point? played;
  final MoveCandidate? best;

  /// Engine moves that are better than the one played (best first).
  final List<MoveCandidate> betterMoves;

  const MoveRating({
    required this.quality,
    required this.pointLoss,
    required this.winrateLoss,
    required this.player,
    required this.played,
    required this.best,
    required this.betterMoves,
  });
}

class MoveClassifier {
  final ClassifierThresholds t;
  const MoveClassifier([this.t = const ClassifierThresholds()]);

  /// Rates [played] by [player] given the analysis of the position before the
  /// move. [after] (analysis of the resulting position) gives a more reliable
  /// value for moves the engine barely searched.
  MoveRating classify({
    required PositionAnalysis before,
    required Point? played,
    required Stone player,
    PositionAnalysis? after,
  }) {
    final best = before.best;
    if (best == null) {
      return MoveRating(
          quality: MoveQuality.good,
          pointLoss: 0,
          winrateLoss: 0,
          player: player,
          played: played,
          best: null,
          betterMoves: const []);
    }
    final bestScore = best.scoreFor(player);
    final bestWr = best.winrateFor(player);

    final cand = before.candidateFor(played);
    final reliable = cand != null &&
        cand.visits >= 2 &&
        cand.visits >= best.visits * 0.02;
    double playedScore, playedWr;
    if (reliable || after == null) {
      playedScore = cand?.scoreFor(player) ??
          (after != null
              ? (player == Stone.black ? after.scoreLead : -after.scoreLead)
              : bestScore);
      playedWr = cand?.winrateFor(player) ??
          (after != null
              ? (player == Stone.black ? after.winrate : 1 - after.winrate)
              : bestWr);
    } else {
      playedScore = player == Stone.black ? after.scoreLead : -after.scoreLead;
      playedWr = player == Stone.black ? after.winrate : 1 - after.winrate;
    }

    final loss = (bestScore - playedScore).clamp(0.0, double.infinity);
    final wrLoss = (bestWr - playedWr).clamp(0.0, 1.0);

    final better = [
      for (final m in before.moves)
        if (m.point != played &&
            m.visits >= 2 &&
            m.scoreFor(player) - playedScore > t.bestTolerance)
          m
    ];

    MoveQuality q;
    final isBest = played == best.point || loss <= t.bestTolerance;
    if (isBest) {
      final others = before.moves
          .where((m) => m.point != played && m.visits >= 2)
          .toList();
      final secondScore = others.isEmpty ? null : others.first.scoreFor(player);
      final gap = secondScore == null ? 0.0 : playedScore - secondScore;
      final prior = cand?.prior ?? 1.0;
      if (secondScore != null &&
          prior < t.tesujiMaxPrior &&
          gap >= t.tesujiMargin) {
        q = MoveQuality.tesuji;
      } else if (secondScore != null && gap >= t.greatMargin) {
        q = MoveQuality.great;
      } else {
        q = MoveQuality.good;
      }
    } else if (wrLoss >= t.blunderWinrate || loss > t.mistake) {
      q = MoveQuality.blunder;
    } else if (wrLoss >= t.mistakeWinrate || loss > t.poor) {
      q = MoveQuality.mistake;
    } else if (loss > t.good) {
      q = MoveQuality.poor;
    } else {
      q = MoveQuality.good;
    }

    return MoveRating(
      quality: q,
      pointLoss: loss.toDouble(),
      winrateLoss: wrLoss.toDouble(),
      player: player,
      played: played,
      best: best,
      betterMoves: better,
    );
  }
}
