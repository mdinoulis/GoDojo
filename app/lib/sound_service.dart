import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Plays recorded stone and capture sounds (assets/sounds, from KaTrain -
/// see assets/sounds/CREDITS.md). The stone recording is chosen in Settings
/// and the same one is used for every move. Failures are ignored - sound is
/// never essential.
class SoundService {
  static const stoneSoundCount = 5;

  final _stones = [for (var i = 0; i < stoneSoundCount; i++) AudioPlayer()];
  final _capture = AudioPlayer();
  Future<void>? _ready;

  Future<void> _init() => _ready ??= () async {
        for (var i = 0; i < stoneSoundCount; i++) {
          await _prepare(_stones[i], 'sounds/stone${i + 1}.wav');
        }
        await _prepare(_capture, 'sounds/capturing.wav');
      }();

  static Future<void> _prepare(AudioPlayer p, String file) async {
    await p.setPlayerMode(PlayerMode.lowLatency);
    await p.setReleaseMode(ReleaseMode.stop);
    await p.setSource(AssetSource(file));
  }

  Future<void> _playStone(int sound) async {
    final p = _stones[(sound - 1).clamp(0, stoneSoundCount - 1)];
    await p.stop();
    await p.resume();
  }

  /// A stone was placed using stone recording [sound] (1-5); [captured]
  /// stones were removed by it.
  Future<void> stonePlayed(int captured, {int sound = 4}) async {
    try {
      await _init();
      await _playStone(sound);
      if (captured > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
        await _capture.stop();
        await _capture.resume();
      }
    } catch (_) {}
  }

  /// Plays stone recording [sound] once (Settings preview).
  Future<void> preview(int sound) async {
    try {
      await _init();
      await _playStone(sound);
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
