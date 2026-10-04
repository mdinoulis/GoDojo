import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_core/go_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Board surface styles.
enum BoardTheme {
  kaya('Light wood (kaya)', Color(0xFFE2BC7A), Color(0xFFC0904A), true),
  shinKaya('Pale wood (shin-kaya)', Color(0xFFEFD39C), Color(0xFFD2AC68), true),
  walnut('Dark wood (walnut)', Color(0xFFB27B48), Color(0xFF7E5128), true),
  bamboo('Bamboo', Color(0xFFE5C989), Color(0xFFC4A35D), true),
  plainTan('Plain tan', Color(0xFFDCB35C), Color(0xFFDCB35C), false),
  slateGrey('Slate grey', Color(0xFFB9BEC3), Color(0xFFB9BEC3), false),
  green('Green', Color(0xFF8DAA7B), Color(0xFF8DAA7B), false);

  const BoardTheme(this.label, this.base, this.grain, this.woodGrain);
  final String label;
  final Color base;
  final Color grain;
  final bool woodGrain;
}

enum GridColour {
  black('Black', Color(0xFF111111)),
  darkBrown('Dark brown', Color(0xFF3E2A14)),
  grey('Dark grey', Color(0xFF444444));

  const GridColour(this.label, this.color);
  final String label;
  final Color color;
}

enum StoneStyle {
  slateShell('Slate & shell (default)'),
  glossy('Glossy'),
  flat('Flat');

  const StoneStyle(this.label);
  final String label;
}

enum GameMode { vsBot, otb }

/// Persisted user preferences.
class AppSettings {
  final BoardTheme boardTheme;
  final GridColour gridColour;
  final StoneStyle stoneStyle;
  final bool showCoordinates;
  final bool showMoveNumbers;
  final bool markLastMove;
  final bool soundEnabled;

  /// Which stone recording (1-5) is used for every move.
  final int stoneSound;

  // New-game defaults
  final GameMode mode;
  final int boardSize;
  final Ruleset rules;
  final double komi;
  final int handicap;
  final String levelId;
  final Stone humanColour;

  /// Engine settings: folder with katago + models (desktop) and overrides.
  final String? engineDir;
  final Map<String, dynamic>? engineOverride;

  const AppSettings({
    this.boardTheme = BoardTheme.kaya,
    this.gridColour = GridColour.black,
    this.stoneStyle = StoneStyle.slateShell,
    this.showCoordinates = true,
    this.showMoveNumbers = false,
    this.markLastMove = true,
    this.soundEnabled = true,
    this.stoneSound = 4,
    this.mode = GameMode.vsBot,
    this.boardSize = 19,
    this.rules = Ruleset.japanese,
    this.komi = 6.5,
    this.handicap = 0,
    this.levelId = '10k',
    this.humanColour = Stone.black,
    this.engineDir,
    this.engineOverride,
  });

  AppSettings copyWith({
    BoardTheme? boardTheme,
    GridColour? gridColour,
    StoneStyle? stoneStyle,
    bool? showCoordinates,
    bool? showMoveNumbers,
    bool? markLastMove,
    bool? soundEnabled,
    int? stoneSound,
    GameMode? mode,
    int? boardSize,
    Ruleset? rules,
    double? komi,
    int? handicap,
    String? levelId,
    Stone? humanColour,
    String? engineDir,
    Map<String, dynamic>? engineOverride,
    bool clearEngineOverride = false,
  }) =>
      AppSettings(
        boardTheme: boardTheme ?? this.boardTheme,
        gridColour: gridColour ?? this.gridColour,
        stoneStyle: stoneStyle ?? this.stoneStyle,
        showCoordinates: showCoordinates ?? this.showCoordinates,
        showMoveNumbers: showMoveNumbers ?? this.showMoveNumbers,
        markLastMove: markLastMove ?? this.markLastMove,
        soundEnabled: soundEnabled ?? this.soundEnabled,
        stoneSound: stoneSound ?? this.stoneSound,
        mode: mode ?? this.mode,
        boardSize: boardSize ?? this.boardSize,
        rules: rules ?? this.rules,
        komi: komi ?? this.komi,
        handicap: handicap ?? this.handicap,
        levelId: levelId ?? this.levelId,
        humanColour: humanColour ?? this.humanColour,
        engineDir: engineDir ?? this.engineDir,
        engineOverride:
            clearEngineOverride ? null : (engineOverride ?? this.engineOverride),
      );

  Map<String, dynamic> toJson() => {
        'boardTheme': boardTheme.name,
        'gridColour': gridColour.name,
        'stoneStyle': stoneStyle.name,
        'showCoordinates': showCoordinates,
        'showMoveNumbers': showMoveNumbers,
        'markLastMove': markLastMove,
        'soundEnabled': soundEnabled,
        'stoneSound': stoneSound,
        'mode': mode.name,
        'boardSize': boardSize,
        'rules': rules.name,
        'komi': komi,
        'handicap': handicap,
        'levelId': levelId,
        'humanColour': humanColour.name,
        'engineDir': engineDir,
        'engineOverride': engineOverride,
      };

  static T _enum<T extends Enum>(List<T> values, Object? name, T fallback) =>
      values.firstWhere((v) => v.name == name, orElse: () => fallback);

  factory AppSettings.fromJson(Map<String, dynamic> j) {
    const d = AppSettings();
    return AppSettings(
      boardTheme: _enum(BoardTheme.values, j['boardTheme'], d.boardTheme),
      gridColour: _enum(GridColour.values, j['gridColour'], d.gridColour),
      stoneStyle: _enum(StoneStyle.values, j['stoneStyle'], d.stoneStyle),
      showCoordinates: j['showCoordinates'] as bool? ?? d.showCoordinates,
      showMoveNumbers: j['showMoveNumbers'] as bool? ?? d.showMoveNumbers,
      markLastMove: j['markLastMove'] as bool? ?? d.markLastMove,
      soundEnabled: j['soundEnabled'] as bool? ?? d.soundEnabled,
      stoneSound: ((j['stoneSound'] as int?) ?? d.stoneSound).clamp(1, 5),
      mode: _enum(GameMode.values, j['mode'], d.mode),
      boardSize: j['boardSize'] as int? ?? d.boardSize,
      rules: _enum(Ruleset.values, j['rules'], d.rules),
      komi: (j['komi'] as num?)?.toDouble() ?? d.komi,
      handicap: j['handicap'] as int? ?? d.handicap,
      levelId: j['levelId'] as String? ?? d.levelId,
      humanColour: _enum(Stone.values, j['humanColour'], d.humanColour),
      engineDir: j['engineDir'] as String?,
      engineOverride: j['engineOverride'] as Map<String, dynamic>?,
    );
  }
}

final sharedPrefsProvider =
    Provider<SharedPreferences>((ref) => throw UnimplementedError());

class SettingsNotifier extends Notifier<AppSettings> {
  static const _key = 'settings.v1';

  @override
  AppSettings build() {
    final raw = ref.read(sharedPrefsProvider).getString(_key);
    if (raw == null) return const AppSettings();
    try {
      return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const AppSettings();
    }
  }

  void update(AppSettings Function(AppSettings) change) {
    state = change(state);
    ref.read(sharedPrefsProvider).setString(_key, jsonEncode(state.toJson()));
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
