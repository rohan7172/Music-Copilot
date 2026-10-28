import 'package:flutter_test/flutter_test.dart';
import 'package:music_copilot_app/models/harmony.dart';

void main() {
  group('SummarySegment.fromJson', () {
    test('parses plain text with no chord link', () {
      final segment = SummarySegment.fromJson({'text': 'This is in C major, '});

      expect(segment.text, 'This is in C major, ');
      expect(segment.chordIndex, isNull);
    });

    test('parses a chord-linked segment', () {
      final segment = SummarySegment.fromJson({'text': 'V', 'chord_index': 1});

      expect(segment.text, 'V');
      expect(segment.chordIndex, 1);
    });
  });

  group('Explanation.fromJson', () {
    test('parses a summary made of segments and per-chord explanations', () {
      final explanation = Explanation.fromJson({
        'summary': [
          {'text': 'This is in C major, moving through a '},
          {'text': 'ii', 'chord_index': 0},
          {'text': '–'},
          {'text': 'V', 'chord_index': 1},
          {'text': ' progression.'},
        ],
        'chords': [
          {'text': 'C — the I chord, tonic: home, where the music feels at rest'},
          {'text': 'G — the V chord, dominant: tension that pulls back toward the tonic'},
        ],
      });

      expect(explanation.summary, hasLength(5));
      expect(explanation.summary[1].text, 'ii');
      expect(explanation.summary[1].chordIndex, 0);
      expect(explanation.summary[2].chordIndex, isNull);
      expect(explanation.chords, hasLength(2));
      expect(explanation.chords[0].text, 'C — the I chord, tonic: home, where the music feels at rest');
    });

    test('parses an empty chord list when nothing was recognised', () {
      final explanation = Explanation.fromJson({
        'summary': [
          {'text': 'Not enough was played to make out a clear key or chord progression.'},
        ],
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
          'summary': [
            {'text': 'Not enough was played to make out a clear key or chord progression.'},
          ],
          'chords': [],
        },
      });

      expect(
        analysis.explanation.summary.single.text,
        'Not enough was played to make out a clear key or chord progression.',
      );
    });
  });
}
