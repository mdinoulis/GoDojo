// Drive the engine from a terminal on the PC:
//   dart run bin/cli.dart [engineDir] [size] [level]
// Then type moves (e.g. D4), "pass", "hint", "rate", "score", "undo", "quit".
import 'dart:io';

import 'package:go_core/go_core.dart';
import 'package:katago_engine/katago_engine.dart';

Future<void> main(List<String> args) async {
  final engineDir = args.isNotEmpty ? args[0] : '../../engine';
  final size = args.length > 1 ? int.parse(args[1]) : 9;
  final level = BotLevel.byId(args.length > 2 ? args[2] : '10k');
  final engine = KataGoEngine(EngineConfig.desktop(engineDir));
  stdout.writeln('Starting KataGo...');
  await engine.start();
  final game = Game(GameSetup(size: size, komi: 6.5));
  stdout.writeln('You are Black vs ${level.label}.');
  while (!game.isOver) {
    stdout.writeln('\n${game.board.toAscii()}');
    stdout.write('${game.toMove.letter}> ');
    final line = stdin.readLineSync()?.trim().toLowerCase();
    if (line == null || line == 'quit') break;
    try {
      switch (line) {
        case 'hint':
          final a = await engine.analyze(game, ownership: false);
          for (final m in a.moves.take(5)) {
            stdout.writeln('  ${m.point?.toGtp(size) ?? 'pass'}  '
                'lead ${m.scoreFor(game.toMove).toStringAsFixed(1)}  '
                'win ${(m.winrateFor(game.toMove) * 100).toStringAsFixed(1)}%  '
                'visits ${m.visits}');
          }
          continue;
        case 'rate':
          final r = await engine.rateMove(game, game.moveNumber - 1);
          stdout.writeln('  ${r.rating.quality.label}, '
              'loss ${r.rating.pointLoss.toStringAsFixed(1)} pts; '
              'better: ${r.rating.betterMoves.take(3).map((m) => m.point?.toGtp(size)).join(', ')}');
          continue;
        case 'score':
          final a = await engine.analyze(game);
          stdout.writeln('  Black leads by ${a.scoreLead.toStringAsFixed(1)}');
          continue;
        case 'undo':
          game.undo(2);
          continue;
        case 'pass':
          game.pass();
        default:
          game.play(Point.fromGtp(line, size));
      }
    } catch (e) {
      stdout.writeln('  $e');
      continue;
    }
    if (game.isOver) break;
    final bm = await engine.genMove(game, level);
    game.play(bm.point);
    stdout.writeln('Bot: ${bm.point?.toGtp(size) ?? 'pass'}');
  }
  final a = await engine.analyze(game, maxVisits: 400);
  final dead = Scorer.guessDeadStones(game.board, a.ownership, rules: game.rules);
  final s = Scorer.scoreGame(game, deadStones: dead, ownership: a.ownership);
  stdout.writeln('Result: ${s.toResult()}  (finished: ${s.isFinished})');
  await engine.stop();
}
