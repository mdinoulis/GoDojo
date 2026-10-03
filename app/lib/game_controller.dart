import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:go_core/go_core.dart';
import 'package:katago_engine/katago_engine.dart';

import 'engine_service.dart';
import 'settings.dart';

/// State of the end-of-game counting screen.
class ScoringState {
  final PositionAnalysis? analysis;
  final Set<Point> dead;
  final ScoreResult result;

  /// Moves the engine says still gain points (game not really finished).
  final List<Point> engineGaps;
  final bool accepted;

  const ScoringState(this.analysis, this.dead, this.result, this.engineGaps,
      {this.accepted = false});

  bool get isFinished => result.isFinished && engineGaps.isEmpty;
  Set<Point> get allGaps => {...result.openGaps, ...engineGaps};
}

enum BoardOverlay { none, hints, estimate, rating }

/// Drives one game: human input, the bot, analysis tools and counting.
class GameController extends ChangeNotifier {
  final EngineService engines;
  final AppSettings Function() settings;

  Game game;
  GameMode mode;
  Stone humanColour;
  BotLevel level;

  bool botThinking = false;
  bool busy = false; // an analysis request is running
  BoardOverlay overlay = BoardOverlay.none;
  PositionAnalysis? hints;
  PositionAnalysis? estimate;
  MoveReview? rating;
  ScoringState? scoring;

  /// One-shot messages for the UI (snackbars).
  final _messages = StreamController<String>.broadcast();
  Stream<String> get messages => _messages.stream;

  int _generation = 0; // bumps on every position change; drops stale results
  int _botLosingStreak = 0;
  int _botToken = 0;

  GameController({
    required this.engines,
    required this.settings,
    required GameSetup setup,
    required this.mode,
    required this.humanColour,
    required this.level,
  }) : game = Game(setup);

  bool get isVsBot => mode == GameMode.vsBot;
  bool get isHumanTurn => !isVsBot || game.toMove == humanColour;
  bool get isScoring => scoring != null;
  bool get canPlay => !game.isOver && !botThinking && isHumanTurn && !isScoring;

  /// It is the bot's turn but it is waiting (e.g. after navigating back).
  bool get botWaiting =>
      isVsBot && !game.isOver && !isHumanTurn && !botThinking && !isScoring;

  void _say(String m) => _messages.add(m);

  void _positionChanged() {
    _generation++;
    hints = null;
    estimate = null;
    rating = null;
    if (overlay != BoardOverlay.none) overlay = BoardOverlay.none;
    notifyListeners();
  }

  Future<KataGoEngine> _engine() => engines.engineFor(settings());

  // -------------------------------------------------------------------------
  // Playing

  void startIfBotToMove() {
    if (isVsBot && !game.isOver && game.toMove != humanColour) _botMove();
  }

  void tap(Point p) {
    if (isScoring) {
      toggleDead(p);
      return;
    }
    if (!canPlay) return;
    final reason = game.illegalReason(p);
    if (reason != null) {
      _say(switch (reason) {
        IllegalReason.ko => 'Ko: you must play elsewhere first',
        IllegalReason.superko => 'Illegal: repeats an earlier position',
        IllegalReason.suicide => 'Suicide is not allowed under these rules',
        _ => 'Illegal move',
      });
      return;
    }
    game.play(p);
    _afterMove();
  }

  void pass() {
    if (!canPlay) return;
    game.pass();
    _afterMove();
  }

  void resign() {
    if (game.isOver) return;
    final loser = isVsBot ? humanColour : game.toMove;
    _cancelBot();
    game.resign(loser);
    _say('${_name(loser)} resigned');
    _positionChanged();
  }

  void _afterMove() {
    _positionChanged();
    if (game.bothPassed) {
      startScoring();
    } else if (isVsBot && game.toMove != humanColour) {
      _botMove();
    }
  }

