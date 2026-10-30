import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_copilot_app/models/note.dart';
import 'package:music_copilot_app/widgets/contour/contour_layout.dart';

Note note(int midi, double start, double end) => Note(
  pitch: midiName(midi),
  midiPitch: midi,
  startTime: start,
  endTime: end,
  confidence: 0.9,
);

void main() {
  final notes = [note(69, 0, 1), note(72, 1, 2), note(71, 2, 3), note(67, 3.5, 4)];
  final layout = ContourLayout(size: const Size(300, 176), notes: notes, duration: 4);

  test('names MIDI pitches with octaves', () {
    expect(midiName(60), 'C4');
    expect(midiName(69), 'A4');
    expect(midiName(73), 'C#5');
  });

  test('time maps across the roll and back', () {
    expect(layout.xForTime(0), ContourLayout.labelGutter);
    expect(layout.xForTime(4), layout.right);
    expect(layout.timeForX(layout.xForTime(1.5)), closeTo(1.5, 1e-9));
  });

  test('higher notes sit higher', () {
    expect(layout.pill(1).center.dy, lessThan(layout.pill(0).center.dy));
    expect(layout.pill(3).center.dy, greaterThan(layout.pill(0).center.dy));
  });

  test('a very short note still gets a tappable pill', () {
    final short = ContourLayout(
      size: const Size(300, 176),
      notes: [note(60, 1, 1.001)],
      duration: 10,
    );
    expect(short.pill(0).width, greaterThanOrEqualTo(ContourLayout.minPillWidth));
    expect(short.pillFloor, ContourLayout.labelPillWidth); // one note: room for its name
  });

  test('tapping a pill finds its note, empty space finds none', () {
    expect(layout.hitNote(layout.pill(2).center), 2);
    expect(layout.hitNote(const Offset(5, 5)), isNull);
  });

  test('grid is labelled top to bottom within the fitted range', () {
    final grid = layout.gridPitches();
    expect(grid.first, layout.fitted.hi);
    expect(grid, orderedEquals([...grid]..sort((a, b) => b.compareTo(a))));
    expect(grid.length, lessThanOrEqualTo(5));
  });

  test('the melody thread skips overlapping notes and breaks on long rests', () {
    final runs = layout.thread(maxGap: 0.4);
    // 0→1→2 join up; the 0.5 s rest before the last note breaks the run,
    // leaving it alone (a one-point run is dropped).
    expect(runs.length, 1);
    expect(runs.single.length, 3);

    final stacked = ContourLayout(
      size: const Size(300, 176),
      notes: [note(60, 0, 2), note(64, 0, 2), note(67, 2, 3)],
      duration: 3,
    );
    expect(stacked.thread().single.length, 2);
  });

  test('chords sit in the ribbon above the roll, tappable by span', () {
    final spans = [(0.0, 2.0), (2.0, 4.0)];
    final first = layout.chordRect(0, 2);
    expect(first.bottom, lessThanOrEqualTo(ContourLayout.ribbonHeight));
    expect(layout.pill(0).top, greaterThan(ContourLayout.ribbonHeight));
    expect(layout.hitChord(layout.chordRect(2, 4).center, spans), 1);
    expect(layout.hitChord(layout.pill(0).center, spans), isNull);
  });
}
