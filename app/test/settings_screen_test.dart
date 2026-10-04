import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_study/screens/settings_screen.dart';
import 'package:go_study/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('stone sound picker fits a phone screen and saves the choice', (t) async {
    t.view.physicalSize = const Size(400, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
        overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
    addTearDown(container.dispose);
    await t.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: SettingsScreen()),
    ));
    await t.pumpAndSettle();
    expect(find.text('Stone sound'), findsOneWidget);
    await t.tap(find.text('2'));
    await t.pump();
    expect(container.read(settingsProvider).stoneSound, 2);
    expect(t.takeException(), isNull);
  });
}
