import 'game.dart';
import 'point.dart';
import 'rules.dart';

/// Minimal SGF (FF[4]) reader/writer for the main line of a game.
class Sgf {
  static String export(Game game,
      {String? blackName, String? whiteName, DateTime? date, String? app}) {
    final sb = StringBuffer('(;FF[4]GM[1]CA[UTF-8]');
    sb.write('AP[${_esc(app ?? 'GoApp')}]');
    sb.write('SZ[${game.size}]');
    sb.write('KM[${_num(game.setup.komi)}]');
    sb.write('RU[${_esc(game.rules.displayName)}]');
    if (blackName != null) sb.write('PB[${_esc(blackName)}]');
    if (whiteName != null) sb.write('PW[${_esc(whiteName)}]');
    if (date != null) {
      sb.write('DT[${date.toIso8601String().substring(0, 10)}]');
    }
    if (game.result != null) sb.write('RE[${game.result!.toSgf()}]');
    if (game.handicapStones.isNotEmpty) {
      sb.write('HA[${game.handicapStones.length}]AB');
      for (final p in game.handicapStones) {
        sb.write('[${p.toSgf()}]');
      }
      if (game.firstPlayer == Stone.white) sb.write('PL[W]');
    }
    for (final m in game.moves) {
      sb.write(';${m.color.letter}[${m.point?.toSgf() ?? ''}]');
    }
    sb.write(')');
    return sb.toString();
  }

  /// Parses the main line of an SGF game into a [Game].
  static Game import(String sgf) {
    final nodes = _parseMainLine(sgf);
    if (nodes.isEmpty) throw const FormatException('Empty SGF');
    final root = nodes.first;
    final size = int.tryParse(root['SZ']?.first.split(':').first ?? '') ?? 19;
    final rules = Ruleset.fromName(root['RU']?.first ?? 'japanese');
    final ha = int.tryParse(root['HA']?.first ?? '') ?? 0;
    final komi = double.tryParse(root['KM']?.first ?? '') ??
        GameSetup.defaultKomi(rules, ha);
    final ab = [
      for (final v in root['AB'] ?? const <String>[]) ..._expand(v, size)
    ];
    final game = Game(
      GameSetup(size: size, rules: rules, komi: komi, handicap: ab.length),
      handicapStones: ab,
    );
    for (final node in nodes) {
      for (final key in const ['B', 'W']) {
        final v = node[key];
        if (v != null) {
          game.playMove(Move(Stone.fromLetter(key), Point.fromSgf(v.first, size)));
        }
      }
    }
    final re = root['RE']?.first;
    if (re != null) {
      final r = GameResult.fromSgf(re);
      if (r != null && r.reason != ResultReason.score) game.setResult(r);
    }
    return game;
  }

  /// Expands compressed point lists like "aa:cc".
  static List<Point> _expand(String v, int size) {
    if (!v.contains(':')) {
      final p = Point.fromSgf(v, size);
      return p == null ? const [] : [p];
    }
    final parts = v.split(':');
    final a = Point.fromSgf(parts[0], size)!, b = Point.fromSgf(parts[1], size)!;
    return [
      for (var y = a.y; y <= b.y; y++)
        for (var x = a.x; x <= b.x; x++) Point(x, y)
    ];
  }

  static List<Map<String, List<String>>> _parseMainLine(String s) {
    final nodes = <Map<String, List<String>>>[];
    var i = s.indexOf('(');
    if (i < 0) return nodes;
    i++;
    var depth = 1;
    Map<String, List<String>>? cur;
    String? key;
    while (i < s.length && depth > 0) {
      final c = s[i];
      if (c == '(') {
        // Only follow the first variation: skip any sibling variations later.
        depth++;
        i++;
      } else if (c == ')') {
        // End of the first variation at this depth: stop the main line.
        break;
      } else if (c == ';') {
        cur = {};
        nodes.add(cur);
        key = null;
        i++;
      } else if (c == '[') {
        final sb = StringBuffer();
        i++;
        while (i < s.length && s[i] != ']') {
          if (s[i] == '\\' && i + 1 < s.length) i++;
          sb.write(s[i]);
          i++;
        }
        i++; // skip ]
        if (cur != null && key != null) {
          (cur[key] ??= []).add(sb.toString());
        }
      } else if (RegExp(r'[A-Za-z]').hasMatch(c)) {
        final start = i;
        while (i < s.length && RegExp(r'[A-Za-z]').hasMatch(s[i])) {
          i++;
        }
        key = s.substring(start, i).replaceAll(RegExp(r'[a-z]'), '');
      } else {
        i++;
      }
    }
    return nodes;
  }

  static String _esc(String v) =>
      v.replaceAll('\\', '\\\\').replaceAll(']', '\\]');

  static String _num(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}
