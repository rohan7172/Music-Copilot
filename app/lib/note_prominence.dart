import 'models/note.dart';

/// Whether [notes][index] is the "lead" voice at that moment: true unless
/// some other note sounding at the same time is pitched higher. A note with
/// nothing sounding alongside it is trivially prominent, so solo passages
/// are unaffected — this only matters where notes genuinely overlap.
bool isProminentNote(List<Note> notes, int index) {
  final note = notes[index];
  for (var i = 0; i < notes.length; i++) {
    if (i == index) continue;
    final other = notes[i];
    final overlaps = other.startTime < note.endTime && other.endTime > note.startTime;
    if (overlaps && other.midiPitch > note.midiPitch) return false;
  }
  return true;
}
