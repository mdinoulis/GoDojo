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

Future<void> _open(WidgetTester t, Game game, {EngineService? engine}) async {
  t.view.physicalSize = const Size(992, 1323); // Boox Note Air, portrait
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  SharedPreferences.setMockInitialValues({'settings.v1': '{"soundEnabled":false}'});
  final prefs = await SharedPreferences.getInstance();
  await t.pumpWidget(ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      if (engine != null) engineServiceProvider.overrideWithValue(engine),
    ],
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
}

Future<void> _press(WidgetTester t, String label) async {
  await t.tap(find
      .ancestor(of: find.text(label), matching: find.bySubtype<ButtonStyleButton>())
      .last);
  await t.pump();
  await t.pump(const Duration(seconds: 1));
}

/// Buttons and slider are on screen and usable (not hidden behind results).
bool _controlsShown(WidgetTester t) =>
    find.text('Undo').hitTestable().evaluate().isNotEmpty &&
    find.byType(Slider).hitTestable().evaluate().isNotEmpty;

void main() {
  testWidgets('portrait counting replaces the buttons; board keeps its size',
      (t) async {
    // A small finished-looking 9x9 game: Black left, White right.
    final game = Game(const GameSetup(size: 9, komi: 6.5));
    for (var y = 0; y < 9; y++) {
      game.play(Point(3, y));
      game.play(Point(5, y));
    }
    await _open(t, game);
    final board = t.getRect(find.byType(BoardView));
    expect(_controlsShown(t), isTrue);

    // Both pass: counting results take the place of buttons and slider.
    await _press(t, 'Pass');
    await _press(t, 'Pass');
    expect(find.byType(AlertDialog), findsNothing, reason: 'no pop-up');
    expect(_controlsShown(t), isFalse);
    expect(find.textContaining('wins by'), findsWidgets);
    expect(find.textContaining('Black: territory'), findsOneWidget);
    expect(find.textContaining('komi 6.5'), findsOneWidget);
    expect(find.text('Accept result'), findsOneWidget);
    expect(t.getRect(find.byType(BoardView)), board, reason: 'board not resized');

    // Accept: result with Review / Back to menu / Close.
    await _press(t, 'Accept result');
    expect(find.text('Review game'), findsOneWidget);
    expect(find.text('Back to menu'), findsOneWidget);
    expect(t.getRect(find.byType(BoardView)), board);

    // Close brings the buttons and slider back.
    await _press(t, 'Close');
    expect(_controlsShown(t), isTrue);
    expect(t.getRect(find.byType(BoardView)), board);
    expect(t.takeException(), isNull);
  });

  testWidgets('"Resume play" brings the buttons and slider back', (t) async {
    await _open(t, Game(const GameSetup(size: 9))..play(const Point(4, 4)));
    final board = t.getRect(find.byType(BoardView));
    await _press(t, 'Count');
    expect(_controlsShown(t), isFalse);
    expect(find.text('Resume play'), findsOneWidget);
    await _press(t, 'Resume play');
    // Clear the "counting without engine" message (no engine in tests).
    t.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).removeCurrentSnackBar();
    await t.pump();
    expect(_controlsShown(t), isTrue);
    expect(find.text('Resume play'), findsNothing);
    expect(find.textContaining('to play'), findsOneWidget);
    expect(t.getRect(find.byType(BoardView)), board);
    expect(t.takeException(), isNull);
  });

  testWidgets('no score or winner is shown until counting has finished', (t) async {
    final game = Game(const GameSetup(size: 9));
    for (var y = 0; y < 9; y++) {
      game.play(Point(3, y));
      game.play(Point(5, y));
    }
    await _open(t, game, engine: _SlowEngineService());
    await _press(t, 'Count');
    expect(find.text('Counting…'), findsWidgets);
    expect(find.textContaining('wins by'), findsNothing);
    expect(find.textContaining('Black:'), findsNothing);
    expect(find.text('Accept result'), findsNothing);
    expect(find.text('Resume play'), findsOneWidget);
    await _press(t, 'Resume play');
    expect(find.text('Counting…'), findsNothing);
    expect(t.takeException(), isNull);
  });
}

/// The engine is "still working" for the whole test.
class _SlowEngineService extends EngineService {
  @override
  Future<KataGoEngine> engineFor(AppSettings settings) => Completer<KataGoEngine>().future;
}
