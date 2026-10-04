import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_core/go_core.dart';
import 'package:path_provider/path_provider.dart';

import 'review_screen.dart';

/// Lists games saved as SGF and opens one for review.
class SavedGamesScreen extends StatefulWidget {
  const SavedGamesScreen({super.key});

  @override
  State<SavedGamesScreen> createState() => _SavedGamesScreenState();
}

class _SavedGamesScreenState extends State<SavedGamesScreen> {
  List<File>? files;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dir = await getApplicationDocumentsDirectory();
    // "GoStudy" is the folder used before the app was renamed to GoDojo.
    final list = <File>[
      for (final name in ['GoDojo', 'GoStudy'])
        if (Directory('${dir.path}${Platform.pathSeparator}$name').existsSync())
          ...Directory('${dir.path}${Platform.pathSeparator}$name')
              .listSync()
              .whereType<File>()
              .where((f) => f.path.toLowerCase().endsWith('.sgf')),
    ];
    list.sort((a, b) => b.path.compareTo(a.path));
    if (mounted) setState(() => files = list);
  }

  @override
  Widget build(BuildContext context) {
    final fs = files;
    return Scaffold(
      appBar: AppBar(title: const Text('Saved games')),
      body: fs == null
          ? const Center(child: CircularProgressIndicator())
          : fs.isEmpty
              ? const Center(child: Text('No saved games yet. Use the save icon during a game.'))
              : ListView.separated(
                  itemCount: fs.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final f = fs[i];
                    final name = f.path.split(Platform.pathSeparator).last;
                    return ListTile(
                      leading: const Icon(Icons.description_outlined),
                      title: Text(name),
                      subtitle: Text(_describe(f)),
                      trailing: const Icon(Icons.query_stats),
                      onTap: () => _open(f),
                    );
                  },
                ),
    );
  }

  String _describe(File f) {
    try {
      final s = f.readAsStringSync();
      String? prop(String k) => RegExp('$k' r'\[([^\]]*)\]').firstMatch(s)?.group(1);
      final size = prop('SZ') ?? '19';
      return '${prop('PB') ?? 'Black'} vs ${prop('PW') ?? 'White'} · $size×$size'
          '${prop('RE') != null ? ' · ${prop('RE')}' : ''}';
    } catch (_) {
      return '';
    }
  }

  void _open(File f) {
    try {
      final s = f.readAsStringSync();
      final game = Sgf.import(s);
      String? prop(String k) => RegExp('$k' r'\[([^\]]*)\]').firstMatch(s)?.group(1);
      final pb = prop('PB') ?? 'Black', pw = prop('PW') ?? 'White';
      final me = pb == 'You' ? Stone.black : pw == 'You' ? Stone.white : null;
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ReviewScreen(game: game, player: me, blackName: pb, whiteName: pw)));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open: $e')));
    }
  }
}
