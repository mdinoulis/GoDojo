import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_core/go_core.dart';

import '../board/board_view.dart';
import '../settings.dart';
import 'new_game_screen.dart';
import 'saved_games_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
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
                  Text('Go Study',
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
