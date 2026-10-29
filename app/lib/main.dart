import 'package:flutter/material.dart';

import 'screens/session_screen.dart';
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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Palette.accent,
          surface: Palette.paper,
        ),
        scaffoldBackgroundColor: Palette.paper,
        useMaterial3: true,
      ),
      home: const SessionScreen(),
    );
  }
}
