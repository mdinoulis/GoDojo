import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_core/go_core.dart';
import 'package:godojo/board/board_view.dart';
import 'package:godojo/main.dart';
import 'package:godojo/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('home screen shows the main actions', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      child: const GoDojoApp(),
    ));
    expect(find.text('Play against KataGo'), findsOneWidget);
    expect(find.text('Over-the-board game (2 players)'), findsOneWidget);
  });

  testWidgets('tapping the board reports the intersection', (tester) async {
    Point? tapped;
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: SizedBox(
          width: 400,
          height: 400,
          child: BoardView(
            board: Board(9),
            settings: const AppSettings(showCoordinates: false),
            onTap: (p) => tapped = p,
          ),
        ),
      ),
    ));
    // Top-left intersection sits 0.7 cells in from the corner.
    final box = tester.getTopLeft(find.byType(BoardView));
    const cell = 400 / (8 + 1.4);
    await tester.tapAt(box + const Offset(cell * 0.7, cell * 0.7));
    expect(tapped, const Point(0, 0));
    await tester.tapAt(box + const Offset(cell * 4.7, cell * 2.7));
    expect(tapped, const Point(4, 2));
  });
}
