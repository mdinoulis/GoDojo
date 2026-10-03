import 'package:go_core/go_core.dart';

import 'config.dart';

/// A move chosen by the bot, with the analysis it was based on.
class BotMove {
  final Point? point; // null = pass
  final PositionAnalysis? analysis;
  const BotMove(this.point, this.analysis);
  bool get isPass => point == null;
}

/// Result of rating one move of a game.
class MoveReview {
  final int moveNumber; // 1-based index of the rated move
  final Move move;
  final MoveRating rating;
  final PositionAnalysis before;
  final PositionAnalysis? after;
  const MoveReview(this.moveNumber, this.move, this.rating, this.before, this.after);
}

typedef AnalysisCallback = void Function(PositionAnalysis partial);

/// The engine API used by the app. Positions are given as a [Game] plus the
/// number of moves of its main line to consider ([moveCount], default: all).
abstract class GoEngine {
  Future<void> start();
  Future<void> stop();
  bool get isRunning;

  /// Picks a move for the side to move at [level].
  Future<BotMove> genMove(Game game, BotLevel level);

  /// Evaluates a position: ranked candidate moves, score lead, winrate and
  /// (optionally) ownership. [onPartial] receives live updates.
  Future<PositionAnalysis> analyze(
    Game game, {
    int? moveCount,
    int? maxVisits,
    bool ownership = true,
    AnalysisCallback? onPartial,
  });

  /// Rates move number [moveNumber] (1-based) and suggests better moves.
  Future<MoveReview> rateMove(Game game, int moveNumber, {int? maxVisits});

  /// Analyses every position of the game (for post-game review).
  Future<List<PositionAnalysis>> analyzeGame(
    Game game, {
    int? maxVisits,
    void Function(int done, int total)? onProgress,
  });

  /// Stops all running searches (their partial results are returned).
  Future<void> cancelAll();
}
