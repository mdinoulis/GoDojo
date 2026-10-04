import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Plays one sound asset. Separated out so the choice of file can be tested.
abstract class SoundBackend {
  Future<void> prepare(String asset);
  Future<void> play(String asset);
  void dispose();
}

/// audioplayers implementation. Each asset gets a small pool of preloaded
/// players, looked up by file name (so a player can never be playing a
/// different recording) and used in turn, so a sound that starts while the
/// previous one is still playing never cuts it off.
class AudioPlayersBackend implements SoundBackend {
  static const voices = 3;
  final Map<String, Future<List<AudioPlayer>>> _pools = {};
  final Map<String, int> _next = {};

  Future<List<AudioPlayer>> _pool(String asset) => _pools[asset] ??= () async {
        return [
          for (var i = 0; i < voices; i++)
            await () async {
              final p = AudioPlayer();
              await p.setPlayerMode(PlayerMode.lowLatency);
              await p.setReleaseMode(ReleaseMode.stop);
              await p.setSource(AssetSource(asset));
              return p;
            }(),
        ];
      }();

  @override
  Future<void> prepare(String asset) async => _pool(asset);

  @override
  Future<void> play(String asset) async {
    final pool = await _pool(asset);
    final i = _next[asset] ?? 0;
    _next[asset] = (i + 1) % pool.length;
    final p = pool[i];
    await p.stop();
    await p.resume();
  }

  @override
  void dispose() {
    for (final f in _pools.values) {
      f.then((pool) {
        for (final p in pool) {
          p.dispose();
        }
      }).ignore();
    }
    _pools.clear();
  }
}

/// Plays recorded stone and capture sounds (assets/sounds, from KaTrain -
/// see assets/sounds/CREDITS.md). The stone recording is chosen in Settings
/// and the same one is used for every move. Failures are ignored - sound is
/// never essential.
class SoundService {
  static const stoneSoundCount = 5;
  static const captureAsset = 'sounds/capturing.wav';

  static String stoneAsset(int sound) =>
      'sounds/stone${sound.clamp(1, stoneSoundCount)}.wav';

  final SoundBackend _backend;
  SoundService([SoundBackend? backend])
      : _backend = backend ?? AudioPlayersBackend();

  /// Loads the sounds for a game in advance so the first move isn't delayed.
  Future<void> warmUp(int sound) async {
    try {
      await _backend.prepare(stoneAsset(sound));
      await _backend.prepare(captureAsset);
    } catch (_) {}
  }

  /// A stone was placed using stone recording [sound] (1-5); [captured]
  /// stones were removed by it.
  Future<void> stonePlayed(int captured, {required int sound}) async {
    try {
      await _backend.play(stoneAsset(sound));
      if (captured > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
        await _backend.play(captureAsset);
      }
    } catch (_) {}
  }

  /// Plays stone recording [sound] once (Settings preview).
  Future<void> preview(int sound) async {
    try {
      await _backend.play(stoneAsset(sound));
    } catch (_) {}
  }

  void dispose() => _backend.dispose();
}

final soundServiceProvider = Provider<SoundService>((ref) {
  final s = SoundService();
  ref.onDispose(s.dispose);
  return s;
});
