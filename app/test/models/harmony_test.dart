import 'package:flutter_test/flutter_test.dart';
import 'package:music_copilot_app/models/harmony.dart';

Map<String, dynamic> _chord(int bar, String symbol, {String fit = 'fits'}) => {
  'bar': bar,
  'start_time': bar * 2.4,
  'end_time': (bar + 1) * 2.4,
  'symbol': symbol,
  'root': symbol[0],
  'quality': 'maj',
  'pitch_classes': [0, 4, 7],
  'roman': 'I',
  'function': 'tonic',
  'kind': 'diatonic',
  'fit': fit,
  'reasons': ['Your C and G are in C, so it feels settled.'],
};

void main() {
  test('MusicKey parses the runner-up', () {
    final key = MusicKey.fromJson({
      'tonic': 'C',
      'mode': 'major',
      'name': 'C major',
      'confidence': 0.9,
      'runner_up': {'tonic': 'A', 'mode': 'minor', 'name': 'A minor', 'confidence': 0.7},
    });
    expect(key.name, 'C major');
    expect(key.runnerUp!.name, 'A minor');
    expect(key.toJson(), {'tonic': 'C', 'mode': 'major'});
  });

  test('BeatGrid parses beats and nudges keep the rest', () {
    final grid = BeatGrid.fromJson({
      'bpm': 100,
      'downbeat': 0.3,
      'meter': 4,
      'guessed': true,
      'beats': [
        {'time': 0.3, 'downbeat': true},
        {'time': 0.9, 'downbeat': false},
      ],
    });
    expect(grid.beatLength, closeTo(0.6, 1e-9));
    expect(grid.beats.first.downbeat, isTrue);
    final nudged = grid.copyWith(downbeat: 0.9);
    expect(nudged.bpm, 100);
    expect(nudged.toJson()['downbeat'], 0.9);
  });

  test('Analysis parses route, melody and progressions', () {
    final analysis = Analysis.fromJson({
      'notes': [],
      'melody': [
        {'pitch': 'C4', 'midi_pitch': 60, 'start_time': 0.0, 'end_time': 0.5, 'confidence': 0.8},
      ],
      'route': 'polyphonic',
      'route_note': 'Suggestions follow its top line for now.',
      'grid': {'bpm': 100, 'downbeat': 0.0, 'meter': 4, 'guessed': false, 'beats': []},
      'key': {'tonic': 'C', 'mode': 'major', 'name': 'C major', 'confidence': 0.9},
      'progressions': [
        {
          'kind': 'bold',
          'source': 'llm',
          'character': 'dreamy with a dark twist',
          'score': 12.5,
          'chords': [_chord(0, 'C'), _chord(1, 'Ab', fit: 'colour')],
        },
      ],
      'insight': 'Your tune ends on C.',
    });
    expect(analysis.route, 'polyphonic');
    expect(analysis.melody.single.midiPitch, 60);
    final bold = analysis.suggestions.progressions.single;
    expect(bold.title, 'Bold');
    expect(bold.source, 'llm');
    expect(bold.chords[1].fit, ChordFit.colour);
    expect(bold.chords[1].toBackingJson()['pitch_classes'], [0, 4, 7]);
    expect(analysis.suggestions.grid!.guessed, isFalse);
    expect(analysis.suggestions.insight, 'Your tune ends on C.');
  });

  test('An empty take parses to no suggestions', () {
    final analysis = Analysis.fromJson({'notes': [], 'grid': null, 'key': null, 'progressions': []});
    expect(analysis.suggestions.progressions, isEmpty);
    expect(analysis.suggestions.key, isNull);
  });
}
