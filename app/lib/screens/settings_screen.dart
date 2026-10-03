import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_core/go_core.dart';
import 'package:katago_engine/katago_engine.dart';

import '../board/board_view.dart';
import '../engine_service.dart';
import '../settings.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  EngineConfig? _resolved;
  String? _testResult;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    final c = await EngineService.resolveConfig(ref.read(settingsProvider));
    if (mounted) setState(() => _resolved = c);
  }

  void _update(AppSettings Function(AppSettings) f) {
    ref.read(settingsProvider.notifier).update(f);
    _resolve();
  }

  void _override(String key, Object? value) {
    _update((s) => s.copyWith(engineOverride: {...?s.engineOverride, key: value}));
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final preview = Board.fromAscii('''
      . . . . . . .
      . . X O . . .
      . X O . O . .
      . X O X X O .
      . . X O . . .
      . . . . . . .
      . . . . . . .''');
    final cfg = _resolved;
    final desktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Board', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Center(
            child: SizedBox(
              width: 220,
              child: BoardView(
                board: preview,
                settings: s,
                decorations: const BoardDecorations(lastMove: Point(3, 3)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _dropdown<BoardTheme>('Board style', s.boardTheme, BoardTheme.values,
              (v) => v.label, (v) => _update((s) => s.copyWith(boardTheme: v))),
          _dropdown<GridColour>('Grid colour', s.gridColour, GridColour.values,
              (v) => v.label, (v) => _update((s) => s.copyWith(gridColour: v))),
          _dropdown<StoneStyle>('Stones', s.stoneStyle, StoneStyle.values,
              (v) => v.label, (v) => _update((s) => s.copyWith(stoneStyle: v))),
          SwitchListTile(
            title: const Text('Show coordinates'),
            value: s.showCoordinates,
            onChanged: (v) => _update((s) => s.copyWith(showCoordinates: v)),
          ),
          SwitchListTile(
            title: const Text('Show move numbers'),
            value: s.showMoveNumbers,
            onChanged: (v) => _update((s) => s.copyWith(showMoveNumbers: v)),
          ),
          SwitchListTile(
            title: const Text('Mark last move'),
            value: s.markLastMove,
            onChanged: (v) => _update((s) => s.copyWith(markLastMove: v)),
          ),
          const Divider(height: 32),
          Text('Engine (KataGo)', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (desktop)
            _text('Engine folder', s.engineDir ?? EngineService.detectDesktopEngineDir() ?? '',
                (v) => _update((s) => s.copyWith(engineDir: v.trim().isEmpty ? null : v.trim()))),
          if (cfg != null) ...[
            _text('Executable', cfg.executable, (v) => _override('executable', v)),
            _text('Main network', cfg.model, (v) => _override('model', v)),
            _text('Human-style network', cfg.humanModel ?? '', (v) => _override('humanModel', v)),
            _text('Analysis config', cfg.configFile, (v) => _override('configFile', v)),
            _slider('Visits for best-move hints', cfg.hintVisits, 50, 5000,
                (v) => _override('hintVisits', v)),
            _slider('Visits for rating a move', cfg.rateVisits, 50, 3000,
                (v) => _override('rateVisits', v)),
            _slider('Visits for score estimate / counting', cfg.estimateVisits, 50, 3000,
                (v) => _override('estimateVisits', v)),
            _slider('Visits for game review', cfg.reviewVisits, 20, 2000,
                (v) => _override('reviewVisits', v)),
            _slider('Bot search visits (human levels)', cfg.botSearchVisits, 1, 400,
                (v) => _override('botSearchVisits', v)),
            _slider('Visits for full-strength bot', cfg.fullStrengthVisits, 50, 10000,
                (v) => _override('fullStrengthVisits', v)),
          ] else
            const Text('KataGo was not found. Set the engine folder above.'),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            FilledButton.tonal(
              onPressed: _testing ? null : _test,
              child: Text(_testing ? 'Testing…' : 'Test engine'),
            ),
            TextButton(
              onPressed: () => _update((s) => s.copyWith(clearEngineOverride: true)),
              child: const Text('Reset engine settings'),
            ),
          ]),
          if (_testResult != null)
            Padding(padding: const EdgeInsets.only(top: 8), child: Text(_testResult!)),
        ],
      ),
    );
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final sw = Stopwatch()..start();
      final engine = await ref.read(engineServiceProvider).engineFor(ref.read(settingsProvider));
      final a = await engine.analyze(Game(const GameSetup(size: 19)), maxVisits: 200, ownership: false);
      _testResult = 'OK – ${a.visits} visits in ${sw.elapsedMilliseconds} ms '
          '(best opening move ${a.best?.point?.toGtp(19)})';
    } catch (e) {
      _testResult = 'Failed: $e';
    }
    if (mounted) setState(() => _testing = false);
  }

  Widget _dropdown<T>(String label, T value, List<T> values, String Function(T) name,
      ValueChanged<T> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: DropdownButtonFormField<T>(
        initialValue: value,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        items: [for (final v in values) DropdownMenuItem(value: v, child: Text(name(v)))],
        onChanged: (v) => onChanged(v as T),
      ),
    );
  }

  Widget _text(String label, String value, ValueChanged<String> onSubmit) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextFormField(
        key: ValueKey('$label=$value'),
        initialValue: value,
        decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            helperText: 'Press Enter to apply'),
        onFieldSubmitted: onSubmit,
      ),
    );
  }

  Widget _slider(String label, int value, int min, int max, ValueChanged<int> onChanged) =>
      _VisitsSlider(
          key: ValueKey('$label=$value'),
          label: label, value: value, min: min, max: max, onChanged: onChanged);
}

class _VisitsSlider extends StatefulWidget {
  final String label;
  final int value, min, max;
  final ValueChanged<int> onChanged;
  const _VisitsSlider({super.key, required this.label, required this.value,
      required this.min, required this.max, required this.onChanged});

  @override
  State<_VisitsSlider> createState() => _VisitsSliderState();
}

class _VisitsSliderState extends State<_VisitsSlider> {
  late double v = widget.value.clamp(widget.min, widget.max).toDouble();

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${widget.label}: ${v.round()}'),
      Slider(
        value: v,
        min: widget.min.toDouble(),
        max: widget.max.toDouble(),
        onChanged: (x) => setState(() => v = x),
        onChangeEnd: (x) => widget.onChanged(x.round()),
      ),
    ]);
  }
}
