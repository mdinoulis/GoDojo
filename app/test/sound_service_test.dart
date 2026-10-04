import 'package:flutter_test/flutter_test.dart';
import 'package:go_study/sound_service.dart';

class FakeBackend implements SoundBackend {
  final played = <String>[];
  @override
  Future<void> prepare(String asset) async {}
  @override
  Future<void> play(String asset) async => played.add(asset);
  @override
  void dispose() {}
}

void main() {
  test('the chosen stone sound is the one played, every time', () async {
    final b = FakeBackend();
    final s = SoundService(b);
    for (var i = 0; i < 10; i++) {
      await s.stonePlayed(0, sound: 1);
    }
    expect(b.played, List.filled(10, 'sounds/stone1.wav'));
  });

  test('previewing another sound does not change what games play', () async {
    final b = FakeBackend();
    final s = SoundService(b);
    await s.preview(4);
    await s.stonePlayed(0, sound: 1);
    await s.preview(3);
    await s.stonePlayed(0, sound: 1);
    expect(b.played, [
      'sounds/stone4.wav',
      'sounds/stone1.wav',
      'sounds/stone3.wav',
      'sounds/stone1.wav',
    ]);
  });

  test('captures add the capture sound after the stone', () async {
    final b = FakeBackend();
    await SoundService(b).stonePlayed(2, sound: 5);
    expect(b.played, ['sounds/stone5.wav', 'sounds/capturing.wav']);
  });

  test('every stone sound maps to its own file', () {
    expect([for (var i = 1; i <= 5; i++) SoundService.stoneAsset(i)], [
      'sounds/stone1.wav',
      'sounds/stone2.wav',
      'sounds/stone3.wav',
      'sounds/stone4.wav',
      'sounds/stone5.wav',
    ]);
  });
}
