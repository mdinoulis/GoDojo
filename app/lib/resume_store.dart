import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_core/go_core.dart';
import 'package:katago_engine/katago_engine.dart';

import 'settings.dart';

/// An unfinished game, saved after every change so it can be continued
/// after the app is closed (or the device loses power).
class ResumableGame {
  final GameMode mode;
  final Stone humanColour;
  final String levelId;
  final GameSetup setup;
  final List<Point> handicapStones;

  /// The whole line, including moves that were taken back but can be redone.
  final List<Move> line;

  /// How many moves of [line] are on the board.
  final int moveNumber;
  final DateTime savedAt;

  const ResumableGame({
    required this.mode,
    required this.humanColour,
    required this.levelId,
    required this.setup,
    required this.handicapStones,
    required this.line,
    required this.moveNumber,
    required this.savedAt,
  });

  /// Snapshot of [game], or null if there is nothing worth continuing
  /// (no moves yet, or the game has a result).
  static ResumableGame? of(Game game,
      {required GameMode mode,
      required Stone humanColour,
      required BotLevel level}) {
    if (game.result != null || game.lineLength == 0) return null;
    final shown = game.moveNumber;
    final copy = game.copy()..goTo(game.lineLength);
    return ResumableGame(
      mode: mode,
      humanColour: humanColour,
      levelId: level.id,
      setup: game.setup,
      handicapStones: game.handicapStones,
      line: copy.moves,
      moveNumber: shown,
      savedAt: DateTime.now(),
    );
  }

  BotLevel get level => BotLevel.byId(levelId);

  /// Rebuilds the game at the saved position (later moves can be redone).
  Game toGame() {
    final g = Game(setup, handicapStones: handicapStones);
    for (final m in line) {
      g.playMove(m);
    }
    g.goTo(moveNumber);
    return g;
  }

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'humanColour': humanColour.name,
        'levelId': levelId,
        'size': setup.size,
        'rules': setup.rules.name,
        'komi': setup.komi,
        'handicap': setup.handicap,
        'handicapStones': [for (final p in handicapStones) p.toSgf()],
        'line': [for (final m in line) '${m.color.letter}${m.point?.toSgf() ?? ''}'],
        'moveNumber': moveNumber,
        'savedAt': savedAt.toIso8601String(),
      };

  factory ResumableGame.fromJson(Map<String, dynamic> j) {
    final size = j['size'] as int;
    return ResumableGame(
      mode: GameMode.values.byName(j['mode'] as String),
      humanColour: Stone.values.byName(j['humanColour'] as String),
      levelId: j['levelId'] as String,
      setup: GameSetup(
        size: size,
        rules: Ruleset.values.byName(j['rules'] as String),
        komi: (j['komi'] as num).toDouble(),
        handicap: j['handicap'] as int,
      ),
      handicapStones: [
        for (final s in j['handicapStones'] as List) Point.fromSgf(s as String, size)!
      ],
      line: [
        for (final s in (j['line'] as List).cast<String>())
          Move(Stone.fromLetter(s[0]), Point.fromSgf(s.substring(1), size))
      ],
      moveNumber: j['moveNumber'] as int,
      savedAt: DateTime.parse(j['savedAt'] as String),
    );
  }
}

/// One saved unfinished game per mode (vs the bot, over the board).
class ResumeStore extends Notifier<Map<GameMode, ResumableGame>> {
  static String _key(GameMode m) => 'unfinished.${m.name}.v1';

  @override
  Map<GameMode, ResumableGame> build() {
    final prefs = ref.read(sharedPrefsProvider);
    final games = <GameMode, ResumableGame>{};
    for (final m in GameMode.values) {
      final raw = prefs.getString(_key(m));
      if (raw == null) continue;
      try {
        final g = ResumableGame.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        g.toGame(); // make sure it replays
        games[m] = g;
      } catch (_) {
        prefs.remove(_key(m));
      }
    }
    return games;
  }

  void save(ResumableGame g) {
    state = {...state, g.mode: g};
    ref.read(sharedPrefsProvider).setString(_key(g.mode), jsonEncode(g.toJson()));
  }

  void clear(GameMode mode) {
    if (!state.containsKey(mode)) return;
    state = {...state}..remove(mode);
    ref.read(sharedPrefsProvider).remove(_key(mode));
  }
}

final resumeStoreProvider =
    NotifierProvider<ResumeStore, Map<GameMode, ResumableGame>>(ResumeStore.new);
