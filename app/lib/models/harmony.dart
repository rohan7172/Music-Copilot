import 'note.dart';

/// The key the backend detected, e.g. "C major".
class MusicKey {
  MusicKey({required this.name, required this.confidence});

  factory MusicKey.fromJson(Map<String, dynamic> json) {
    return MusicKey(
      name: json['name'] as String,
      confidence: (json['confidence'] as num).toDouble(),
    );
  }

  final String name;
  final double confidence;
}

/// A chord the backend found, spanning [startTime]..[endTime] seconds.
class Chord {
  Chord({
    required this.name,
    required this.roman,
    required this.notes,
    required this.pitchClasses,
    required this.startTime,
    required this.endTime,
  });

  factory Chord.fromJson(Map<String, dynamic> json) {
    return Chord(
      name: json['name'] as String,
      roman: json['roman'] as String,
      notes: (json['notes'] as List<dynamic>).cast<String>(),
      pitchClasses: (json['pitch_classes'] as List<dynamic>).cast<int>(),
      startTime: (json['start_time'] as num).toDouble(),
      endTime: (json['end_time'] as num).toDouble(),
    );
  }

  /// Display name, e.g. "Am" or "G7".
  final String name;

  /// Function in the key, e.g. "vi" or "V7".
  final String roman;

  /// Chord tones, spelled for the key, e.g. ["A", "C", "E"].
  final List<String> notes;

  /// The same tones as pitch classes (C = 0 ... B = 11).
  final List<int> pitchClasses;

  final double startTime;
  final double endTime;

  /// Whether [note] is one of this chord's tones and sounds during it.
  bool contains(Note note) =>
      pitchClasses.contains(note.midiPitch % 12) &&
      note.startTime < endTime &&
      note.endTime > startTime;
}

/// Everything /analyze returns for a recording.
class Analysis {
  Analysis({required this.notes, required this.key, required this.chords});

  factory Analysis.fromJson(Map<String, dynamic> json) {
    final key = json['key'];
    return Analysis(
      notes: [
        for (final n in json['notes'] as List<dynamic>)
          Note.fromJson(n as Map<String, dynamic>),
      ],
      key: key == null ? null : MusicKey.fromJson(key as Map<String, dynamic>),
      chords: [
        for (final c in (json['chords'] as List<dynamic>? ?? const []))
          Chord.fromJson(c as Map<String, dynamic>),
      ],
    );
  }

  final List<Note> notes;
  final MusicKey? key;
  final List<Chord> chords;
}