  Future<void> _botMove() async {
    if (botThinking) return;
    final token = ++_botToken;
    botThinking = true;
    notifyListeners();
    final gen = _generation;
    try {
      final engine = await _engine();
      final m = await engine.genMove(game, level);
      if (gen != _generation || token != _botToken) return;
      if (_shouldResign(m.analysis)) {
        botThinking = false;
        game.resign(game.toMove);
        _say('${level.label} resigns - you win!');
        _positionChanged();
        return;
      }
      botThinking = false;
      game.play(m.point);
      if (m.isPass) _say('${level.label} passes');
      _positionChanged();
      if (game.bothPassed) startScoring();
    } catch (e) {
      if (gen == _generation && token == _botToken) _say('Engine error: $e');
    } finally {
      if (token == _botToken && botThinking) {
        botThinking = false;
        notifyListeners();
      }
    }
  }

  bool _shouldResign(PositionAnalysis? a) {
    if (a == null) return false;
    final bot = game.toMove;
    final wr = bot == Stone.black ? a.winrate : 1 - a.winrate;
    final lead = bot == Stone.black ? a.scoreLead : -a.scoreLead;
    final threshold = switch (game.size) { 9 => 15.0, 13 => 25.0, _ => 35.0 };
    if (game.moveNumber > game.size * game.size ~/ 4 &&
        wr < 0.02 &&
        lead < -threshold) {
      _botLosingStreak++;
    } else {
      _botLosingStreak = 0;
    }
    return _botLosingStreak >= 3;
  }

  void _cancelBot() {
    _botToken++;
    if (botThinking) {
      engines.cancel();
      botThinking = false;
    }
  }

  void botPlayNow() {
    if (botWaiting) _botMove();
  }

  // -------------------------------------------------------------------------
  // Take-back, navigation and switching sides

  /// Takes back the last move (vs the bot: back to your previous turn).
  void undo() {
    _cancelBot();
    scoring = null;
    if (!game.canUndo) return;
    game.undo(1);
    if (isVsBot) {
      while (game.toMove != humanColour && game.canUndo) {
        game.undo(1);
      }
    }
    _positionChanged();
  }

  void redo() {
    if (!game.canRedo) return;
    _cancelBot();
    scoring = null;
    game.redo(1);
    _positionChanged();
  }

  /// Jumps to any move of the game (moves after it can be redone, or are
  /// discarded as soon as a different move is played).
  void goTo(int moveNumber) {
    _cancelBot();
    scoring = null;
    game.goTo(moveNumber.clamp(0, game.lineLength));
    _positionChanged();
  }

  void switchSides() {
    if (!isVsBot) return;
    humanColour = humanColour.opponent;
    _say('You now play ${_name(humanColour)}');
    notifyListeners();
    if (!game.isOver && !isScoring && game.toMove != humanColour) _botMove();
  }

  // -------------------------------------------------------------------------
  // Analysis tools

