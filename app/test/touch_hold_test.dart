import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_core/go_core.dart';
import 'package:godojo/board/board_view.dart';
import 'package:godojo/settings.dart';

void main() {
  final taps = <Point>[];
  const cell = 400 / (8 + 1.4);
  Offset at(WidgetTester t, int x, int y) =>
      t.getTopLeft(find.byType(BoardView)) +
      Offset(cell * (0.7 + x), cell * (0.7 + y));

  Future<void> board(WidgetTester t, {double hold = 0.25}) async {
    taps.clear();
    await t.pumpWidget(MaterialApp(
      home: Center(
        child: SizedBox(
          width: 400,
          height: 400,
          child: BoardView(
            board: Board(9),
            settings: AppSettings(showCoordinates: false, touchHoldSeconds: hold),
            onTap: taps.add,
            ghost: Stone.black,
          ),
        ),
      ),
    ));
  }

  test('hold time defaults to 0.25 s, persists and is kept in 0-1 s', () {
    expect(const AppSettings().touchHoldSeconds, 0.25);
    final s = const AppSettings().copyWith(touchHoldSeconds: 0.6);
    expect(AppSettings.fromJson(s.toJson()).touchHoldSeconds, 0.6);
    expect(AppSettings.fromJson({'touchHoldSeconds': 3}).touchHoldSeconds, 1.0);
    expect(AppSettings.fromJson({'touchHoldSeconds': -1}).touchHoldSeconds, 0.0);
    expect(AppSettings.fromJson({}).touchHoldSeconds, 0.25);
  });

  testWidgets('a quick touch is ignored', (t) async {
    await board(t);
    final g = await t.startGesture(at(t, 2, 3));
    await t.pump(const Duration(milliseconds: 200));
    await g.up();
    await t.pump(const Duration(seconds: 1));
    expect(taps, isEmpty);
  });

  testWidgets('holding for the hold time places the stone', (t) async {
    await board(t);
    final g = await t.startGesture(at(t, 2, 3));
    await t.pump(const Duration(milliseconds: 240));
    expect(taps, isEmpty);
    await t.pump(const Duration(milliseconds: 20));
    expect(taps, [const Point(2, 3)]);
    await g.up();
    await t.pump(const Duration(seconds: 1));
    expect(taps, [const Point(2, 3)], reason: 'placed once only');
  });

  testWidgets('sliding to another point cancels the press', (t) async {
    await board(t);
    final g = await t.startGesture(at(t, 2, 3));
    await t.pump(const Duration(milliseconds: 100));
    await g.moveTo(at(t, 3, 3));
    await t.pump(const Duration(seconds: 1));
    await g.up();
    expect(taps, isEmpty);
  });

  testWidgets('a second finger cancels the press', (t) async {
    await board(t);
    final a = await t.startGesture(at(t, 2, 3));
    final b = await t.startGesture(at(t, 6, 6), pointer: 7);
    await t.pump(const Duration(seconds: 1));
    await a.up();
    await b.up();
    expect(taps, isEmpty);
  });

  testWidgets('the hold time follows the setting', (t) async {
    await board(t, hold: 0.8);
    final g = await t.startGesture(at(t, 4, 4));
    await t.pump(const Duration(milliseconds: 500));
    expect(taps, isEmpty);
    await t.pump(const Duration(milliseconds: 310));
    expect(taps, [const Point(4, 4)]);
    await g.up();
  });

  testWidgets('hold time 0 places on a normal tap', (t) async {
    await board(t, hold: 0);
    await t.tapAt(at(t, 1, 1));
    expect(taps, [const Point(1, 1)]);
  });

  testWidgets('mouse clicks place at once', (t) async {
    await board(t);
    final g = await t.startGesture(at(t, 5, 5), kind: PointerDeviceKind.mouse);
    await g.up();
    expect(taps, [const Point(5, 5)]);
  });
}
