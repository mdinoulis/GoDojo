import 'package:flutter_test/flutter_test.dart';
import 'package:go_core/go_core.dart';
import 'package:go_study/engine_service.dart';
import 'package:go_study/game_controller.dart';
import 'package:go_study/settings.dart';
import 'package:katago_engine/katago_engine.dart';

void main() {
  test('sound setting defaults on and survives save/load', () {
    expect(const AppSettings().soundEnabled, isTrue);
    final off = const AppSettings().copyWith(soundEnabled: false);
    expect(AppSettings.fromJson(off.toJson()).soundEnabled, isFalse);
    expect(AppSettings.fromJson({}).soundEnabled, isTrue);
  });

  test('controller reports placed stones and captures, not passes or undo', () {
    final c = GameController(
      engines: EngineService(),
      settings: () => const AppSettings(),
      setup: const GameSetup(size: 9),
      mode: GameMode.otb,
      humanColour: Stone.black,
      level: BotLevel.byId('10k'),
    );
    final events = <(Move, int)>[];
    c.onStonePlayed = (m, n) => events.add((m, n));

    // White E5 is surrounded and captured by Black's 4th stone.
    for (final (x, y) in [(3, 4), (4, 4), (5, 4), (0, 0), (4, 3), (0, 8), (4, 5)]) {
      c.tap(Point(x, y));
    }
    expect(events.length, 7);
    expect(events.last.$2, 1, reason: 'last move captured one stone');
    expect(events.take(6).every((e) => e.$2 == 0), isTrue);

    c.pass(); // no sound for a pass
    expect(events.length, 7);
    c.undo(); // no sound for undo; White to play again
    expect(events.length, 7);
    c.tap(const Point(4, 4)); // suicide for White -> illegal, no sound
    expect(events.length, 7);
    c.tap(const Point(8, 8));
    expect(events.length, 8);
    c.tap(const Point(8, 8)); // occupied -> no sound
    expect(events.length, 8);
    c.dispose();
  });
}
