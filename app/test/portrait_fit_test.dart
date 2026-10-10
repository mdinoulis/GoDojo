import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_core/go_core.dart';
import 'package:godojo/board/board_view.dart';
import 'package:godojo/engine_service.dart';
import 'package:godojo/screens/game_screen.dart';
import 'package:godojo/settings.dart';
import 'package:katago_engine/katago_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // Logical portrait sizes: e-readers (Boox), phones and a tablet.
  const sizes = [
    Size(992, 1323), // Boox Note Air (1860x2480 @ 300 dpi)
    Size(620, 827),
    Size(702, 936),
    Size(632, 840),
    Size(412, 915),
    Size(800, 1280),
  ];

  for (final size in sizes) {
    testWidgets('portrait game screen fits ${size.width}x${size.height} exactly',
        (t) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      SharedPreferences.setMockInitialValues({'settings.v1': '{"soundEnabled":false}'});
      final prefs = await SharedPreferences.getInstance();
      final game = Game(const GameSetup(size: 19));
      for (final p in [const Point(3, 3), const Point(15, 15), const Point(15, 3)]) {
        game.play(p);
      }
      await t.pumpWidget(ProviderScope(
        overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          home: GameScreen(
            setup: game.setup,
            mode: GameMode.otb,
            humanColour: Stone.black,
            level: BotLevel.byId('10k'),
            resume: game,
          ),
        ),
      ));
      await t.pump(const Duration(seconds: 1));

      // (No engine in tests, so an error notice follows below the fitted
      // area; only the fixed controls must fit the screen.)
      final list = t.getRect(find.byType(ListView));
      final navigator =
          find.ancestor(of: find.byTooltip('Latest'), matching: find.byType(Card));
      double controlsBottom() => t.getRect(navigator).bottom;
      final board = t.getSize(find.byType(BoardView));

      // The move slider (last fixed control) ends on screen, and either the
      // board fills the width or it was shrunk so the controls end exactly
      // at the bottom - nothing to slide.
      expect(controlsBottom(), lessThanOrEqualTo(list.bottom - 8 + 0.5));
      if (board.width < size.width - 16 - 0.5) {
        expect(controlsBottom(), greaterThan(list.bottom - 8 - 1.5));
      }
      expect(board.width, board.height);

      // Stepping back (redo available) must not change the layout.
      await t.tap(find.byTooltip('Back one move'));
      await t.pump();
      expect(t.getSize(find.byType(BoardView)), board);
      expect(controlsBottom(), lessThanOrEqualTo(list.bottom - 8 + 0.5));
      expect(t.takeException(), isNull);
    });
  }

  // An engine that never starts, so no "KataGo not found" notice is shown
  // below the controls (as on a device where the engine works).
  final idleEngine = _IdleEngineService();

  testWidgets('dragging the portrait game screen does not move it', (t) async {
    t.view.physicalSize = const Size(992, 1323);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    SharedPreferences.setMockInitialValues({'settings.v1': '{"soundEnabled":false}'});
    final prefs = await SharedPreferences.getInstance();
    await t.pumpWidget(ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        engineServiceProvider.overrideWithValue(idleEngine),
      ],
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: GameScreen(
          setup: const GameSetup(size: 19),
          mode: GameMode.otb,
          humanColour: Stone.black,
          level: BotLevel.byId('10k'),
        ),
      ),
    ));
    await t.pump(const Duration(seconds: 1));
    final before = t.getRect(find.byType(BoardView));
    for (final dy in [-60.0, 60.0]) {
      final g = await t.startGesture(t.getCenter(find.text('Black')));
      for (var i = 0; i < 6; i++) {
        await g.moveBy(Offset(0, dy / 6));
        await t.pump(const Duration(milliseconds: 16));
        expect(t.getRect(find.byType(BoardView)), before, reason: 'moved while dragging');
      }
      await g.up();
      await t.pump(const Duration(seconds: 1));
    }
  });
}

class _IdleEngineService extends EngineService {
  @override
  Future<KataGoEngine> engineFor(AppSettings settings) => Completer<KataGoEngine>().future;
}
