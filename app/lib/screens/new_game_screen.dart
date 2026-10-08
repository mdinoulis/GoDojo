import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_core/go_core.dart';
import 'package:katago_engine/katago_engine.dart';

import '../resume_store.dart';
import '../settings.dart';
import 'game_screen.dart';

enum ColourChoice { black, white, random }

class NewGameScreen extends ConsumerStatefulWidget {
  final GameMode initialMode;
  const NewGameScreen({super.key, required this.initialMode});

  @override
  ConsumerState<NewGameScreen> createState() => _NewGameScreenState();
}

class _NewGameScreenState extends ConsumerState<NewGameScreen> {
  late GameMode mode;
  late int size;
  late Ruleset rules;
  late double komi;
  late int handicap;
  late String levelId;
  late ColourChoice colour;

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider);
    mode = widget.initialMode;
    size = s.boardSize;
    rules = s.rules;
    komi = s.komi;
    handicap = s.handicap.clamp(0, maxHandicap(size));
    levelId = s.levelId;
    colour = s.humanColour == Stone.black ? ColourChoice.black : ColourChoice.white;
  }

  void _resetKomi() => komi = GameSetup.defaultKomi(rules, handicap);

  @override
  Widget build(BuildContext context) {
    final levels = BotLevel.all;
    return Scaffold(
      appBar: AppBar(title: const Text('New game')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section('Opponent'),
          SegmentedButton<GameMode>(
            segments: const [
              ButtonSegment(value: GameMode.vsBot, label: Text('KataGo'), icon: Icon(Icons.smart_toy_outlined)),
              ButtonSegment(value: GameMode.otb, label: Text('Over the board'), icon: Icon(Icons.people_outline)),
            ],
            selected: {mode},
            onSelectionChanged: (v) => setState(() => mode = v.first),
          ),
          if (mode == GameMode.vsBot) ...[
            _section('Bot strength'),
            DropdownButtonFormField<String>(
              initialValue: levelId,
              items: [
                for (final l in levels)
                  DropdownMenuItem(value: l.id, child: Text(l.label)),
              ],
              onChanged: (v) => setState(() => levelId = v!),
            ),
            _section('You play'),
            SegmentedButton<ColourChoice>(
              segments: const [
                ButtonSegment(value: ColourChoice.black, label: Text('Black')),
                ButtonSegment(value: ColourChoice.white, label: Text('White')),
                ButtonSegment(value: ColourChoice.random, label: Text('Random')),
              ],
              selected: {colour},
              onSelectionChanged: (v) => setState(() => colour = v.first),
            ),
          ],
          _section('Board size'),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 9, label: Text('9×9')),
              ButtonSegment(value: 13, label: Text('13×13')),
              ButtonSegment(value: 19, label: Text('19×19')),
            ],
            selected: {size},
            onSelectionChanged: (v) => setState(() {
              size = v.first;
              if (handicap > maxHandicap(size)) {
                handicap = maxHandicap(size);
                _resetKomi();
              }
            }),
          ),
          _section('Rules'),
          DropdownButtonFormField<Ruleset>(
            initialValue: rules,
            items: [
              for (final r in Ruleset.values)
                DropdownMenuItem(value: r, child: Text(r.displayName)),
            ],
            onChanged: (v) => setState(() {
              rules = v!;
              _resetKomi();
            }),
          ),
          _section('Handicap (Black stones)'),
          DropdownButtonFormField<int>(
            initialValue: handicap,
            items: [
              const DropdownMenuItem(value: 0, child: Text('None (even game)')),
              for (var h = 2; h <= maxHandicap(size); h++)
                DropdownMenuItem(value: h, child: Text('$h stones')),
            ],
            onChanged: (v) => setState(() {
              handicap = v!;
              _resetKomi();
            }),
          ),
          _section('Komi (points for White)'),
          Row(children: [
            IconButton.outlined(
                onPressed: () => setState(() => komi -= 0.5),
                icon: const Icon(Icons.remove)),
            Expanded(
              child: Text(komi.toString(),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall),
            ),
            IconButton.outlined(
                onPressed: () => setState(() => komi += 0.5),
                icon: const Icon(Icons.add)),
          ]),
          const SizedBox(height: 32),
          if (ref.watch(resumeStoreProvider)[mode] != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'You have an unfinished ${mode == GameMode.vsBot ? 'game against KataGo' : 'over-the-board game'}. '
                'It is replaced once you play a move in the new game - '
                'go back to continue it instead.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          FilledButton.icon(
            icon: const Icon(Icons.play_arrow),
            label: const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Start game'),
            ),
            onPressed: _start,
          ),
        ],
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(title, style: Theme.of(context).textTheme.titleSmall),
      );

  void _start() {
    final human = switch (colour) {
      ColourChoice.black => Stone.black,
      ColourChoice.white => Stone.white,
      ColourChoice.random => Random().nextBool() ? Stone.black : Stone.white,
    };
    ref.read(settingsProvider.notifier).update((s) => s.copyWith(
          mode: mode,
          boardSize: size,
          rules: rules,
          komi: komi,
          handicap: handicap,
          levelId: levelId,
          humanColour: colour == ColourChoice.random ? s.humanColour : human,
        ));
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => GameScreen(
        setup: GameSetup(size: size, rules: rules, komi: komi, handicap: handicap),
        mode: mode,
        humanColour: human,
        level: BotLevel.byId(levelId),
      ),
    ));
  }
}
