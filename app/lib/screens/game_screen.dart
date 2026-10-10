import 'dart:async';
import 'dart:io';
import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_core/go_core.dart';
import 'package:katago_engine/katago_engine.dart';
import 'package:path_provider/path_provider.dart';

import '../board/board_view.dart';
import '../engine_service.dart';
import '../game_controller.dart';
import '../resume_store.dart';
import '../settings.dart';
import '../sound_service.dart';
import 'quality.dart';
import 'review_screen.dart';

class GameScreen extends ConsumerStatefulWidget {
  final GameSetup setup;
  final GameMode mode;
  final Stone humanColour;
  final BotLevel level;

  /// An unfinished game to continue instead of starting a new one.
  final Game? resume;

  const GameScreen({
    super.key,
    required this.setup,
    required this.mode,
    required this.humanColour,
    required this.level,
    this.resume,
  });

  GameScreen.resume(ResumableGame g, {Key? key})
      : this(
          key: key,
          setup: g.setup,
          mode: g.mode,
          humanColour: g.humanColour,
          level: g.level,
          resume: g.toGame(),
        );

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  late final GameController c;
  StreamSubscription<String>? _msgSub;
  String? _savedJson;

  // Portrait has no room for the counting card, so the score is shown in a
  // dialog: opened once the count is ready, reopened with the Count button.
  bool _portrait = true;
  bool _scoreDialogOpen = false;
  bool _scoreAutoShown = false;

  /// Whether the saved unfinished game (for this mode) is this one - a new
  /// game only replaces it once a move has been played.
  late bool _ownsSaved = widget.resume != null;

