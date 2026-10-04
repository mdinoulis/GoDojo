import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Plays recorded stone and capture sounds (assets/sounds, from KaTrain -
/// see assets/sounds/CREDITS.md). If several stone recordings are listed,
/// one is picked at random each move. Failures are ignored - sound is never
/// essential.
class SoundService {
  static const _stoneFiles = ['sounds/stone4.wav'];

  final _stones = [for (final _ in _stoneFiles) AudioPlayer()];
  final _capture = AudioPlayer();
  final _random = Random();
  int _last = -1;
  Future<void>? _ready;

  Future<void> _init() => _ready ??= () async {
        for (var i = 0; i < _stones.length; i++) {
          await _prepare(_stones[i], _stoneFiles[i]);
        }
        await _prepare(_capture, 'sounds/capturing.wav');
      }();

  static Future<void> _prepare(AudioPlayer p, String file) async {
    await p.setPlayerMode(PlayerMode.lowLatency);
    await p.setReleaseMode(ReleaseMode.stop);
    await p.setSource(AssetSource(file));
  }

  /// A stone was placed; [captured] stones were removed by it.
  Future<void> stonePlayed(int captured) async {
    try {
      await _init();
      var i = _random.nextInt(_stones.length);
      if (i == _last && _stones.length > 1) i = (i + 1) % _stones.length;
      _last = i;
      await _stones[i].stop();
      await _stones[i].resume();
      if (captured > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
        await _capture.stop();
        await _capture.resume();
      }
    } catch (_) {}
  }

  void dispose() {
    for (final p in _stones) {
      p.dispose();
    }
    _capture.dispose();
  }
}

final soundServiceProvider = Provider<SoundService>((ref) {
  final s = SoundService();
  ref.onDispose(s.dispose);
  return s;
});
