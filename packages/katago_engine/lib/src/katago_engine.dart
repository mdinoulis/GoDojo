import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:go_core/go_core.dart';

import 'config.dart';
import 'engine.dart';
import 'transport.dart';

typedef TransportFactory = Future<EngineTransport> Function(EngineConfig config);

class EngineException implements Exception {
  final String message;
  EngineException(this.message);
  @override
  String toString() => 'EngineException: $message';
}

class _Pending {
  final int size;
  final Set<int> remaining;
  final Map<int, PositionAnalysis?> results = {};
  final Completer<Map<int, PositionAnalysis?>> completer = Completer();
  final AnalysisCallback? onPartial;
  final void Function(int done, int total)? onProgress;
  final int total;
  _Pending(this.size, Iterable<int> turns, {this.onPartial, this.onProgress})
      : remaining = turns.toSet(),
        total = turns.length;
}

/// [GoEngine] backed by KataGo's JSON analysis engine.
class KataGoEngine implements GoEngine {
  EngineConfig config;
  final TransportFactory _transportFactory;
  final MoveClassifier classifier;
  final Random _random;

  EngineTransport? _transport;
  StreamSubscription<String>? _sub;
  final Map<String, _Pending> _pending = {};
  int _nextId = 0;

  KataGoEngine(
    this.config, {
    TransportFactory? transportFactory,
    this.classifier = const MoveClassifier(),
    Random? random,
  })  : _transportFactory = transportFactory ?? _processFactory,
        _random = random ?? Random();

  static Future<EngineTransport> _processFactory(EngineConfig c) =>
      ProcessTransport.start(
        c.executable,
        [
          ...c.arguments,
          // The app always works with values from Black's point of view.
          '-override-config', 'reportAnalysisWinratesAs=BLACK',
        ],
        workingDirectory: c.workingDirectory,
      );

  @override
  bool get isRunning => _transport != null;

  @override
  Future<void> start() async {
    if (_transport != null) return;
    final t = await _transportFactory(config);
    _transport = t;
    _sub = t.lines.listen(_onLine);
    t.done.then((code) {
      if (identical(_transport, t)) {
        _transport = null;
        _failAll(EngineException('Engine exited (code $code)'));
      }
    });
    try {
      await t.ready;
    } catch (e) {
      _transport = null;
      await _sub?.cancel();
      rethrow;
    }
  }

  @override
  Future<void> stop() async {
    final t = _transport;
    _transport = null;
    _failAll(EngineException('Engine stopped'));
    await _sub?.cancel();
    await t?.close();
  }

  /// Restarts the engine with a new configuration.
  Future<void> reconfigure(EngineConfig newConfig) async {
    await stop();
    config = newConfig;
    await start();
  }

  @override
  Future<void> cancelAll() async {
    _send({'id': 'cancel${_nextId++}', 'action': 'terminate_all'});
  }

  // ---------------------------------------------------------------------
  // Queries

  Map<String, dynamic> _position(Game g, int moveCount) => {
        'rules': g.rules.katagoName,
        'komi': g.setup.komi,
        'boardXSize': g.size,
        'boardYSize': g.size,
        'initialStones': g.initialStonesForEngine(),
        'initialPlayer': g.firstPlayer.letter,
        'moves': g.movesForEngine(moveCount),
      };

  Future<Map<int, PositionAnalysis?>> _query(
    Map<String, dynamic> query,
    int size,
    List<int> turns, {
    AnalysisCallback? onPartial,
    void Function(int, int)? onProgress,
  }) {
    if (_transport == null) {
      return Future.error(EngineException('Engine is not running'));
    }
    final id = 'q${_nextId++}';
    final p = _Pending(size, turns, onPartial: onPartial, onProgress: onProgress);
    _pending[id] = p;
    _send({...query, 'id': id, 'analyzeTurns': turns});
    return p.completer.future;
  }

  Future<PositionAnalysis> _single(Map<String, dynamic> query, Game g,
      int moveCount, {AnalysisCallback? onPartial}) async {
    final r = await _query(query, g.size, [moveCount], onPartial: onPartial);
    final a = r[moveCount];
    if (a == null) throw EngineException('Search was cancelled');
    return a;
  }

