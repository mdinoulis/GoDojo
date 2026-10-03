// End-to-end run of the desktop app against the real KataGo engine.
// Saves screenshots to $GOSTUDY_SHOTS (if set).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_study/board/board_view.dart';
import 'package:go_study/main.dart';
import 'package:go_study/settings.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _root = GlobalKey();

Future<void> shot(WidgetTester t, String name) async {
  final dir = Platform.environment['GOSTUDY_SHOTS'];
  if (dir == null) return;
  await t.pump();
  await t.runAsync(() async {
    final b = _root.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final img = await b.toImage(pixelRatio: 1);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    File('$dir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
}

Future<void> waitFor(WidgetTester t, bool Function() cond,
    {Duration timeout = const Duration(seconds: 60)}) async {
  final end = DateTime.now().add(timeout);
  while (!cond()) {
    if (DateTime.now().isAfter(end)) throw TimeoutException('waitFor timed out');
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pump();
  }
  await t.pump();
}

bool hasText(String s) => find.textContaining(s).evaluate().isNotEmpty;

Future<void> tapPoint(WidgetTester t, int x, int y, int size) async {
  final rect = t.getRect(find.byType(BoardView));
  final g = BoardGeometry(rect.width, size, true);
  await t.tapAt(rect.topLeft + g.atIndex(x, y));
  await t.pump();
}

Future<void> tapButton(WidgetTester t, String label) async {
  final f = find.ancestor(
      of: find.text(label), matching: find.bySubtype<ButtonStyleButton>());
  await t.ensureVisible(f.first);
  await t.tap(f.first);
  await t.pump();
}

class TimeoutException implements Exception {
  final String m;
  TimeoutException(this.m);
  @override
  String toString() => m;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('play a 9x9 game against KataGo using every tool', (t) async {
    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1;
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await t.pumpWidget(RepaintBoundary(
      key: _root,
      child: ProviderScope(
        overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
        child: const GoStudyApp(),
      ),
    ));
    await t.pumpAndSettle();
    await shot(t, '01_home');

    await t.tap(find.text('Play against KataGo'));
    await t.pumpAndSettle();
    await t.tap(find.text('9×9'));
    await t.pumpAndSettle();
    expect(find.text('6.5'), findsOneWidget, reason: 'Japanese 6.5 komi default');
    await shot(t, '02_new_game');
    await t.ensureVisible(find.text('Start game'));
    await t.tap(find.text('Start game'));
    await t.pumpAndSettle();

    // Play a few moves; the 10k bot answers each.
    final wanted = [(2, 6), (6, 2), (6, 6), (2, 2), (4, 6), (6, 4), (2, 4), (4, 2)];
    for (var i = 0; i < 4; i++) {
      await waitFor(t, () => hasText('Your move'));
      final board = t.widget<BoardView>(find.byType(BoardView)).board;
      final (x, y) = wanted.firstWhere((p) => board.at(p.$1, p.$2) == null);
      await tapPoint(t, x, y, 9);
      await waitFor(t, () => hasText('is thinking') || hasText('Your move'));
    }
    await waitFor(t, () => hasText('Your move'));
    await shot(t, '03_game');

    await tapButton(t, 'Best moves');
    await waitFor(t, () => hasText('visits'));
    await t.runAsync(() => Future<void>.delayed(const Duration(seconds: 3)));
    await shot(t, '04_hints');
    await tapButton(t, 'Hide hints');

    await tapButton(t, 'Rate my move');
    await waitFor(t, () => hasText('): '));
    await shot(t, '05_rating');

    await tapButton(t, 'Score estimate');
    await waitFor(t, () => hasText('Black win chance'));
    await shot(t, '06_estimate');

    // Multi-step take-back via the navigator, then undo.
    final before = find.textContaining('Move ').evaluate().isNotEmpty;
    expect(before, isTrue);
    await tapButton(t, 'Undo');
    await waitFor(t, () => hasText('Move 6 / 8'));

    await tapButton(t, 'Switch sides');
    await waitFor(t, () => hasText('Your move'));
    expect(hasText('Move 7 /'), isTrue, reason: 'bot played for Black after switching');

    await tapButton(t, 'Count');
    await waitFor(t, () => hasText('Counting (Japanese rules)') && !hasText('Starting'));
    await t.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
    await t.pump();
    await shot(t, '07_counting');
    expect(hasText('not finished'), isTrue);
  }, timeout: const Timeout(Duration(minutes: 5)));


  testWidgets('over-the-board game is counted correctly at the end', (t) async {
    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1;
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await t.pumpWidget(RepaintBoundary(
      key: _root,
      child: ProviderScope(
        overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
        child: const GoStudyApp(),
      ),
    ));
    await t.pumpAndSettle();
    await t.tap(find.text('Over-the-board game (2 players)'));
    await t.pumpAndSettle();
    await t.tap(find.text('9×9'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Start game'));
    await t.tap(find.text('Start game'));
    await t.pumpAndSettle();

    // Black walls off columns A-D, White columns E-J: a finished game.
    for (var y = 0; y < 9; y++) {
      await tapPoint(t, 3, y, 9);
      await tapPoint(t, 4, y, 9);
    }
    await tapButton(t, 'Pass');
    await tapButton(t, 'Pass');
    await waitFor(t, () => hasText('Counting (Japanese rules)'));
    await waitFor(t, () => find.byType(LinearProgressIndicator).evaluate().isEmpty);
    await shot(t, '08_count_finished');
    expect(hasText('White wins by 15.5'), isTrue);
    expect(hasText('not finished'), isFalse);
    await tapButton(t, 'Accept result');
    await t.pump();
    expect(hasText('White wins by 15.5 points'), isTrue);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
