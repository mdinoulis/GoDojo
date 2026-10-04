import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'engine_service.dart';
import 'screens/home_screen.dart';
import 'settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _migrateWindowsSettings();
  final prefs = await SharedPreferences.getInstance();
  runApp(ProviderScope(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    child: const GoDojoApp(),
  ));
}

class GoDojoApp extends ConsumerStatefulWidget {
  const GoDojoApp({super.key});

  @override
  ConsumerState<GoDojoApp> createState() => _GoDojoAppState();
}

class _GoDojoAppState extends ConsumerState<GoDojoApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Make sure the KataGo process does not outlive the app.
    _lifecycle = AppLifecycleListener(onExitRequested: () async {
      await ref.read(engineServiceProvider).shutdown();
      return AppExitResponse.exit;
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF8D6E3F);
    return MaterialApp(
      title: 'GoDojo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

/// The app used to be called "Go Study"; on Windows its settings lived in
/// %APPDATA%\com.gostudy\go_study. Copy them over once so they survive the
/// rename to GoDojo.
Future<void> _migrateWindowsSettings() async {
  if (!Platform.isWindows) return;
  try {
    final appData = Platform.environment['APPDATA'];
    if (appData == null) return;
    final old = File('$appData/com.gostudy/go_study/shared_preferences.json');
    final dir = await getApplicationSupportDirectory();
    final current = File('${dir.path}/shared_preferences.json');
    if (old.existsSync() && !current.existsSync()) {
      await dir.create(recursive: true);
      await old.copy(current.path);
    }
  } catch (_) {
    // Not important enough to stop the app starting.
  }
}
