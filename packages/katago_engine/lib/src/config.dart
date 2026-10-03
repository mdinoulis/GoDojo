/// A bot playing strength. Levels with a [humanProfile] imitate human players
/// of that rank using KataGo's human-SL network; the strongest level uses
/// KataGo's own search.
class BotLevel {
  final String id;
  final String label;
  final String? humanProfile;

  /// Sampling temperature for the human policy (<1 = sharper, stronger).
  final double temperature;

  const BotLevel(this.id, this.label, this.humanProfile, this.temperature);

  bool get isFullStrength => humanProfile == null;

  static const fullStrength = BotLevel('max', 'KataGo (full strength)', null, 0);

  /// 20 kyu ... 9 dan, then full strength.
  static final List<BotLevel> all = [
    for (var k = 20; k >= 1; k--) BotLevel('${k}k', '$k kyu', 'rank_${k}k', 1.0),
    for (var d = 1; d <= 9; d++)
      BotLevel('${d}d', '$d dan', 'rank_${d}d', d <= 3 ? 0.85 : 0.7),
    fullStrength,
  ];

  static BotLevel byId(String id) =>
      all.firstWhere((l) => l.id == id, orElse: () => all.firstWhere((l) => l.id == '10k'));

  @override
  String toString() => label;
}

/// Everything needed to start and drive KataGo. Every field is
/// user-configurable so other networks or a different build can be used.
class EngineConfig {
  final String executable;
  final String model;
  final String? humanModel;
  final String configFile;
  final List<String> extraArgs;
  final String? workingDirectory;

  /// Visits for each feature.
  final int hintVisits;
  final int rateVisits;
  final int estimateVisits;
  final int reviewVisits;

  /// Search used by human-imitating bots, mainly to decide when to pass.
  final int botSearchVisits;
  final int fullStrengthVisits;

  const EngineConfig({
    required this.executable,
    required this.model,
    this.humanModel,
    required this.configFile,
    this.extraArgs = const [],
    this.workingDirectory,
    this.hintVisits = 400,
    this.rateVisits = 300,
    this.estimateVisits = 200,
    this.reviewVisits = 150,
    this.botSearchVisits = 50,
    this.fullStrengthVisits = 800,
  });

  List<String> get arguments => [
        'analysis',
        '-config', configFile,
        '-model', model,
        if (humanModel != null) ...['-human-model', humanModel!],
        ...extraArgs,
      ];

  EngineConfig copyWith({
    String? executable,
    String? model,
    String? humanModel,
    String? configFile,
    List<String>? extraArgs,
    String? workingDirectory,
    int? hintVisits,
    int? rateVisits,
    int? estimateVisits,
    int? reviewVisits,
    int? botSearchVisits,
    int? fullStrengthVisits,
  }) =>
      EngineConfig(
        executable: executable ?? this.executable,
        model: model ?? this.model,
        humanModel: humanModel ?? this.humanModel,
        configFile: configFile ?? this.configFile,
        extraArgs: extraArgs ?? this.extraArgs,
        workingDirectory: workingDirectory ?? this.workingDirectory,
        hintVisits: hintVisits ?? this.hintVisits,
        rateVisits: rateVisits ?? this.rateVisits,
        estimateVisits: estimateVisits ?? this.estimateVisits,
        reviewVisits: reviewVisits ?? this.reviewVisits,
        botSearchVisits: botSearchVisits ?? this.botSearchVisits,
        fullStrengthVisits: fullStrengthVisits ?? this.fullStrengthVisits,
      );

  Map<String, dynamic> toJson() => {
        'executable': executable,
        'model': model,
        'humanModel': humanModel,
        'configFile': configFile,
        'extraArgs': extraArgs,
        'workingDirectory': workingDirectory,
        'hintVisits': hintVisits,
        'rateVisits': rateVisits,
        'estimateVisits': estimateVisits,
        'reviewVisits': reviewVisits,
        'botSearchVisits': botSearchVisits,
        'fullStrengthVisits': fullStrengthVisits,
      };

  factory EngineConfig.fromJson(Map<String, dynamic> j) => EngineConfig(
        executable: j['executable'] as String,
        model: j['model'] as String,
        humanModel: j['humanModel'] as String?,
        configFile: j['configFile'] as String,
        extraArgs: [...?(j['extraArgs'] as List?)?.cast<String>()],
        workingDirectory: j['workingDirectory'] as String?,
        hintVisits: j['hintVisits'] as int? ?? 400,
        rateVisits: j['rateVisits'] as int? ?? 300,
        estimateVisits: j['estimateVisits'] as int? ?? 200,
        reviewVisits: j['reviewVisits'] as int? ?? 150,
        botSearchVisits: j['botSearchVisits'] as int? ?? 50,
        fullStrengthVisits: j['fullStrengthVisits'] as int? ?? 800,
      );

  /// Layout of the repo's `engine/` folder on the development PC.
  factory EngineConfig.desktop(String engineDir, {bool cpu = false}) {
    String path(String rel) => '$engineDir/$rel';
    return EngineConfig(
      executable: path(cpu ? 'windows-cpu/katago.exe' : 'windows/katago.exe'),
      model: path('models/kata1-b18c384nbt-s9996604416-d4316597426.bin.gz'),
      humanModel: path('models/b18c384nbt-humanv0.bin.gz'),
      configFile: path(cpu ? 'configs/analysis_mobile.cfg' : 'configs/analysis.cfg'),
      workingDirectory: engineDir,
    );
  }
}
