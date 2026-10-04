import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Plays one sound asset. Separated out so the choice of file can be tested.
abstract class SoundBackend {
  Future<void> prepare(String asset);
  Future<void> play(String asset);
  void dispose();
}

/// audioplayers implementation: one preloaded player per asset file, looked
/// up by file name so a player can never be playing a different recording.
class AudioPlayersBackend implements SoundBackend {
  final Map<String, Future<AudioPlayer>> _players = {};

  Future<AudioPlayer> _player(String asset) => _players[asset] ??= () async {
        final p = AudioPlayer();
        await p.setPlayerMode(PlayerMode.lowLatency);
        await p.setReleaseMode(ReleaseMode.stop);
        await p.setSource(AssetSource(asset));
        return p;
      }();

  @override
  Future<void> prepare(String asset) async => _player(asset);

  @override
  Future<void> play(String asset) async {
    final p = await _player(asset);
    await p.stop();
    await p.resume();
  }

  @override
  void dispose() {
    for (final f in _players.values) {
      f.then((p) => p.dispose()).ignore();
    }
    _players.clear();
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