  @override
  void initState() {
    super.initState();
    c = GameController(
      engines: ref.read(engineServiceProvider),
      settings: () => ref.read(settingsProvider),
      setup: widget.setup,
      mode: widget.mode,
      humanColour: widget.humanColour,
      level: widget.level,
      resume: widget.resume,
    );
    c.addListener(_persist);
    c.addListener(_watchScoring);
    final sounds = ref.read(soundServiceProvider);
    sounds.warmUp(ref.read(settingsProvider).stoneSound);
    c.onStonePlayed = (move, captured) {
      final s = ref.read(settingsProvider);
      if (s.soundEnabled) sounds.stonePlayed(captured, sound: s.stoneSound);
    };
    _msgSub = c.messages.listen((m) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 3)));
    });
    // Warm up the engine (and let the bot open if it plays Black).
    final engines = ref.read(engineServiceProvider);
    engines.engineFor(ref.read(settingsProvider)).then((_) {
      if (!mounted) return;
      if (c.game.bothPassed && c.game.result == null) {
        c.startScoring(); // the game was left while counting
      } else if (!c.game.canRedo) {
        c.startIfBotToMove(); // else wait for "Bot move" (user went back)
      }
    }).catchError((Object e) {
      if (mounted && widget.mode == GameMode.vsBot) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    });
  }

  /// Keeps the unfinished game saved so it can be continued later, even
  /// after the app is closed or the power fails; forgets it once finished.
  void _persist() {
    final store = ref.read(resumeStoreProvider.notifier);
    final snap = ResumableGame.of(c.game,
        mode: c.mode, humanColour: c.humanColour, level: c.level);
    if (snap == null) {
      if (c.game.result != null && _ownsSaved) {
        store.clear(c.mode);
        _savedJson = null;
      }
      return;
    }
    final json = snap.toJson()..remove('savedAt');
    final key = json.toString();
    if (key == _savedJson) return;
    _savedJson = key;
    _ownsSaved = true;
    store.save(snap);
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final engines = ref.watch(engineServiceProvider);
    return ListenableBuilder(
      listenable: Listenable.merge([c, engines]),
      builder: (context, _) {
        final board = BoardView(
          board: c.game.board,
          settings: settings,
          decorations: _decorations(settings),
          onTap: c.tap,
          ghost: c.canPlay ? c.game.toMove : null,
        );
        return Scaffold(
          appBar: AppBar(
            title: Text(_title()),
            actions: [
              IconButton(
                tooltip: 'Review game',
                icon: const Icon(Icons.query_stats),
                onPressed: c.game.moveNumber >= 2 && !c.botThinking ? _review : null,
              ),
              IconButton(
                tooltip: 'Save SGF',
                icon: const Icon(Icons.save_alt),
                onPressed: _saveSgf,
              ),
            ],
          ),
          body: SafeArea(
            child: LayoutBuilder(builder: (context, box) {
              final wide = box.maxWidth > box.maxHeight * 1.15;
              _portrait = !wide;
              if (wide) {
                return Row(children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Center(child: board),
                    ),
                  ),
                  SizedBox(
                    width: 360,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
                      children: _panel(engines),
                    ),
                  ),
                ]);
              }
              // Portrait: the board shrinks just enough for the players, board,
              // buttons and move slider to fit the screen exactly, so it does
              // not slide when touched. Cards (hints, counting...) and engine
              // notices follow below and scroll into view.
              const pad = 8.0;
              final list = ListView(
                // Only scrolls when a card makes it taller than the screen.
                primary: false,
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.all(pad),
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(
                        maxHeight: (box.maxHeight - 2 * pad).floorToDouble()),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      _playersBar(),
                      const SizedBox(height: 6),
                      Flexible(child: board),
                      ..._controls(),
                    ]),
                  ),
                  ..._cards(engines, starting: false),
                ],
              );
              // Engine start-up shows as a thin bar over the top edge, so it
              // takes no room from the layout.
              return Stack(children: [
                list,
                if (engines.status == EngineStatus.starting)
                  const Positioned(
                      top: 0, left: 0, right: 0, child: LinearProgressIndicator(minHeight: 3)),
              ]);
            }),
          ),
        );
      },
    );
  }

  String _title() {
    final s = widget.setup;
    final opp = c.isVsBot ? 'vs ${c.level.label}' : 'Over the board';
    return '$opp · ${s.size}×${s.size} · ${s.rules.displayName}';
  }

  // ---------------------------------------------------------------------------
  // Board decorations

  BoardDecorations _decorations(AppSettings settings) {
    final game = c.game;
    Map<Point, int>? numbers;
    if (settings.showMoveNumbers) {
      numbers = {};
      final moves = game.moves;
      for (var i = 0; i < moves.length; i++) {
        final p = moves[i].point;
        if (p != null) numbers[p] = i + 1;
      }
    }
    final last = settings.markLastMove ? game.lastMove?.point : null;

    final scoring = c.scoring;
    if (scoring != null) {
      return BoardDecorations(
        lastMove: last,
        moveNumbers: numbers,
        scoring: scoring.result.status,
        gaps: scoring.accepted ? const {} : scoring.allGaps,
        unsettled: scoring.accepted ? const {} : scoring.result.unsettled,
      );
    }

    switch (c.overlay) {
      case BoardOverlay.hints:
        final a = c.hints;
        if (a == null || a.best == null) break;
        final mover = a.toMove;
        final bestScore = a.best!.scoreFor(mover);
        final minVisits = (a.best!.visits * 0.03).clamp(1, 1 << 30);
        final cands = <CandidateMark>[];
        for (final m in a.moves.take(10)) {
          if (m.point == null || m.visits < minVisits) continue;
          final loss = bestScore - m.scoreFor(mover);
          cands.add(CandidateMark(
            m.point!,
            signed(m.scoreFor(mover)),
            lossColor(loss),
            subLabel: '${(m.winrateFor(mover) * 100).round()}%',
            best: m.order == 0,
          ));
        }
        return BoardDecorations(lastMove: last, moveNumbers: numbers, candidates: cands);
      case BoardOverlay.rating:
        final r = c.rating;
        if (r == null) break;
        final played = r.move.point;
        final playedScore = r.rating.best!.scoreFor(r.move.color) - r.rating.pointLoss;
        return BoardDecorations(
          lastMove: last,
          moveNumbers: numbers,
          rings: {?played: qualityColor(r.rating.quality)},
          candidates: [
            for (final m in r.rating.betterMoves.take(4))
              if (m.point != null && c.game.board[m.point!] == null)
                CandidateMark(
                  m.point!,
                  signed(m.scoreFor(r.move.color) - playedScore),
                  lossColor(r.rating.best!.scoreFor(r.move.color) - m.scoreFor(r.move.color)),
                  best: m == r.rating.best,
                ),
          ],
        );
      case BoardOverlay.estimate:
        return BoardDecorations(
            lastMove: last, moveNumbers: numbers, ownership: c.estimate?.ownership);
      case BoardOverlay.none:
        break;
    }
    return BoardDecorations(lastMove: last, moveNumbers: numbers);
  }

  // ---------------------------------------------------------------------------
  // Side panel

  List<Widget> _panel(EngineService engines) => [
        _playersBar(),
        ..._notices(engines),
        ..._controls(),
        ..._cards(engines, notices: false),
      ];

  List<Widget> _notices(EngineService engines, {bool starting = true}) => [
        if (starting && engines.status == EngineStatus.starting)
          const _Notice(icon: Icons.hourglass_top, text: 'Starting KataGo…'),
        if (engines.status == EngineStatus.error && engines.error != null)
          _Notice(icon: Icons.error_outline, text: engines.error!, error: true),
      ];

  List<Widget> _controls() => [
        const SizedBox(height: 8),
        _actions(),
        const SizedBox(height: 2),
        _navigator(),
      ];

  List<Widget> _cards(EngineService engines,
      {bool notices = true, bool starting = true}) {
    final cards = [
      if (notices) ..._notices(engines, starting: starting),
      if (c.scoring != null && !_portrait) _scoringCard(),
      if (c.scoring == null && c.overlay == BoardOverlay.hints) _hintsCard(),
      if (c.scoring == null && c.overlay == BoardOverlay.rating) _ratingCard(),
      if (c.scoring == null && c.overlay == BoardOverlay.estimate) _estimateCard(),
    ];
    return [if (cards.isNotEmpty) const SizedBox(height: 8), ...cards];
  }

  Widget _playersBar() {
    final g = c.game;
    String name(Stone s) {
      if (!c.isVsBot) return s == Stone.black ? 'Black' : 'White';
      return s == c.humanColour ? 'You' : c.level.label;
    }

    Widget player(Stone s) {
      final toMove = !g.isOver && g.toMove == s && c.scoring == null;
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: toMove ? Theme.of(context).colorScheme.primary : Colors.transparent,
              width: 2,
            ),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          child: Row(children: [
            CircleAvatar(
              radius: 9,
              backgroundColor: s == Stone.black ? Colors.black : Colors.white,
              child: Container(
                decoration: BoxDecoration(
                    shape: BoxShape.circle, border: Border.all(color: Colors.black54)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name(s), overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text('Captures: ${g.prisoners(s)}'
                    '${s == Stone.white ? ' · Komi ${g.setup.komi}' : ''}',
                    style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),
            if (toMove && c.botThinking && name(s) != 'You')
              const SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          ]),
        ),
      );
    }

    return Column(children: [
      Row(children: [player(Stone.black), const SizedBox(width: 8), player(Stone.white)]),
      const SizedBox(height: 6),
      Text(_status(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleSmall),
    ]);
  }

  String _status() {
    final g = c.game;
    if (g.result != null) return c.resultText();
    if (c.scoring != null) return 'Counting – tap stones to mark them dead/alive';
    if (c.botThinking) return '${c.level.label} is thinking…';
    if (c.botWaiting) return 'Bot to play – press "Bot move" to continue';
    final last = g.lastMove;
    final passed = last != null && last.isPass ? ' (${last.color == Stone.black ? 'Black' : 'White'} passed)' : '';
    if (!c.isVsBot) return '${g.toMove == Stone.black ? 'Black' : 'White'} to play$passed';
    return 'Your move$passed';
  }

  Widget _actions() {
    final over = c.game.isOver;
    final scoring = c.scoring != null;
    final scheme = Theme.of(context).colorScheme;
    final btns = <Widget>[
      FilledButton.icon(
        onPressed: c.canPlay ? c.pass : null,
        icon: const Icon(Icons.skip_next, size: 18),
        label: const Text('Pass'),
        style: FilledButton.styleFrom(
          visualDensity: VisualDensity.compact,
          backgroundColor: scheme.tertiary,
          foregroundColor: scheme.onTertiary,
        ),
      ),
      _btn(Icons.flag_outlined, 'Resign', !over && !scoring ? _confirmResign : null),
      _btn(Icons.undo, 'Undo', c.game.canUndo && !(c.scoring?.accepted ?? false) ? c.undo : null),
      _btn(Icons.redo, 'Redo', c.game.canRedo && !c.botThinking ? c.redo : null),
      if (c.isVsBot)
        _btn(Icons.swap_horiz, 'Switch sides', !over && !scoring ? c.switchSides : null),
      if (c.botWaiting) _btn(Icons.smart_toy_outlined, 'Bot move', c.botPlayNow),
      _btn(Icons.lightbulb_outline, c.overlay == BoardOverlay.hints ? 'Hide hints' : 'Best moves',
          !scoring && !c.game.isOver ? c.toggleHints : null,
          selected: c.overlay == BoardOverlay.hints),
      _btn(Icons.grading, 'Rate my move',
          !scoring && c.moveToRate != null && !c.busy ? c.rateLastMove : null,
          selected: c.overlay == BoardOverlay.rating),
      _btn(Icons.pie_chart_outline, 'Score estimate', !scoring ? c.toggleEstimate : null,
          selected: c.overlay == BoardOverlay.estimate),
      _btn(
          Icons.calculate_outlined,
          'Count',
          scoring && _portrait
              ? _showScore // reopens the score while counting
              : !scoring && c.game.result == null
                  ? c.startScoring
                  : null),
    ];
    return Wrap(spacing: 6, runSpacing: 6, children: btns);
  }

  Widget _btn(IconData icon, String label, VoidCallback? onPressed, {bool selected = false}) {
    final style = selected
        ? FilledButton.styleFrom(visualDensity: VisualDensity.compact)
        : null;
    return selected
        ? FilledButton.icon(onPressed: onPressed, icon: Icon(icon, size: 18), label: Text(label), style: style)
        : OutlinedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon, size: 18),
            label: Text(label),
            style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact));
  }

  Widget _navigator() {
    final g = c.game;
    final total = g.lineLength;
    return Card(
      // Snug under the buttons, leaving more height for the board.
      margin: const EdgeInsets.fromLTRB(4, 0, 4, 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
        child: Column(children: [
          Row(children: [
            IconButton(
                tooltip: 'Start',
                onPressed: g.moveNumber > 0 ? () => c.goTo(0) : null,
                icon: const Icon(Icons.first_page)),
            IconButton(
                tooltip: 'Back one move',
                onPressed: g.moveNumber > 0 ? () => c.goTo(g.moveNumber - 1) : null,
                icon: const Icon(Icons.chevron_left)),
            Expanded(
              child: Text('Move ${g.moveNumber} / $total',
                  textAlign: TextAlign.center),
            ),
            IconButton(
                tooltip: 'Forward one move',
                onPressed: g.canRedo ? () => c.goTo(g.moveNumber + 1) : null,
                icon: const Icon(Icons.chevron_right)),
            IconButton(
                tooltip: 'Latest',
                onPressed: g.canRedo ? () => c.goTo(total) : null,
                icon: const Icon(Icons.last_page)),
          ]),
          // Always the same height, so the board never resizes during play.
          Slider(
            value: g.moveNumber.toDouble(),
            max: max(total, 1).toDouble(),
            divisions: max(total, 1),
            label: '${g.moveNumber}',
            onChanged: total > 0 ? (v) => c.goTo(v.round()) : null,
          ),
          Visibility.maintain(
            visible: g.canRedo,
            child: Text('Playing a new move here discards the later moves',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall),
          ),
        ]),
      ),
    );
  }

  Widget _hintsCard() {
    final a = c.hints;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('Best moves', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            if (a != null) Text('${a.visits} visits', style: Theme.of(context).textTheme.bodySmall),
          ]),
          const SizedBox(height: 6),
          if (a == null) const LinearProgressIndicator(),
          if (a != null) ...[
            Text('Position: ${leadText(a.scoreLead)} · Black win ${(a.winrate * 100).toStringAsFixed(0)}%'),
            const SizedBox(height: 6),
            for (final m in a.moves.take(6))
              _candidateRow(m, a.best!.scoreFor(a.toMove) - m.scoreFor(a.toMove), a.toMove),
          ],
        ]),
      ),
    );
  }

  Widget _candidateRow(MoveCandidate m, double loss, Stone mover) {
    final size = c.game.size;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(color: lossColor(loss), shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        SizedBox(width: 48, child: Text(m.point?.toGtp(size) ?? 'Pass',
            style: const TextStyle(fontWeight: FontWeight.w600))),
        Expanded(child: Text('lead ${signed(m.scoreFor(mover))} · '
            'win ${(m.winrateFor(mover) * 100).toStringAsFixed(1)}%')),
        Text(loss <= 0.05 ? 'best' : '−${loss.toStringAsFixed(1)}',
            style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }

  Widget _ratingCard() {
    final r = c.rating;
    final size = c.game.size;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: r == null
            ? const Column(children: [Text('Rating your move…'), SizedBox(height: 8), LinearProgressIndicator()])
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(qualityIcon(r.rating.quality), color: qualityColor(r.rating.quality), size: 28),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        'Move ${r.moveNumber} (${r.move.toGtp(size)}): ${r.rating.quality.label}',
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                ]),
                const SizedBox(height: 6),
                Text(r.rating.pointLoss < 0.05
                    ? 'This was the engine\'s top choice.'
                    : 'Lost ${r.rating.pointLoss.toStringAsFixed(1)} points '
                        '(${(r.rating.winrateLoss * 100).toStringAsFixed(1)}% winrate) '
                        'compared with ${r.rating.best?.point?.toGtp(size) ?? 'pass'}.'),
                if (r.rating.betterMoves.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Better alternatives', style: Theme.of(context).textTheme.titleSmall),
                  for (final m in r.rating.betterMoves.take(4))
                    _candidateRow(
                        m,
                        r.rating.best!.scoreFor(r.move.color) - m.scoreFor(r.move.color),
                        r.move.color),
                  const SizedBox(height: 4),
                  Text('Numbers on the board show how many points each move gains over yours.',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ]),
      ),
    );
  }

  Widget _estimateCard() {
    final a = c.estimate;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: a == null
            ? const Column(children: [Text('Estimating score…'), SizedBox(height: 8), LinearProgressIndicator()])
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Score estimate', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(leadText(a.scoreLead),
                    style: Theme.of(context).textTheme.headlineMedium),
                Text('Black win chance ${(a.winrate * 100).toStringAsFixed(1)}% '
                    '(komi ${c.game.setup.komi} included)'),
                const SizedBox(height: 4),
                Text('Squares show who is likely to own each point; '
                    'crossed stones are probably dead.',
                    style: Theme.of(context).textTheme.bodySmall),
              ]),
      ),
    );
  }

  Widget _scoringCard() {
    final s = c.scoring!;
    final r = s.result;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Counting (${r.rules.displayName} rules)',
              style: Theme.of(context).textTheme.titleMedium),
          ..._scoreDetails(context),
          const SizedBox(height: 8),
          Text('Tap a stone to toggle it dead/alive.', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          if (!s.accepted)
            Wrap(spacing: 8, runSpacing: 6, children: [
              FilledButton(onPressed: c.acceptScore, child: const Text('Accept result')),
              OutlinedButton(onPressed: c.resumePlay, child: const Text('Resume play')),
            ])
          else
            Wrap(spacing: 8, runSpacing: 6, children: [
              FilledButton.icon(
                  onPressed: _review,
                  icon: const Icon(Icons.query_stats),
                  label: const Text('Review game')),
              OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(), child: const Text('Back to menu')),
            ]),
        ]),
      ),
    );
  }

  /// Score table, result and warnings - shared by the card and the dialog.
  List<Widget> _scoreDetails(BuildContext context) {
    final s = c.scoring!;
    final r = s.result;
    final territory = r.rules.scoring == ScoringType.territory;
    String fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
    TableRow row(String label, Object b, Object w) => TableRow(children: [
          Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text(label)),
          Text('$b', textAlign: TextAlign.right),
          Text('$w', textAlign: TextAlign.right),
        ]);
    return [
      if (c.busy) const Padding(
          padding: EdgeInsets.symmetric(vertical: 6), child: LinearProgressIndicator()),
      const SizedBox(height: 8),
      Table(columnWidths: const {0: FlexColumnWidth(2)}, children: [
        row('', 'Black', 'White'),
        if (territory) ...[
          row('Territory', r.blackTerritory, r.whiteTerritory),
          row('Prisoners', r.blackPrisoners, r.whitePrisoners),
        ] else ...[
          row('Stones', r.blackStones, r.whiteStones),
          row('Territory', r.blackTerritory, r.whiteTerritory),
          if (r.handicapBonus > 0) row('Handicap comp.', '', r.handicapBonus),
        ],
        row('Komi', '', fmt(r.komi)),
        row('Total', fmt(r.blackScore), fmt(r.whiteScore)),
      ]),
      const SizedBox(height: 8),
      Text(_scoreLine(r), style: Theme.of(context).textTheme.titleMedium),
      if (r.sekiStones.isNotEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text('◆ Seki detected – points in seki are not counted as territory.'),
        ),
      if (!s.isFinished && !s.accepted) ...[
        const SizedBox(height: 8),
        _Notice(
          icon: Icons.warning_amber,
          error: true,
          text: [
            'The game is not finished.',
            if (r.unsettled.isNotEmpty) 'Areas marked with red dots are still open.',
            if (s.allGaps.isNotEmpty)
              '${s.allGaps.length} point(s) marked "?" still need to be played '
                  '(open borders, dame or protective moves).',
          ].join(' '),
        ),
      ],
    ];
  }

  void _watchScoring() {
    if (!c.isScoring) {
      _scoreAutoShown = false;
      return;
    }
    if (_portrait && !c.busy && !_scoreAutoShown && !_scoreDialogOpen &&
        !c.scoring!.accepted) {
      _scoreAutoShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && c.isScoring) _showScore();
      });
    }
  }

  /// The counting result as a dialog over the board (portrait layout).
  Future<void> _showScore() async {
    if (_scoreDialogOpen || !c.isScoring) return;
    _scoreDialogOpen = true;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => ListenableBuilder(
        listenable: c,
        builder: (ctx, _) {
          final s = c.scoring;
          if (s == null) return const SizedBox.shrink();
          void close([String? a]) => Navigator.pop(ctx, a);
          return AlertDialog(
            title: Text(s.accepted
                ? 'Result'
                : 'Counting (${s.result.rules.displayName} rules)'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ..._scoreDetails(ctx),
                  if (!s.accepted) ...[
                    const SizedBox(height: 8),
                    Text('Wrong dead stones? Tap "Mark stones", tap the stones on '
                        'the board, then "Count" to see the score again.',
                        style: Theme.of(ctx).textTheme.bodySmall),
                  ],
                ],
              ),
            ),
            actions: s.accepted
                ? [
                    TextButton(onPressed: close, child: const Text('Close')),
                    OutlinedButton(
                        onPressed: () => close('menu'), child: const Text('Back to menu')),
                    FilledButton(
                        onPressed: () => close('review'), child: const Text('Review game')),
                  ]
                : [
                    TextButton(onPressed: close, child: const Text('Mark stones')),
                    OutlinedButton(
                        onPressed: () => close('resume'), child: const Text('Resume play')),
                    FilledButton(
                        onPressed: c.busy ? null : c.acceptScore, child: const Text('Accept')),
                  ],
          );
        },
      ),
    );
    _scoreDialogOpen = false;
    if (!mounted) return;
    switch (action) {
      case 'resume':
        c.resumePlay();
      case 'review':
        _review();
      case 'menu':
        Navigator.of(context).pop();
    }
  }

  String _scoreLine(ScoreResult r) {
    final m = r.margin;
    if (m == 0) return 'Jigo (draw)';
    return '${m > 0 ? 'Black' : 'White'} wins by ${m.abs().toStringAsFixed(1)}';
  }

  void _review() {
    final names = _names();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ReviewScreen(
        game: c.game.copy(),
        player: c.isVsBot ? c.humanColour : null,
        blackName: names.$1,
        whiteName: names.$2,
      ),
    ));
  }

  (String, String) _names() {
    if (!c.isVsBot) return ('Black', 'White');
    final bot = 'KataGo ${c.level.label}';
    return c.humanColour == Stone.black ? ('You', bot) : (bot, 'You');
  }

  Future<void> _confirmResign() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Resign?'),
        content: Text(c.isVsBot ? 'Resign this game?' : '${c.game.toMove == Stone.black ? 'Black' : 'White'} resigns?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Resign')),
        ],
      ),
    );
    if (ok == true) c.resign();
  }

  Future<void> _saveSgf() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final folder = Directory('${dir.path}${Platform.pathSeparator}GoDojo');
      await folder.create(recursive: true);
      final now = DateTime.now();
      String two(int v) => v.toString().padLeft(2, '0');
      final name = 'game-${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}${two(now.second)}.sgf';
      final file = File('${folder.path}${Platform.pathSeparator}$name');
      final names = _names();
      await file.writeAsString(Sgf.export(
        c.game,
        blackName: names.$1,
        whiteName: names.$2,
        date: now,
        app: 'GoDojo',
      ));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved ${file.path}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    }
  }
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool error;
  const _Notice({required this.icon, required this.text, this.error = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: error ? scheme.errorContainer : scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        Icon(icon, color: error ? scheme.onErrorContainer : scheme.onSecondaryContainer),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ]),
    );
  }
}
