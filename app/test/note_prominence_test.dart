import 'package:flutter_test/flutter_test.dart';
import 'package:music_copilot_app/models/note.dart';
import 'package:music_copilot_app/note_prominence.dart';

Note note(int midiPitch, double start, double end) {
  return Note(pitch: 'x', midiPitch: midiPitch, startTime: start, endTime: end, confidence: 0.7);
}

void main() {
  group('isProminentNote', () {
    test('a solo note with no overlap is prominent', () {
      final notes = [note(60, 0, 1)];
      expect(isProminentNote(notes, 0), isTrue);
    });

    test('two non-overlapping notes are both prominent regardless of pitch', () {
      final notes = [note(72, 0, 1), note(60, 1, 2)];
      expect(isProminentNote(notes, 0), isTrue);
      expect(isProminentNote(notes, 1), isTrue);
    });

    test('of two overlapping notes, only the higher pitch is prominent', () {
      final notes = [note(60, 0, 1), note(72, 0.2, 0.8)];
      expect(isProminentNote(notes, 0), isFalse);
      expect(isProminentNote(notes, 1), isTrue);
    });

    test('of three overlapping notes, only the single highest is prominent', () {
      final notes = [note(60, 0, 1), note(72, 0.1, 0.9), note(67, 0.2, 0.8)];
      expect(isProminentNote(notes, 0), isFalse);
      expect(isProminentNote(notes, 1), isTrue);
      expect(isProminentNote(notes, 2), isFalse);
    });

    test('notes that only just touch do not count as overlapping', () {
      final notes = [note(72, 0, 1), note(60, 1, 2)];
      // endTime of note 0 equals startTime of note 1 - not a real overlap.
      expect(isProminentNote(notes, 1), isTrue);
    });
  });
}