  @override
  Future<PositionAnalysis> analyze(
    Game game, {
    int? moveCount,
    int? maxVisits,
    bool ownership = true,
    AnalysisCallback? onPartial,
  }) {
    final n = moveCount ?? game.moveNumber;
    return _single({
      ..._position(game, n),
      'maxVisits': maxVisits ?? config.hintVisits,
      'includeOwnership': ownership,
      'includePolicy': false,
      if (onPartial != null) 'reportDuringSearchEvery': 0.3,
    }, game, n, onPartial: onPartial);
  }

  @override
  Future<BotMove> genMove(Game game, BotLevel level) async {
    final n = game.moveNumber;
    if (level.isFullStrength) {
      final a = await _single({
        ..._position(game, n),
        'maxVisits': config.fullStrengthVisits,
      }, game, n);
      return BotMove(a.best?.point, a);
    }

    final a = await _single({
      ..._position(game, n),
      'maxVisits': config.botSearchVisits,
      'includePolicy': true,
      'overrideSettings': {
        'humanSLProfile': level.humanProfile,
        'ignorePreRootHistory': false,
        'rootNumSymmetriesToSample': 2,
      },
    }, game, n);

    // KataGo's own search decides when the game is over; otherwise imitate
    // a human of this rank by sampling the human policy (never passing).
    if (a.best == null || a.best!.isPass) return BotMove(null, a);
    final hp = a.humanPolicy;
    if (hp == null) {
      throw EngineException('No human policy - is the human SL model loaded?');
    }
    final point = sampleHumanPolicy(hp, game, level.temperature, _random);
    return BotMove(point ?? a.best!.point, a);
  }

  /// Samples a legal non-pass move from [policy] (row-major + pass), with
  /// probabilities raised to 1/[temperature].
  static Point? sampleHumanPolicy(
      List<double> policy, Game game, double temperature, Random random) {
    final size = game.size;
    final pts = <Point>[];
    final weights = <double>[];
    var total = 0.0;
    for (var i = 0; i < size * size; i++) {
      final v = policy[i];
      if (v <= 0) continue;
      final pt = Point(i % size, i ~/ size);
      if (!game.isLegal(pt)) continue;
      final w = temperature <= 0 ? v : pow(v, 1 / temperature).toDouble();
      pts.add(pt);
      weights.add(w);
      total += w;
    }
    if (pts.isEmpty) return null;
    if (temperature <= 0) {
      var bi = 0;
      for (var i = 1; i < weights.length; i++) {
        if (weights[i] > weights[bi]) bi = i;
      }
      return pts[bi];
    }
    var r = random.nextDouble() * total;
    for (var i = 0; i < pts.length; i++) {
      r -= weights[i];
      if (r <= 0) return pts[i];
    }
    return pts.last;
  }

  @override
  Future<MoveReview> rateMove(Game game, int moveNumber, {int? maxVisits}) async {
    if (moveNumber < 1 || moveNumber > game.moveNumber) {
      throw RangeError.range(moveNumber, 1, game.moveNumber, 'moveNumber');
    }
    final move = game.moves[moveNumber - 1];
    final r = await _query({
      ..._position(game, moveNumber),
      'maxVisits': maxVisits ?? config.rateVisits,
      if (!move.isPass) 'focusMoves': [move.toGtp(game.size)],
    }, game.size, [moveNumber - 1, moveNumber]);
    final before = r[moveNumber - 1];
    if (before == null) throw EngineException('Search was cancelled');
    final after = r[moveNumber];
    final rating = classifier.classify(
        before: before, played: move.point, player: move.color, after: after);
    return MoveReview(moveNumber, move, rating, before, after);
  }

  @override
  Future<List<PositionAnalysis>> analyzeGame(
    Game game, {
    int? maxVisits,
    void Function(int done, int total)? onProgress,
  }) async {
    final n = game.moveNumber;
    final turns = [for (var i = 0; i <= n; i++) i];
    final r = await _query({
      ..._position(game, n),
      'maxVisits': maxVisits ?? config.reviewVisits,
      'includeOwnership': false,
    }, game.size, turns, onProgress: onProgress);
    return [
      for (final t in turns)
        r[t] ??
            (throw EngineException('Analysis of move $t was cancelled')),
    ];
  }

