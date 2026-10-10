import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_core/go_core.dart';
import 'package:godojo/engine_service.dart';
import 'package:godojo/game_controller.dart';
import 'package:godojo/settings.dart';
import 'package:katago_engine/katago_engine.dart';

/// Analysis requests stay pending until the test answers them.
class _ManualEngine implements KataGoEngine {
  final pending = <Completer<PositionAnalysis>>[];

  @override
  EngineConfig get config => EngineConfig.desktop('engine');

  @override
  Future<PositionAnalysis> analyze(Game game,
      {int? moveCount,
      int? maxVisits,
      bool ownership = true,
      AnalysisCallback? onPartial}) {
    final c = Completer<PositionAnalysis>();
    pending.add(c);
    return c.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Engines extends EngineService {
  final KataGoEngine engine;
  _Engines(this.engine);
  @override
  Future<KataGoEngine> engineFor(AppSettings settings) async => engine;
  @override
  Future<void> cancel() async {}
}

PositionAnalysis _analysis() => PositionAnalysis(
      toMove: Stone.black,
      visits: 10,
      winrate: 0.5,
      scoreLead: 0,
      moves: const [],
      ownership: List.filled(81, 0.0),
    );

void main() {
  test('an estimate finishing mid-count does not end "counting"', () async {
    final engine = _ManualEngine();
    final c = GameController(
      engines: _Engines(engine),
      settings: () => const AppSettings(),
      setup: const GameSetup(size: 9),
      mode: GameMode.otb,
      humanColour: Stone.black,
      level: BotLevel.byId('10k'),
    );
    c.tap(const Point(4, 4));

    unawaited(c.toggleEstimate()); // estimate still running...
    await Future<void>.delayed(Duration.zero);
    unawaited(c.startScoring()); // ...when counting starts
    await Future<void>.delayed(Duration.zero);
    expect(c.isCounting, isTrue);

    engine.pending.first.complete(_analysis()); // the estimate finishes
    await Future<void>.delayed(Duration.zero);
    expect(c.isCounting, isTrue, reason: 'still counting: no score yet');

    // Counting's own two analyses finish.
    engine.pending[1].complete(_analysis());
    await Future<void>.delayed(Duration.zero);
    expect(c.isCounting, isTrue);
    engine.pending[2].complete(_analysis());
    await Future<void>.delayed(Duration.zero);
    expect(c.isCounting, isFalse);
    expect(c.scoring!.analysis, isNotNull, reason: 'the engine count is shown');
    c.dispose();
  });
}
