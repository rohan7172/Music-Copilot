import 'package:flutter/material.dart';

import '../models/note.dart';

class ResultsScreen extends StatelessWidget {
  const ResultsScreen({super.key, required this.notes});

  final List<Note> notes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Detected Notes')),
      body: notes.isEmpty
          ? const Center(child: Text('No notes detected. Try recording again.'))
          : ListView.separated(
              itemCount: notes.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final note = notes[index];
                return ListTile(
                  leading: CircleAvatar(child: Text(note.pitch)),
                  title: Text(note.pitch),
                  subtitle: Text(
                    '${note.startTime.toStringAsFixed(2)}s – '
                    '${note.endTime.toStringAsFixed(2)}s',
                  ),
                  trailing: Text('${(note.confidence * 100).toStringAsFixed(0)}%'),
                );
              },
            ),
    );
  }
}
