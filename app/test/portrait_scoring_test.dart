import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_core/go_core.dart';
import 'package:godojo/board/board_view.dart';
import 'package:godojo/screens/game_screen.dart';
import 'package:godojo/settings.dart';
import 'package:katago_engine/katago_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('portrait counting shows the score in a dialog; board keeps its size',
      (t) async {
    t.view.physicalSize = const Size(992, 1323); // Boox Note Air, portrait
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    SharedPreferences.setMockInitialValues({'settings.v1': '{"soundEnabled":false}'});
    final prefs = await SharedPreferences.getInstance();
    // A small finished-looking 9x9 game: Black left, White right.
    final game = Game(const GameSetup(size: 9, komi: 6.5));
    for (var y = 0; y < 9; y++) {
      game.play(Point(3, y));
      game.play(Point(5, y));
    }
    await t.pumpWidget(ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      child: MaterialApp(
        home: Navigator(
          onGenerateRoute: (_) => MaterialPageRoute(
            builder: (_) => GameScreen(
              setup: game.setup,
              mode: GameMode.otb,
              humanColour: Stone.black,
              level: BotLevel.byId('10k'),
              resume: game,
            ),
          ),
        ),
      ),
    ));
    await t.pump(const Duration(seconds: 1));
    final board = t.getRect(find.byType(BoardView));

    Future<void> press(String label) async {
      await t.tap(find.ancestor(of: find.text(label), matching: find.bySubtype<ButtonStyleButton>()).last);
      await t.pump();
      await t.pump(const Duration(seconds: 1));
    }

    // Both pass: counting starts and the score pops up by itself.
    await press('Pass');
    await press('Pass');
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('Counting ('), findsOneWidget);
    expect(find.text('Total'), findsOneWidget);
    expect(find.textContaining('wins by'), findsWidgets);
    expect(t.getRect(find.byType(BoardView)), board, reason: 'board not resized');

    // "Mark stones" closes it; "Count" brings it back.
    await press('Mark stones');
    expect(find.byType(AlertDialog), findsNothing);
    await press('Count');
    expect(find.byType(AlertDialog), findsOneWidget);

    // Accepting shows the result with Review / Back to menu.
    await press('Accept');
    expect(find.text('Result'), findsOneWidget);
    expect(find.text('Review game'), findsOneWidget);
    expect(find.text('Back to menu'), findsOneWidget);
    await press('Close');
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.textContaining('wins by'), findsWidgets, reason: 'status line shows result');
    expect(t.getRect(find.byType(BoardView)), board);
    expect(t.takeException(), isNull);
  });

  testWidgets('"Resume play" from the dialog leaves counting', (t) async {
    t.view.physicalSize = const Size(992, 1323);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    SharedPreferences.setMockInitialValues({'settings.v1': '{"soundEnabled":false}'});
    final prefs = await SharedPreferences.getInstance();
    final game = Game(const GameSetup(size: 9))..play(const Point(4, 4));
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
    await t.tap(find.ancestor(of: find.text('Count'), matching: find.bySubtype<ButtonStyleButton>()));
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    expect(find.byType(AlertDialog), findsOneWidget);
    await t.tap(find.text('Resume play'));
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.textContaining('to play'), findsOneWidget);
  });
}
