import 'package:flutter_test/flutter_test.dart';
import 'package:music_copilot_app/models/harmony.dart';

void main() {
  group('Explanation.fromJson', () {
    test('parses a summary and per-chord explanations', () {
      final explanation = Explanation.fromJson({
        'summary': 'This is in C major, moving through 2 chords.',
        'chords': [
          {'text': 'C — the I chord, tonic: home, where the music feels at rest'},
          {'text': 'G — the V chord, dominant: tension that pulls back toward the tonic'},
        ],
      });

      expect(explanation.summary, 'This is in C major, moving through 2 chords.');
      expect(explanation.chords, hasLength(2));
      expect(explanation.chords[0].text, 'C — the I chord, tonic: home, where the music feels at rest');
      expect(explanation.chords[1].text, 'G — the V chord, dominant: tension that pulls back toward the tonic');
    });

    test('parses an empty chord list when nothing was recognised', () {
      final explanation = Explanation.fromJson({
        'summary': 'Not enough was played to make out a clear key or chord progression.',
        'chords': [],
      });

      expect(explanation.chords, isEmpty);
    });
  });

  group('Analysis.fromJson', () {
    test('includes the explanation alongside notes, key, and chords', () {
      final analysis = Analysis.fromJson({
        'notes': [],
        'key': null,
        'chords': [],
        'explanation': {
          'summary': 'Not enough was played to make out a clear key or chord progression.',
          'chords': [],
        },
      });

      expect(
        analysis.explanation.summary,
        'Not enough was played to make out a clear key or chord progression.',
      );
    });
  });
}
