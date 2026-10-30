import 'package:flutter/material.dart';

import 'screens/splash_screen.dart';
import 'theme.dart';

void main() {
  runApp(const MusicCopilotApp());
}

class MusicCopilotApp extends StatelessWidget {
  const MusicCopilotApp({super.key});

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
