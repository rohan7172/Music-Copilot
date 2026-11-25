import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';

import 'screens/splash_screen.dart';
import 'services/local_backend/local_backend.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // The desktop app runs its own backend; elsewhere this does nothing.
  unawaited(LocalBackend.instance.start());
  runApp(const MusicCopilotApp());
}

class MusicCopilotApp extends StatefulWidget {
  const MusicCopilotApp({super.key});

  @override
  State<MusicCopilotApp> createState() => _MusicCopilotAppState();
}

class _MusicCopilotAppState extends State<MusicCopilotApp> {
  // Stops the backend the app started when the app quits. If the app is
  // killed instead, the backend notices its stdin close and stops itself.
  late final AppLifecycleListener _lifecycle = AppLifecycleListener(
    onExitRequested: () async {
      await LocalBackend.instance.stop();
      return AppExitResponse.exit;
    },
  );

  @override
  void initState() {
    super.initState();
    _lifecycle;
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Music Copilot',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const SplashScreen(),
    );
  }
}
