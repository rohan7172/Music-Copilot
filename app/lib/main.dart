import 'package:flutter/material.dart';

import 'screens/record_screen.dart';

void main() {
  runApp(const MusicCopilotApp());
}

class MusicCopilotApp extends StatelessWidget {
  const MusicCopilotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Music Copilot',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const RecordScreen(),
    );
  }
}
