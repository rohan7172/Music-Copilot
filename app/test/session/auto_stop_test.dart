import 'package:flutter_test/flutter_test.dart';
import 'package:music_copilot_app/session/session_controller.dart';

void main() {
  group('a hummed take', () {
    test('keeps going before 10 s, however quiet', () {
      expect(
        shouldAutoStop(recorded: 9, lastLoudAt: 1, songMode: false),
        isFalse,
      );
    });

    test('stops after 3 s of quiet once 10 s long', () {
      expect(
        shouldAutoStop(recorded: 12, lastLoudAt: 9, songMode: false),
        isTrue,
      );
      expect(
        shouldAutoStop(recorded: 12, lastLoudAt: 10, songMode: false),
        isFalse,
      );
    });
  });

  group('a song playing nearby', () {
    test('never stops on a quiet stretch', () {
      expect(
        shouldAutoStop(recorded: 30, lastLoudAt: 10, songMode: true),
        isFalse,
      );
    });

    test('stops once it has listened long enough', () {
      const cap = SessionController.songListenSeconds;
      expect(
        shouldAutoStop(recorded: cap - 0.1, lastLoudAt: 0, songMode: true),
        isFalse,
      );
      expect(
        shouldAutoStop(recorded: cap, lastLoudAt: cap, songMode: true),
        isTrue,
      );
    });
  });
}
