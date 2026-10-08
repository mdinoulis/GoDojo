import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_core/go_core.dart';

import '../board/board_view.dart';
import '../resume_store.dart';
import '../settings.dart';
import 'game_screen.dart';
import 'new_game_screen.dart';
import 'saved_games_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final unfinished = ref.watch(resumeStoreProvider);
    final preview = Board.fromAscii('''
      . . . . . . . . .
      . . . . . . . . .
      . . X O . . O . .
      . . X O . O X . .
      . . . X O X . . .
      . . . X O . . . .
      . . X O . O . . .
      . . . . . . . . .
      . . . . . . . . .''');
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('GoDojo',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.displaySmall),
                  const SizedBox(height: 4),
                  Text('Play and learn with KataGo',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 24),
                  Center(
                    child: SizedBox(
                      width: 240,
                      height: 240,
                      child: BoardView(
                          board: preview,
                          settings: settings.copyWith(showCoordinates: false)),
                    ),
                  ),
                  const SizedBox(height: 24),
                  for (final mode in GameMode.values)
                    if (unfinished[mode] case final g?) ...[
                      _ContinueButton(game: g),
                      const SizedBox(height: 12),
                    ],
                  FilledButton.icon(
                    icon: const Icon(Icons.smart_toy_outlined),
                    label: const Text('Play against KataGo'),
                    onPressed: () => _newGame(context, GameMode.vsBot),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.people_outline),
                    label: const Text('Over-the-board game (2 players)'),
                    onPressed: () => _newGame(context, GameMode.otb),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.folder_open_outlined),
                    label: const Text('Saved games & review'),
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const SavedGamesScreen())),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.settings_outlined),
                    label: const Text('Settings'),
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const SettingsScreen())),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _newGame(BuildContext context, GameMode mode) {
    Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => NewGameScreen(initialMode: mode)));
  }
}

class _ContinueButton extends StatelessWidget {
  final ResumableGame game;
  const _ContinueButton({required this.game});

  @override
  Widget build(BuildContext context) {
    final g = game;
    final who = g.mode == GameMode.vsBot ? 'vs ${g.level.label}' : 'over the board';
    return FilledButton.icon(
      key: ValueKey('continue-${g.mode.name}'),
      icon: const Icon(Icons.play_arrow),
      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
      label: Column(children: [
        Text('Continue game $who'),
        Text('${g.setup.size}×${g.setup.size} · move ${g.moveNumber}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onPrimary)),
      ]),
      onPressed: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => GameScreen.resume(g))),
    );
  }
}
