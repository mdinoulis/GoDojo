import 'package:flutter_test/flutter_test.dart';
import 'package:go_core/go_core.dart';
import 'package:godojo/engine_service.dart';
import 'package:godojo/game_controller.dart';
import 'package:godojo/settings.dart';
import 'package:katago_engine/katago_engine.dart';

void main() {
  test('score estimate uses the same marks as counting', () {
    final c = GameController(
      engines: EngineService(),
      settings: () => const AppSettings(),
      setup: const GameSetup(size: 9),
      mode: GameMode.otb,
      humanColour: Stone.black,
      level: BotLevel.byId('10k'),
    );
    // Black stone at C3, a lone White stone at C7 inside Black's area.
    c.tap(const Point(2, 2));
    c.tap(const Point(2, 6));
    expect(c.estimateStatus, isNull, reason: 'no estimate yet');

    // Black owns the left of the board (incl. the White stone), White the
    // right; the middle column is undecided.
    c.estimate = PositionAnalysis(
      toMove: Stone.black,
      visits: 100,
      winrate: 0.7,
      scoreLead: 5,
      moves: const [],
      ownership: [
        for (var y = 0; y < 9; y++)
          for (var x = 0; x < 9; x++) x < 4 ? 0.9 : (x == 4 ? 0.2 : -0.8)
      ],
    );
    final st = c.estimateStatus!;
    PointStatus at(int x, int y) => st[y * 9 + x];
    expect(at(2, 2), PointStatus.blackStone);
    expect(at(2, 6), PointStatus.deadWhite, reason: 'White stone in Black area is dead');
    expect(at(0, 0), PointStatus.blackTerritory);
    expect(at(4, 4), PointStatus.dame, reason: 'under 50% sure: not marked');
    expect(at(8, 8), PointStatus.whiteTerritory);
    c.dispose();
  });
}
