import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'engine_service.dart';
import 'screens/home_screen.dart';
import 'settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(ProviderScope(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    child: const GoStudyApp(),
  ));
}

class GoStudyApp extends ConsumerStatefulWidget {
  const GoStudyApp({super.key});

  @override
  ConsumerState<GoStudyApp> createState() => _GoStudyAppState();
}

class _GoStudyAppState extends ConsumerState<GoStudyApp> {
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
      title: 'Go Study',
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