  Future<void> toggleHints() async {
    if (overlay == BoardOverlay.hints) {
      overlay = BoardOverlay.none;
      engines.cancel();
      notifyListeners();
      return;
    }
    overlay = BoardOverlay.hints;
    hints = null;
    busy = true;
    notifyListeners();
    final gen = _generation;
    try {
      final engine = await _engine();
      final a = await engine.analyze(game,
          ownership: false,
          onPartial: (p) {
            if (gen == _generation && overlay == BoardOverlay.hints) {
              hints = p;
              notifyListeners();
            }
          });
      if (gen == _generation && overlay == BoardOverlay.hints) hints = a;
    } catch (e) {
      if (gen == _generation) _say('Hint failed: $e');
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Number of the move to rate: your last move (vs bot) or the last move.
  int? get moveToRate {
    final moves = game.moves;
    for (var i = moves.length - 1; i >= 0; i--) {
      if (!isVsBot || moves[i].color == humanColour) return i + 1;
    }
    return null;
  }

  Future<void> rateLastMove() async {
    final n = moveToRate;
    if (n == null) {
      _say('No move to rate yet');
      return;
    }
    busy = true;
    overlay = BoardOverlay.rating;
    rating = null;
    notifyListeners();
    final gen = _generation;
    try {
      final engine = await _engine();
      final r = await engine.rateMove(game, n);
      if (gen == _generation) rating = r;
    } catch (e) {
      if (gen == _generation) {
        overlay = BoardOverlay.none;
        _say('Rating failed: $e');
      }
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> toggleEstimate() async {
    if (overlay == BoardOverlay.estimate) {
      overlay = BoardOverlay.none;
      notifyListeners();
      return;
    }
    overlay = BoardOverlay.estimate;
    busy = true;
    notifyListeners();
    final gen = _generation;
    try {
      final engine = await _engine();
      final a = await engine.analyze(game,
          maxVisits: engine.config.estimateVisits, ownership: true);
      if (gen == _generation) estimate = a;
    } catch (e) {
      if (gen == _generation) {
        overlay = BoardOverlay.none;
        _say('Estimate failed: $e');
      }
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void closeOverlay() {
    overlay = BoardOverlay.none;
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Counting

  Future<void> startScoring() async {
    _cancelBot();
    overlay = BoardOverlay.none;
    busy = true;
    // Provisional count without engine help so the UI can show something.
    scoring = ScoringState(
        null,
        const {},
        Scorer.scoreGame(game, deadStones: Scorer.guessDeadStones(
            game.board, null, rules: game.rules)),
        const []);
    notifyListeners();
    final gen = _generation;
    try {
      final engine = await _engine();
      final visits = engine.config.estimateVisits * 2;
      final a = await engine.analyze(game, maxVisits: visits, ownership: true);
      // Is the game really over? Compare the best move with passing.
      final passed = game.copy()
        ..clearResult()
        ..pass();
      final ap = await engine.analyze(passed, maxVisits: visits, ownership: false);
      if (gen != _generation || scoring == null) return;
      final mover = a.toMove;
      final passScore = mover == Stone.black ? ap.scoreLead : -ap.scoreLead;
      final best = a.best;
      final gaps = <Point>[
        for (final m in a.moves.take(6))
          if (m.point != null &&
              best != null &&
              m.visits >= best.visits * 0.05 &&
              m.scoreFor(mover) - passScore > 0.75)
            m.point!
      ].take(3).toList();
      final dead = Scorer.guessDeadStones(game.board, a.ownership, rules: game.rules);
      scoring = _score(a, dead, gaps);
    } catch (e) {
      if (gen == _generation) _say('Counting without engine help: $e');
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  ScoringState _score(PositionAnalysis? a, Set<Point> dead, List<Point> engineGaps) =>
      ScoringState(
          a,
          dead,
          Scorer.scoreGame(game, deadStones: dead, ownership: a?.ownership),
          engineGaps);

  void toggleDead(Point p) {
    final s = scoring;
    if (s == null || s.accepted || game.board[p] == null) return;
    scoring = _score(s.analysis, Scorer.toggleDead(game.board, s.dead, p), s.engineGaps);
    notifyListeners();
  }

  void acceptScore() {
    final s = scoring;
    if (s == null) return;
    game.setResult(s.result.toResult());
    scoring = ScoringState(s.analysis, s.dead, s.result, s.engineGaps, accepted: true);
    _say('Result: ${_resultText(game.result!)}');
    notifyListeners();
  }

  /// Leaves counting and continues playing (undoing the final passes).
  void resumePlay() {
    scoring = null;
    game.clearResult();
    while (game.canUndo && (game.lastMove?.isPass ?? false)) {
      game.undo(1);
    }
    _positionChanged();
    startIfBotToMove();
  }

  String resultText() => game.result == null ? '' : _resultText(game.result!);

  static String _resultText(GameResult r) {
    if (r.winner == null) return 'Draw (jigo)';
    final who = _name(r.winner!);
    return switch (r.reason) {
      ResultReason.resignation => '$who wins by resignation',
      ResultReason.score => '$who wins by ${_fmt(r.margin ?? 0)} points',
      _ => '$who wins',
    };
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  static String _name(Stone s) => s == Stone.black ? 'Black' : 'White';

  @override
  void dispose() {
    _cancelBot();
    _messages.close();
    super.dispose();
  }
}