  /// Rates every move of a game from a full-game analysis.
  List<MoveReview> reviewGame(Game game, List<PositionAnalysis> analyses) {
    final moves = game.moves;
    return [
      for (var i = 1; i < analyses.length && i <= moves.length; i++)
        MoveReview(
          i,
          moves[i - 1],
          classifier.classify(
            before: analyses[i - 1],
            played: moves[i - 1].point,
            player: moves[i - 1].color,
            after: analyses[i],
          ),
          analyses[i - 1],
          analyses[i],
        ),
    ];
  }

  // ---------------------------------------------------------------------
  // Wire protocol

  void _send(Map<String, dynamic> msg) {
    final t = _transport;
    if (t == null) throw EngineException('Engine is not running');
    t.send(jsonEncode(msg));
  }

  void _onLine(String line) {
    if (!line.startsWith('{')) return;
    final Map<String, dynamic> j;
    try {
      j = jsonDecode(line) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final id = j['id'] as String?;
    final p = id == null ? null : _pending[id];
    if (j.containsKey('error')) {
      final err = EngineException('${j['error']} (field: ${j['field']})');
      if (p != null) {
        _pending.remove(id);
        p.completer.completeError(err);
      }
      return;
    }
    if (j.containsKey('warning') || j.containsKey('action') || p == null) return;

    final turn = j['turnNumber'] as int;
    if (j['isDuringSearch'] == true) {
      final a = parseAnalysis(j, p.size, partial: true);
      if (a != null) p.onPartial?.call(a);
      return;
    }
    p.results[turn] = parseAnalysis(j, p.size);
    p.remaining.remove(turn);
    p.onProgress?.call(p.total - p.remaining.length, p.total);
    if (p.remaining.isEmpty) {
      _pending.remove(id);
      p.completer.complete(p.results);
    }
  }

  void _failAll(Object error) {
    final all = _pending.values.toList();
    _pending.clear();
    for (final p in all) {
      if (!p.completer.isCompleted) p.completer.completeError(error);
    }
  }

  /// Converts a KataGo analysis response into a [PositionAnalysis].
  /// Returns null for terminated queries without results.
  static PositionAnalysis? parseAnalysis(Map<String, dynamic> j, int size,
      {bool partial = false}) {
    if (j['noResults'] == true || j['rootInfo'] == null) return null;
    final root = j['rootInfo'] as Map<String, dynamic>;
    List<double>? dl(Object? v) =>
        (v as List?)?.map((e) => (e as num).toDouble()).toList();
    Point? pt(String s) => Point.fromGtp(s, size);

    final moves = [
      for (final m in (j['moveInfos'] as List? ?? const []))
        if (m is Map<String, dynamic>)
          MoveCandidate(
            point: pt(m['move'] as String),
            order: m['order'] as int,
            visits: m['visits'] as int,
            winrate: (m['winrate'] as num).toDouble(),
            scoreLead: (m['scoreLead'] as num).toDouble(),
            prior: (m['prior'] as num?)?.toDouble() ?? 0,
            humanPrior: (m['humanPrior'] as num?)?.toDouble(),
            pv: [for (final s in (m['pv'] as List? ?? const [])) pt(s as String)],
          )
    ]..sort((a, b) => a.order.compareTo(b.order));

    return PositionAnalysis(
      toMove: Stone.fromLetter(root['currentPlayer'] as String),
      visits: root['visits'] as int,
      winrate: (root['winrate'] as num).toDouble(),
      scoreLead: (root['scoreLead'] as num).toDouble(),
      scoreStdev: (root['scoreStdev'] as num?)?.toDouble(),
      moves: moves,
      ownership: dl(j['ownership']),
      policy: dl(j['policy']),
      humanPolicy: dl(j['humanPolicy']),
      isPartial: partial,
    );
  }
}
