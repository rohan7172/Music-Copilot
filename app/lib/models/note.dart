class Note {
  Note({
    required this.pitch,
    required this.midiPitch,
    required this.startTime,
    required this.endTime,
    required this.confidence,
  });

  factory Note.fromJson(Map<String, dynamic> json) {
    return Note(
      pitch: json['pitch'] as String,
      midiPitch: json['midi_pitch'] as int,
      startTime: (json['start_time'] as num).toDouble(),
      endTime: (json['end_time'] as num).toDouble(),
      confidence: (json['confidence'] as num).toDouble(),
    );
  }

  final String pitch;
  final int midiPitch;
  final double startTime;
  final double endTime;
  final double confidence;
}
