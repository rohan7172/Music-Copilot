import 'package:flutter_test/flutter_test.dart';
import 'package:music_copilot_app/audio/waveform.dart';
import 'package:music_copilot_app/models/note.dart';

Note note(double start, double end, {double confidence = 0.7}) {
  return Note(
    pitch: 'C4',
    midiPitch: 60,
    startTime: start,
    endTime: end,
    confidence: confidence,
  );
}

void main() {
  group('Waveform.fromNoteActivity', () {
    test('rises where notes sound and falls to zero where none do', () {
      final waveform = Waveform.fromNoteActivity([note(0, 1)], 2.0);

      expect(waveform.duration, 2.0);
      expect(waveform.at(0.5), greaterThan(0));
      expect(waveform.at(1.9), 0);
    });

    test('is louder where notes overlap than where only one sounds', () {
      final notes = [note(0, 2), note(0.5, 1.5)];
      final waveform = Waveform.fromNoteActivity(notes, 2.0);

      expect(waveform.at(1.0), greaterThan(waveform.at(1.9)));
    });

    test('is empty with no notes', () {
      final waveform = Waveform.fromNoteActivity([], 3.0);

      expect(waveform.duration, 3.0);
      expect(waveform.envelope.every((v) => v == 0), isTrue);
    });
  });
}
