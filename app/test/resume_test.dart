import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_core/go_core.dart';
import 'package:godojo/main.dart';
import 'package:godojo/resume_store.dart';
import 'package:godojo/settings.dart';
import 'package:katago_engine/katago_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

Game _sample() {
  final g = Game(const GameSetup(size: 9, handicap: 2));
  for (final p in [const Point(2, 2), const Point(3, 3), const Point(4, 4)]) {
    g.play(p);
  }
  g.pass();
  g.play(const Point(5, 5));
  g.undo(2); // two moves can be redone
  return g;
}

void main() {
  test('snapshot round-trips through JSON, keeping redo moves and position', () {
    final g = _sample();
    final snap = ResumableGame.of(g,
        mode: GameMode.vsBot, humanColour: Stone.white, level: BotLevel.byId('5k'))!;
    final back = ResumableGame.fromJson(snap.toJson());
    expect(back.mode, GameMode.vsBot);
    expect(back.humanColour, Stone.white);
    expect(back.levelId, '5k');
    final r = back.toGame();
    expect(r.size, 9);
    expect(r.handicapStones, g.handicapStones);
    expect(r.moves, g.moves);
    expect(r.moveNumber, 3);
    expect(r.lineLength, 5);
    expect(r.board, g.board);
    expect(r.toMove, g.toMove);
    r.redo(2);
    expect(r.lastMove, const Move(Stone.white, Point(5, 5)));
  });

  test('nothing to save for an empty or finished game', () {
    final level = BotLevel.byId('10k');
    expect(
        ResumableGame.of(Game(const GameSetup(size: 9)),
            mode: GameMode.otb, humanColour: Stone.black, level: level),
        isNull);
    final g = _sample()..resign(Stone.black);
    expect(ResumableGame.of(g, mode: GameMode.otb, humanColour: Stone.black, level: level),
        isNull);
  });

  test('store keeps one game per mode in shared preferences', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    ProviderContainer make() =>
        ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
    final level = BotLevel.byId('10k');
    final c1 = make();
    c1.read(resumeStoreProvider.notifier).save(ResumableGame.of(_sample(),
        mode: GameMode.otb, humanColour: Stone.black, level: level)!);
    c1.read(resumeStoreProvider.notifier).save(ResumableGame.of(_sample(),
        mode: GameMode.vsBot, humanColour: Stone.black, level: level)!);
    c1.dispose();

    final c2 = make(); // as after an app restart
    expect(c2.read(resumeStoreProvider).keys,
        unorderedEquals([GameMode.otb, GameMode.vsBot]));
    c2.read(resumeStoreProvider.notifier).clear(GameMode.otb);
    c2.dispose();

    final c3 = make();
    expect(c3.read(resumeStoreProvider).keys, [GameMode.vsBot]);
    c3.dispose();
  });

  test('a corrupt saved game is dropped', () async {
    SharedPreferences.setMockInitialValues({'unfinished.otb.v1': '{"bad":1}'});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
    expect(c.read(resumeStoreProvider), isEmpty);
    expect(prefs.getString('unfinished.otb.v1'), isNull);
    c.dispose();
  });

  testWidgets('OTB game is saved as moves are played and offered on the home screen',
      (t) async {
    t.view.physicalSize = const Size(800, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    SharedPreferences.setMockInitialValues({
      'settings.v1':
          '{"touchHold":0,"soundEnabled":false,"mode":"otb","boardSize":9}',
    });
    final prefs = await SharedPreferences.getInstance();
    final container =
        ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
    addTearDown(container.dispose);
    await t.pumpWidget(UncontrolledProviderScope(
        container: container, child: const GoDojoApp()));

    expect(find.textContaining('Continue game'), findsNothing);
    await t.tap(find.text('Over-the-board game (2 players)'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Start game'));
    await t.tap(find.text('Start game'));
    await t.pump();
    await t.pump(const Duration(seconds: 1));

    // Pass and Resign come first, ahead of Undo.
    final pass = t.getCenter(find.text('Pass'));
    final resign = t.getCenter(find.text('Resign'));
    final undo = t.getCenter(find.text('Undo'));
    bool before(Offset a, Offset b) => a.dy < b.dy - 1 || (a.dy - b.dy).abs() <= 1 && a.dx < b.dx;
    expect(before(pass, resign), isTrue);
    expect(before(resign, undo), isTrue);

    await t.ensureVisible(find.text('Pass'));
    await t.tap(find.text('Pass'));
    await t.pump();
    final saved = container.read(resumeStoreProvider)[GameMode.otb];
    expect(saved, isNotNull);
    expect(saved!.moveNumber, 1);
    expect(prefs.getString('unfinished.otb.v1'), isNotNull, reason: 'written to disk');

    Future<void> settle() async {
      await t.pump();
      await t.pump(const Duration(seconds: 1));
    }

    // Back to the menu: choosing the same kind of game offers to continue it.
    await t.pageBack();
    await settle();
    expect(find.textContaining('Continue game'), findsNothing, reason: 'no menu button');
    final otb = find.text('Over-the-board game (2 players)');

    // A bot game is not offered the OTB game.
    await t.tap(find.text('Play against KataGo'));
    await settle();
    expect(find.text('Continue game?'), findsNothing);
    expect(find.text('Start game'), findsOneWidget);
    await t.pageBack();
    await settle();

    // "Yes" continues where it was left.
    await t.tap(otb);
    await settle();
    expect(find.text('Continue game?'), findsOneWidget);
    await t.tap(find.text('Yes'));
    await settle();
    expect(find.text('Move 1 / 1'), findsOneWidget);
    expect(find.textContaining('Black passed'), findsOneWidget);

    // Resigning finishes it, so it is no longer offered.
    await t.ensureVisible(find.text('Resign'));
    await t.tap(find.text('Resign'));
    await settle();
    await t.tap(find.widgetWithText(FilledButton, 'Resign'));
    await settle();
    expect(container.read(resumeStoreProvider), isEmpty);
    expect(prefs.getString('unfinished.otb.v1'), isNull);
    await t.pageBack();
    await settle();

    // Start another game and leave it unfinished.
    await t.tap(otb);
    await settle();
    expect(find.text('Continue game?'), findsNothing);
    await t.ensureVisible(find.text('Start game'));
    await t.tap(find.text('Start game'));
    await settle();
    await t.ensureVisible(find.text('Pass'));
    await t.tap(find.text('Pass'));
    await settle();
    expect(container.read(resumeStoreProvider)[GameMode.otb], isNotNull);
    await t.pageBack();
    await settle();

    // "No" discards it, even if the new game is left without a move.
    await t.tap(otb);
    await settle();
    await t.tap(find.text('No'));
    await settle();
    expect(find.text('Start game'), findsOneWidget);
    expect(container.read(resumeStoreProvider), isEmpty);
    expect(prefs.getString('unfinished.otb.v1'), isNull);
    await t.ensureVisible(find.text('Start game'));
    await t.tap(find.text('Start game'));
    await settle();
    await t.pageBack(); // no moves played
    await settle();
    await t.tap(otb);
    await settle();
    expect(find.text('Continue game?'), findsNothing);
    expect(find.text('Start game'), findsOneWidget);
  });
}
